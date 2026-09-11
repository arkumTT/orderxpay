package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

func (h *Handler) ListSettlements(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	settlements, err := h.Queries.ListSettlementsByMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list settlements"})
	}
	return c.JSON(settlements)
}

// ListAllSettlements backs the Back Office 7.2 landing page — a
// cross-merchant view (unlike ListSettlements, which is scoped to one
// merchant's detail page).
func (h *Handler) ListAllSettlements(c *fiber.Ctx) error {
	limit := int32(c.QueryInt("limit", 50))
	offset := int32(c.QueryInt("offset", 0))

	settlements, err := h.Queries.ListSettlementsAdmin(c.Context(), db.ListSettlementsAdminParams{
		StatusFilter: c.Query("status"),
		RowLimit:     limit,
		RowOffset:    offset,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list settlements"})
	}
	return c.JSON(settlements)
}

const dateLayout = "2006-01-02"

type generateSettlementRequest struct {
	MerchantID  string `json:"merchant_id"`
	PeriodStart string `json:"period_start"` // "2026-08-01"
	PeriodEnd   string `json:"period_end"`   // inclusive calendar date, e.g. "2026-08-14"
}

// GenerateSettlement is the Section 7.2 batch-run: aggregates every
// not-yet-settled successful payment for a merchant within a calendar-date
// period into one payout record, and atomically marks those payments as
// claimed by it so a second run (accidental or scheduled) can never double
// -pay them. This is the "scheduled batch runs" half of 7.2's payout batch
// management — see UpdateSettlementStatus for the manual mark-paid step
// that actually executing the payout (still off-platform for now, per the
// Phase 1 roadmap's "manual payout") reduces to.
func (h *Handler) GenerateSettlement(c *fiber.Ctx) error {
	var req generateSettlementRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	merchantID, err := parseUUID(req.MerchantID)
	if err != nil {
		return badRequest(c, "invalid merchant_id")
	}
	periodStart, err := time.Parse(dateLayout, req.PeriodStart)
	if err != nil {
		return badRequest(c, "period_start must be YYYY-MM-DD")
	}
	periodEndDate, err := time.Parse(dateLayout, req.PeriodEnd)
	if err != nil {
		return badRequest(c, "period_end must be YYYY-MM-DD")
	}
	if periodEndDate.Before(periodStart) {
		return badRequest(c, "period_end must be on or after period_start")
	}
	// period_end is inclusive as given by the caller; the exclusive
	// upper bound for the timestamptz range is the start of the next day.
	rangeEnd := periodEndDate.AddDate(0, 0, 1)

	merchant, err := h.Queries.GetMerchant(c.Context(), merchantID)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}
	if merchant.Status == "suspended" {
		return badRequest(c, "merchant is suspended and cannot receive new payouts")
	}
	// Section 4.1/7.2: a settlement with nowhere verified to send it just
	// pushes the "where does this go" question off-platform to whoever
	// executes the payout by hand — exactly the gap payout-account capture
	// exists to close. Require it here rather than only encouraging it in
	// the app, so Back Office staff can't generate one for a merchant who
	// hasn't gone through the app's verify-account flow yet.
	if !merchant.PayoutAccountVerifiedAt.Valid {
		return badRequest(c, "this merchant has no verified payout account yet — ask them to add one under Verify & Withdraw before generating a settlement")
	}

	tx, err := h.Pool.Begin(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to start transaction"})
	}
	defer tx.Rollback(c.Context())
	qtx := h.Queries.WithTx(tx)

	aggParams := db.ComputeSettlementAggregateParams{
		MerchantID:  merchantID,
		PeriodStart: pgtype.Timestamptz{Time: periodStart, Valid: true},
		PeriodEnd:   pgtype.Timestamptz{Time: rangeEnd, Valid: true},
	}
	agg, err := qtx.ComputeSettlementAggregate(c.Context(), aggParams)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to compute settlement aggregate"})
	}
	if agg.PaymentCount == 0 {
		return badRequest(c, "no unsettled successful payments for this merchant in the given period")
	}

	// Section 7.7: work off any debt this merchant owes from a refund/
	// chargeback that landed on a payment from an *earlier* settlement —
	// the merchant was already paid that money, so it comes out of this
	// one instead. Must happen before the threshold check below: a payout
	// that clawback reduces to near nothing shouldn't clear the bar to be
	// worth paying out at all.
	outstanding, err := qtx.ListOutstandingClawbacksByMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load outstanding clawbacks"})
	}
	netAfterClawback, clawbacksApplied := consumeOutstandingClawbacks(agg.NetPayoutPesewas, outstanding)
	clawbackPesewas := agg.NetPayoutPesewas - netAfterClawback

	// Section 7.2: a merchant can hold payouts back until they are worth
	// taking. The withdrawal fee below is flat, so paying out ₵20 a day costs
	// proportionally far more than paying out ₵300 once a week — the
	// threshold is how a merchant opts into the cheaper shape.
	if netAfterClawback < merchant.PayoutMinThresholdPesewas {
		if clawbackPesewas > 0 {
			return badRequest(c, fmt.Sprintf(
				"net payout of %s (after %s clawed back for prior refunds) is below this merchant's minimum payout threshold of %s",
				formatPesewas(netAfterClawback), formatPesewas(clawbackPesewas), formatPesewas(merchant.PayoutMinThresholdPesewas)))
		}
		return badRequest(c, fmt.Sprintf(
			"net payout of %s is below this merchant's minimum payout threshold of %s",
			formatPesewas(netAfterClawback), formatPesewas(merchant.PayoutMinThresholdPesewas)))
	}

	withdrawalFee, err := h.withdrawalFeeFor(c.Context(), merchantID, merchant.PayoutAccountType, netAfterClawback)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to resolve withdrawal fee"})
	}

	settlement, err := qtx.CreateSettlement(c.Context(), db.CreateSettlementParams{
		MerchantID:              merchantID,
		PeriodStart:             pgtype.Date{Time: periodStart, Valid: true},
		PeriodEnd:               pgtype.Date{Time: periodEndDate, Valid: true},
		GrossCollectionsPesewas: agg.GrossCollectionsPesewas,
		PspFeesPesewas:          agg.PspFeesPesewas,
		CommissionPesewas:       agg.CommissionPesewas,
		WithdrawalFeePesewas:    withdrawalFee,
		ClawbackPesewas:         clawbackPesewas,
		NetPayoutPesewas:        netAfterClawback - withdrawalFee,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create settlement"})
	}

	for _, cb := range clawbacksApplied {
		if err := qtx.ApplySettlementClawback(c.Context(), db.ApplySettlementClawbackParams{
			ID:                  cb.ID,
			AppliedSettlementID: settlement.ID,
		}); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to apply settlement clawback"})
		}
	}

	if err := qtx.MarkPaymentsSettled(c.Context(), db.MarkPaymentsSettledParams{
		SettlementID: settlement.ID,
		MerchantID:   merchantID,
		PeriodStart:  aggParams.PeriodStart,
		PeriodEnd:    aggParams.PeriodEnd,
	}); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to mark payments settled"})
	}

	after, _ := json.Marshal(fiber.Map{
		"status":                    settlement.Status,
		"gross_collections_pesewas": settlement.GrossCollectionsPesewas,
		"psp_fees_pesewas":          settlement.PspFeesPesewas,
		"commission_pesewas":        settlement.CommissionPesewas,
		"withdrawal_fee_pesewas":    settlement.WithdrawalFeePesewas,
		"clawback_pesewas":          settlement.ClawbackPesewas,
		"net_payout_pesewas":        settlement.NetPayoutPesewas,
		"payment_count":             agg.PaymentCount,
		"period_start":              req.PeriodStart,
		"period_end":                req.PeriodEnd,
	})
	if err := writeAdminAuditLog(c, h, "settlement.generate", "settlement", settlement.ID, nil, after); err != nil {
		log.Printf("settlements: failed to write audit log for generate: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	if err := tx.Commit(c.Context()); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to commit settlement"})
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{
		"settlement":    settlement,
		"payment_count": agg.PaymentCount,
	})
}

// settlementStatusTransitions enumerates the only moves UpdateSettlementStatus
// accepts — a settlement can advance from pending, or fail out of either
// non-terminal state, but never un-pay or un-fail.
var settlementStatusTransitions = map[string][]string{
	"pending":    {"processing", "paid", "failed"},
	"processing": {"paid", "failed"},
}

type updateSettlementStatusRequest struct {
	Status string `json:"status"`
}

// UpdateSettlementStatus is the manual half of Section 7.2's payout batch
// management: back-office staff mark a settlement paid once they've
// actually sent the money (Phase 1 payouts are manual — see the roadmap),
// or failed if it needs to move to the exception queue. Always audited
// (Section 7.9 explicitly calls out manual payout as a sensitive action).
func (h *Handler) UpdateSettlementStatus(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid settlement id")
	}

	var req updateSettlementStatusRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	settlement, err := h.Queries.GetSettlement(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load settlement"})
	}

	allowed := settlementStatusTransitions[settlement.Status]
	valid := false
	for _, s := range allowed {
		if s == req.Status {
			valid = true
			break
		}
	}
	if !valid {
		return badRequest(c, "cannot move settlement from "+settlement.Status+" to "+req.Status)
	}

	updated, err := h.Queries.SetSettlementStatus(c.Context(), db.SetSettlementStatusParams{ID: id, Status: req.Status})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update settlement status"})
	}

	before, _ := json.Marshal(fiber.Map{"status": settlement.Status})
	after, _ := json.Marshal(fiber.Map{"status": updated.Status})
	if err := writeAdminAuditLog(c, h, "settlement.status_change", "settlement", id, before, after); err != nil {
		log.Printf("settlements: failed to write audit log for status change: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	if updated.Status == "paid" {
		// Best-effort (Section 4.10) — never fail the status update itself
		// over a notification write.
		body := fmt.Sprintf(
			"%s settled for %s – %s.",
			formatPesewas(updated.NetPayoutPesewas),
			updated.PeriodStart.Time.Format("2 Jan"),
			updated.PeriodEnd.Time.Format("2 Jan"),
		)
		if _, err := h.Queries.CreateNotification(c.Context(), db.CreateNotificationParams{
			MerchantID:   updated.MerchantID,
			Type:         "payout_processed",
			Title:        "Payout processed",
			Body:         body,
			TargetEntity: textOrNull("settlement"),
			TargetID:     updated.ID,
		}); err != nil {
			log.Printf("settlements: failed to create notification for %s: %v", updated.ID, err)
		}
		h.pushToMerchant(c.Context(), updated.MerchantID, "Payout processed", body, map[string]string{
			"target_entity": "settlement",
			"target_id":     uuid.UUID(updated.ID.Bytes).String(),
		})
	}

	return c.JSON(updated)
}

// writeAdminAuditLog records a Back Office action against the authenticated
// admin user (Section 7.9) — separate from the "system" actor used for
// PSP-webhook-driven changes in payments.go. A thin wrapper over
// writeActorAuditLog kept under its original name since every existing call
// site is on an admin-only route.
func writeAdminAuditLog(c *fiber.Ctx, h *Handler, action, targetEntity string, targetID pgtype.UUID, before, after []byte) error {
	return writeActorAuditLog(c, h, action, targetEntity, targetID, before, after)
}

// writeActorAuditLog is writeAdminAuditLog generalized to attribute
// correctly regardless of which kind of principal is authenticated — reads
// ActorType off the token itself (auth.ActorUser/ActorMerchant/ActorStaff)
// rather than assuming Back Office, so a merchant- or staff-initiated
// action sensitive enough to want a real audit trail (e.g.
// SetMerchantOwnFeeRule) never gets mislabeled as a Back Office user's.
func writeActorAuditLog(c *fiber.Ctx, h *Handler, action, targetEntity string, targetID pgtype.UUID, before, after []byte) error {
	payload, ok := actorPayload(c)
	if !ok {
		return fiber.NewError(fiber.StatusUnauthorized, "missing auth payload")
	}
	_, err := h.Queries.CreateAuditLogEntry(c.Context(), db.CreateAuditLogEntryParams{
		ActorID:      toPgUUID(payload.ActorID),
		ActorType:    string(payload.ActorType),
		Action:       action,
		TargetEntity: targetEntity,
		TargetID:     targetID,
		BeforeState:  before,
		AfterState:   after,
	})
	return err
}

// withdrawalFeeFor prices a single payout. The PSP charges a flat amount per
// transfer — not a percentage — so this is passed through flat rather than
// folded into the blended collection rate, which is what fee_rules'
// long-retired payout_fee_bps tried and could not do at any scale.
//
// The fee is waived entirely once a payout is large enough to carry it
// comfortably: at the default ₵500 waiver the collection margin on that
// volume is several times the ₵1 transfer cost, so the waiver funds itself
// while pushing merchants towards the batching that makes payouts cheap for
// everyone.
//
// A merchant with no payout account on file yet is priced as mobile money —
// the overwhelming default in Ghana, and the cheaper of the two, so an
// unset account can never overcharge.
func (h *Handler) withdrawalFeeFor(ctx context.Context, merchantID pgtype.UUID, accountType pgtype.Text, netPayoutPesewas int64) (int64, error) {
	rule, err := h.Queries.GetFeeRuleByMerchant(ctx, merchantID)
	if errors.Is(err, pgx.ErrNoRows) {
		rule, err = h.Queries.GetGlobalFeeRule(ctx)
	}
	if err != nil {
		return 0, err
	}

	return withdrawalFee(rule.WithdrawalFeeMomoPesewas, rule.WithdrawalFeeBankPesewas,
		rule.WithdrawalFeeWaiverPesewas, accountType, netPayoutPesewas), nil
}

func withdrawalFee(momoFee, bankFee, waiver int64, accountType pgtype.Text, netPayoutPesewas int64) int64 {
	if waiver > 0 && netPayoutPesewas >= waiver {
		return 0
	}

	fee := momoFee
	if accountType.Valid && accountType.String == "bank" {
		fee = bankFee
	}

	// Never hand back a negative payout: a fee larger than the payout it is
	// charged on takes the whole payout and no more.
	if fee > netPayoutPesewas {
		fee = netPayoutPesewas
	}
	return fee
}

// consumeOutstandingClawbacks applies a merchant's outstanding clawback
// debt against a settlement's gross net payout, oldest debt first, one
// whole clawback at a time. A clawback is never split across settlements —
// if the oldest outstanding one doesn't fit inside what's left, it (and
// every clawback behind it in the queue) stays outstanding for next time
// rather than letting a later, smaller one jump the line. That keeps a
// single large chargeback from being silently nibbled away across many
// settlements while looking, on any one of them, like it was never
// applied at all.
//
// Returns the payout remaining after deductions (always >= 0, and never
// more is taken than the payout itself has) and exactly which clawbacks
// were fully absorbed — the caller still owes qtx.ApplySettlementClawback
// on each of those before committing.
func consumeOutstandingClawbacks(netPayoutPesewas int64, outstanding []db.SettlementClawback) (remaining int64, applied []db.SettlementClawback) {
	remaining = netPayoutPesewas
	for _, cb := range outstanding {
		if cb.AmountPesewas > remaining {
			break
		}
		remaining -= cb.AmountPesewas
		applied = append(applied, cb)
	}
	return remaining, applied
}
