package handlers

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

var validDisputeReasons = map[string]bool{
	"not_received":     true,
	"wrong_item":       true,
	"damaged":          true,
	"duplicate_charge": true,
	"not_as_described": true,
	"other":            true,
}

type createDisputeRequest struct {
	InvoiceReference string `json:"invoice_reference"`
	ReasonCategory   string `json:"reason_category"`
	Description      string `json:"description"`
}

// CreateDispute logs a customer complaint against an invoice (Section 7.7).
// Looked up by reference rather than requiring the invoice's UUID — staff
// have the reference from the checkout link, records view, or a WhatsApp
// screenshot, not the internal id.
func (h *Handler) CreateDispute(c *fiber.Ctx) error {
	var req createDisputeRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.InvoiceReference == "" {
		return badRequest(c, "invoice_reference is required")
	}
	if !validDisputeReasons[req.ReasonCategory] {
		return badRequest(c, "reason_category must be one of: not_received, wrong_item, damaged, duplicate_charge, not_as_described, other")
	}

	invoice, err := h.Queries.GetInvoiceByReference(c.Context(), req.InvoiceReference)
	if errors.Is(err, pgx.ErrNoRows) {
		return badRequest(c, "no invoice found with that reference")
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load invoice"})
	}

	payload, ok := actorPayload(c)
	if !ok {
		return fiber.NewError(fiber.StatusUnauthorized, "missing auth payload")
	}

	dispute, err := h.Queries.CreateDispute(c.Context(), db.CreateDisputeParams{
		InvoiceID:      invoice.ID,
		ReasonCategory: req.ReasonCategory,
		Description:    textOrNull(req.Description),
		CreatedBy:      toPgUUID(payload.ActorID),
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create dispute"})
	}

	after, _ := json.Marshal(fiber.Map{"reason_category": dispute.ReasonCategory, "invoice_reference": invoice.Reference})
	if err := writeAdminAuditLog(c, h, "dispute.create", "dispute", dispute.ID, nil, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.Status(fiber.StatusCreated).JSON(dispute)
}

func (h *Handler) ListDisputesAdmin(c *fiber.Ctx) error {
	limit := int32(c.QueryInt("limit", 100))
	offset := int32(c.QueryInt("offset", 0))

	disputes, err := h.Queries.ListDisputesAdmin(c.Context(), db.ListDisputesAdminParams{
		StatusFilter: c.Query("status"),
		RowLimit:     limit,
		RowOffset:    offset,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list disputes"})
	}
	return c.JSON(disputes)
}

type refundablePayment struct {
	db.Payment
	RefundablePesewas int64 `json:"refundable_pesewas"`
}

// GetDisputeDetail includes the invoice's successful payments alongside the
// dispute so the Back Office can offer a refund-amount picker without a
// second round trip — each payment's refundable balance is its own amount
// minus whatever's already been refunded against it (a payment can be
// partially refunded across more than one dispute).
func (h *Handler) GetDisputeDetail(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid dispute id")
	}

	dispute, err := h.Queries.GetDispute(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load dispute"})
	}

	payments, err := h.Queries.ListPaymentsByInvoice(c.Context(), dispute.InvoiceID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load payments"})
	}
	refundable := make([]refundablePayment, 0, len(payments))
	for _, p := range payments {
		if p.Status != "success" {
			continue
		}
		refundable = append(refundable, refundablePayment{
			Payment:           p,
			RefundablePesewas: p.AmountPesewas - p.RefundedAmountPesewas,
		})
	}

	return c.JSON(fiber.Map{"dispute": dispute, "refundable_payments": refundable})
}

// disputeStatusTransitions: open can move anywhere; investigating can only
// resolve. resolved_refunded/resolved_denied are terminal.
var disputeStatusTransitions = map[string][]string{
	"open":          {"investigating", "resolved_refunded", "resolved_denied"},
	"investigating": {"resolved_refunded", "resolved_denied"},
}

type resolveDisputeRequest struct {
	Status              string `json:"status"`
	ResolutionNotes     string `json:"resolution_notes"`
	RefundPaymentID     string `json:"refund_payment_id"`
	RefundAmountPesewas int64  `json:"refund_amount_pesewas"`
}

// ResolveDispute drives a dispute's status forward, including the "trigger
// a refund through the PSP where warranted" half of Section 7.7. The
// Paystack call happens outside any DB transaction (it's an external HTTP
// request, not something Postgres can roll back) — only once it succeeds
// do the payment/invoice/dispute rows update together.
func (h *Handler) ResolveDispute(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid dispute id")
	}

	var req resolveDisputeRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	dispute, err := h.Queries.GetDispute(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load dispute"})
	}

	allowed := disputeStatusTransitions[dispute.Status]
	valid := false
	for _, s := range allowed {
		if s == req.Status {
			valid = true
			break
		}
	}
	if !valid {
		return badRequest(c, "cannot move dispute from "+dispute.Status+" to "+req.Status)
	}

	if req.Status == "resolved_denied" && req.ResolutionNotes == "" {
		return badRequest(c, "resolution_notes is required when denying")
	}

	payload, ok := actorPayload(c)
	if !ok {
		return fiber.NewError(fiber.StatusUnauthorized, "missing auth payload")
	}

	// Non-terminal transition: no resolution fields, no PSP call.
	if req.Status == "investigating" {
		updated, err := h.Queries.SetDisputeStatus(c.Context(), db.SetDisputeStatusParams{ID: id, Status: req.Status})
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update dispute"})
		}
		before, _ := json.Marshal(fiber.Map{"status": dispute.Status})
		after, _ := json.Marshal(fiber.Map{"status": updated.Status})
		if err := writeAdminAuditLog(c, h, "dispute.status_change", "dispute", id, before, after); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
		}
		return c.JSON(updated)
	}

	var refundPaymentID pgtype.UUID
	if req.Status == "resolved_refunded" {
		pspClient := h.paystackClient(c.Context())
		if !pspClient.Enabled() {
			return notImplemented(c, "refunds are not configured — set PAYSTACK_SECRET_KEY")
		}
		if req.RefundAmountPesewas <= 0 {
			return badRequest(c, "refund_amount_pesewas must be positive")
		}
		refundPaymentID, err = parseUUID(req.RefundPaymentID)
		if err != nil {
			return badRequest(c, "invalid refund_payment_id")
		}

		pmt, err := h.Queries.GetPayment(c.Context(), refundPaymentID)
		if errors.Is(err, pgx.ErrNoRows) {
			return badRequest(c, "refund_payment_id not found")
		} else if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load payment"})
		}
		if pmt.InvoiceID != dispute.InvoiceID {
			return badRequest(c, "refund_payment_id does not belong to this dispute's invoice")
		}
		if pmt.Status != "success" {
			return badRequest(c, "only a successful payment can be refunded")
		}
		refundable := pmt.AmountPesewas - pmt.RefundedAmountPesewas
		if req.RefundAmountPesewas > refundable {
			return badRequest(c, "refund_amount_pesewas exceeds the refundable balance on that payment")
		}

		invoice, err := h.Queries.GetInvoice(c.Context(), pmt.InvoiceID)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load invoice"})
		}

		if _, err := pspClient.RefundTransaction(c.Context(), pmt.PspReference, req.RefundAmountPesewas); err != nil {
			return c.Status(fiber.StatusBadGateway).JSON(fiber.Map{"error": "failed to process refund with provider"})
		}

		if _, err := h.Queries.AddPaymentRefund(c.Context(), db.AddPaymentRefundParams{ID: pmt.ID, Amount: req.RefundAmountPesewas}); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "refund succeeded with the provider but failed to record — needs manual reconciliation"})
		}

		// Section 7.7: the merchant's share of this payment may already have
		// left OrderxPay's balance by either of two paths — see
		// merchantAlreadyReceivedPayout. Record a clawback for the
		// merchant's entitled share of what's being refunded now (not the
		// whole refund — OrderxPay's own commission on that slice was never
		// paid to the merchant, so it isn't owed back), to be deducted from
		// their next settlement. Unlike the invoice-status update below, a
		// failure here is not best-effort: it's real money the merchant now
		// owes back, so it has to surface loudly rather than silently go
		// untracked.
		if merchantAlreadyReceivedPayout(pmt) {
			owed := merchantEntitledShare(req.RefundAmountPesewas, invoice.TotalPesewas, invoice.CommissionPesewas)
			if owed > 0 {
				via := "a payment already paid out via settlement"
				if !pmt.SettlementID.Valid {
					// Split payments never accrue a settlement_id at all —
					// see ComputeSettlementAggregate's exclusion of them —
					// so this is the only path left once SettlementID is
					// the false half of the OR.
					via = "a split payment Paystack already sent straight to the merchant's subaccount"
				}
				if _, err := h.Queries.CreateSettlementClawback(c.Context(), db.CreateSettlementClawbackParams{
					MerchantID:    invoice.MerchantID,
					PaymentID:     pmt.ID,
					DisputeID:     dispute.ID,
					AmountPesewas: owed,
					Reason:        fmt.Sprintf("refund of %s on %s (dispute %s)", formatPesewas(req.RefundAmountPesewas), via, uuid.UUID(dispute.ID.Bytes).String()),
				}); err != nil {
					return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "refund succeeded but failed to record the settlement clawback — needs manual reconciliation"})
				}
			}
		}

		allPayments, err := h.Queries.ListPaymentsByInvoice(c.Context(), dispute.InvoiceID)
		if err == nil {
			var totalRefunded int64
			for _, p := range allPayments {
				if p.ID == pmt.ID {
					totalRefunded += p.RefundedAmountPesewas + req.RefundAmountPesewas
				} else {
					totalRefunded += p.RefundedAmountPesewas
				}
			}
			if totalRefunded >= invoice.TotalPesewas {
				_, _ = h.Queries.SetInvoiceStatus(c.Context(), db.SetInvoiceStatusParams{ID: invoice.ID, Status: "refunded"})
			}
		}
	}

	var refundAmount pgtype.Int8
	if req.Status == "resolved_refunded" {
		refundAmount = pgtype.Int8{Int64: req.RefundAmountPesewas, Valid: true}
	}

	updated, err := h.Queries.ResolveDispute(c.Context(), db.ResolveDisputeParams{
		ID:                  id,
		Status:              req.Status,
		ResolutionNotes:     textOrNull(req.ResolutionNotes),
		RefundPaymentID:     refundPaymentID,
		RefundAmountPesewas: refundAmount,
		ResolvedBy:          toPgUUID(payload.ActorID),
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update dispute"})
	}

	before, _ := json.Marshal(fiber.Map{"status": dispute.Status})
	after, _ := json.Marshal(fiber.Map{"status": updated.Status, "resolution_notes": req.ResolutionNotes, "refund_amount_pesewas": req.RefundAmountPesewas})
	if err := writeAdminAuditLog(c, h, "dispute.resolve", "dispute", id, before, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(updated)
}

// merchantEntitledShare is the portion of a refund that was actually paid
// to the merchant, as opposed to OrderxPay's own commission on that slice —
// the amount a clawback needs to recover once the payment carrying it has
// already gone through a settlement. Mirrors ComputeSettlementAggregate's
// net_payout proration: total_pesewas is exactly subtotal + service_charge
// (+ bundled delivery), so (total - commission) is the merchant's share of
// every pesewa on the invoice, same as at settlement time.
func merchantEntitledShare(refundAmountPesewas, invoiceTotalPesewas, invoiceCommissionPesewas int64) int64 {
	if invoiceTotalPesewas <= 0 {
		return 0
	}
	return refundAmountPesewas * (invoiceTotalPesewas - invoiceCommissionPesewas) / invoiceTotalPesewas
}

// merchantAlreadyReceivedPayout reports whether a payment's merchant share
// has already left OrderxPay's balance by one of two genuinely different
// paths, both of which need the same clawback treatment on refund:
//
//  1. It was claimed by a completed settlement (settlement_id set) — Phase
//     1 payouts are manual, so once that's set the money is gone.
//  2. It was a Paystack split-at-charge payment (paystack_subaccount_code
//     set) — Paystack sent the merchant's share straight to their own
//     subaccount at charge time, bypassing the settlement system
//     entirely. This is the case ComputeSettlementAggregate's own
//     filter (AND p.paystack_subaccount_code IS NULL) means
//     settlement_id checked alone will always miss: a split payment
//     never gets aggregated into any settlement, so settlement_id for it
//     stays NULL forever, not just until the next settlement run. Without
//     this second check, refunding a split payment silently recorded no
//     debt at all — exactly the gap the Fee Architecture brief named
//     before split payments were ever allowed to go live for anyone.
//
// What this function fixes is detection — the clawback row now always
// gets created. What it can't fix on its own: GenerateSettlement is how a
// clawback actually gets collected (deducted from a merchant's next
// settlement), and a merchant who takes ONLY split payments never has a
// settlement generated for them at all — there's nothing non-split left
// to aggregate. For that merchant the clawback stays visible and
// outstanding (Back Office shows it), but nothing automatically collects
// it; a merchant who has any mix of split and non-split activity is fully
// covered, since the debt applies to whatever real settlement they next
// get. Recovering from a 100%-split merchant would need its own
// collection mechanism — initiating a transfer to pull money back, not
// withholding one — which is a materially different, higher-stakes
// feature than this one and hasn't been built.
func merchantAlreadyReceivedPayout(pmt db.Payment) bool {
	return pmt.SettlementID.Valid || pmt.PaystackSubaccountCode.Valid
}
