package handlers

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math/big"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
	"github.com/orderxpay/api/internal/psp"
)

func (h *Handler) ListPaymentsByInvoice(c *fiber.Ctx) error {
	invoiceID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid invoice id")
	}

	payments, err := h.Queries.ListPaymentsByInvoice(c.Context(), invoiceID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list payments"})
	}
	return c.JSON(payments)
}

// systemActorID is the well-known audit-log actor for state changes no human
// initiated directly (webhook callbacks, verify-on-return reconciliation).
var systemActorID = pgtype.UUID{Valid: true}

type initiatePaymentRequest struct {
	// PreferredMethod is a best-effort hint recorded on the payments row;
	// the customer can still pick a different channel on Paystack's hosted
	// page, and the real method is corrected from the channel Paystack
	// reports back at settlement time (see paystackChannelToMethod).
	PreferredMethod string `json:"preferred_method"`
}

// InitiateCheckoutPayment starts a Paystack transaction for the still-owed
// balance on an invoice (Section 4.5, 9.1) and returns the hosted checkout
// URL to redirect the customer to. Unauthenticated like the checkout page
// itself — the reference in the URL is the bearer credential (Section 5.3).
func (h *Handler) InitiateCheckoutPayment(c *fiber.Ctx) error {
	if !h.PSP.Enabled() {
		return notImplemented(c, "payment collection is not configured — set PAYSTACK_SECRET_KEY")
	}

	reference := c.Params("reference")
	invoice, err := h.loadPayableInvoice(c.Context(), reference)
	if err != nil {
		if errors.Is(err, errInvoiceNotPayable) {
			return badRequest(c, err.Error())
		}
		if errors.Is(err, pgx.ErrNoRows) {
			return notFound(c)
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load invoice"})
	}

	var req initiatePaymentRequest
	_ = c.BodyParser(&req) // optional body — a missing/empty body is fine
	method := req.PreferredMethod
	if method != "momo" && method != "card" && method != "ussd" {
		method = "momo"
	}

	amountOwed, err := h.amountOwedPesewas(c.Context(), invoice)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to compute amount owed"})
	}
	if amountOwed <= 0 {
		return badRequest(c, "invoice has no remaining balance")
	}

	pspReference, err := generatePaymentReference(invoice.Reference)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to generate payment reference"})
	}

	result, err := h.PSP.InitializeTransaction(c.Context(), psp.InitializeParams{
		Email:         syntheticCustomerEmail(invoice.CustomerContact),
		AmountPesewas: amountOwed,
		Currency:      "GHS",
		Reference:     pspReference,
		CallbackURL:   fmt.Sprintf("%s/checkout/%s", h.WebBaseURL, invoice.Reference),
	})
	if err != nil {
		log.Printf("paystack: initialize transaction failed: %v", err)
		return c.Status(fiber.StatusBadGateway).JSON(fiber.Map{"error": "failed to start payment with provider"})
	}

	if _, err := h.Queries.CreatePayment(c.Context(), db.CreatePaymentParams{
		InvoiceID:     invoice.ID,
		PspReference:  pspReference,
		Method:        method,
		AmountPesewas: amountOwed,
		Status:        "pending",
	}); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to record payment attempt"})
	}

	return c.JSON(fiber.Map{
		"authorization_url": result.AuthorizationURL,
		"reference":         pspReference,
	})
}

// VerifyCheckoutPayment is the fallback path the checkout page calls after
// Paystack redirects the customer back: it verifies the transaction
// server-side rather than trusting the redirect alone, and covers the case
// where the async webhook (HandlePSPWebhook) hasn't arrived yet — the two
// paths share creditSuccessfulPayment so crediting stays idempotent either
// way, keyed off the payments.psp_reference unique index.
func (h *Handler) VerifyCheckoutPayment(c *fiber.Ctx) error {
	if !h.PSP.Enabled() {
		return notImplemented(c, "payment collection is not configured — set PAYSTACK_SECRET_KEY")
	}

	reference := c.Params("reference")
	trxReference := c.Query("trx_reference")
	if trxReference == "" {
		return badRequest(c, "trx_reference query param is required")
	}

	invoice, err := h.Queries.GetInvoiceByReference(c.Context(), reference)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load invoice"})
	}

	payment, err := h.Queries.GetPaymentByPSPReference(c.Context(), trxReference)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load payment"})
	}
	if payment.InvoiceID != invoice.ID {
		return badRequest(c, "trx_reference does not belong to this invoice")
	}

	if payment.Status != "success" {
		result, err := h.PSP.VerifyTransaction(c.Context(), trxReference)
		if err != nil {
			log.Printf("paystack: verify transaction failed: %v", err)
			return c.Status(fiber.StatusBadGateway).JSON(fiber.Map{"error": "failed to verify payment with provider"})
		}
		if result.Status == "success" {
			if err := h.creditSuccessfulPayment(c.Context(), trxReference, result.Channel); err != nil {
				return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to record payment"})
			}
		}
	}

	return h.renderCheckout(c, reference)
}

// HandlePSPWebhook is Paystack's async source of truth for payment success
// (Section 4.5, 8): verifies the signature, then credits idempotently via
// creditSuccessfulPayment so a retried callback never double-credits an
// invoice. Each PSP has its own signature scheme (Section 9.1) — this one is
// Paystack-specific (HMAC-SHA512 over the raw body).
func (h *Handler) HandlePSPWebhook(c *fiber.Ctx) error {
	if !h.PSP.Enabled() {
		return notImplemented(c, "payment collection is not configured — set PAYSTACK_SECRET_KEY")
	}

	body := c.Body()
	signature := c.Get("x-paystack-signature")
	if !psp.VerifyWebhookSignature(h.PSP.SecretKey, body, signature) {
		return badRequest(c, "invalid webhook signature")
	}

	var event struct {
		Event string `json:"event"`
		Data  struct {
			Reference string `json:"reference"`
			Status    string `json:"status"`
			Channel   string `json:"channel"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &event); err != nil {
		return badRequest(c, "invalid webhook payload")
	}

	if event.Event != "charge.success" {
		return c.SendStatus(fiber.StatusOK)
	}

	if err := h.creditSuccessfulPayment(c.Context(), event.Data.Reference, event.Data.Channel); err != nil {
		log.Printf("paystack webhook: failed to credit payment %s: %v", event.Data.Reference, err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to process webhook"})
	}
	return c.SendStatus(fiber.StatusOK)
}

// creditSuccessfulPayment marks a payment successful and rolls the invoice
// status forward (partially_paid vs paid, per the running sum of successful
// payments — a customer can pay a partial balance in more than one attempt).
// Idempotent: a payment already marked successful is a no-op, so calling
// this from both the webhook and the verify-on-return path never double
// -credits (Section 4.5, 8: financial writes must be safe to retry).
func (h *Handler) creditSuccessfulPayment(ctx context.Context, pspReference, channel string) error {
	payment, err := h.Queries.GetPaymentByPSPReference(ctx, pspReference)
	if errors.Is(err, pgx.ErrNoRows) {
		log.Printf("paystack: received success for unknown reference %s — ignoring", pspReference)
		return nil
	} else if err != nil {
		return err
	}
	if payment.Status == "success" {
		return nil // already credited
	}

	method := paystackChannelToMethod(channel, payment.Method)
	if _, err := h.Queries.SetPaymentStatus(ctx, db.SetPaymentStatusParams{ID: payment.ID, Status: "success"}); err != nil {
		return err
	}

	invoice, err := h.Queries.GetInvoice(ctx, payment.InvoiceID)
	if err != nil {
		return err
	}

	totalPaid, err := h.Queries.SumSuccessfulPaymentsByInvoice(ctx, payment.InvoiceID)
	if err != nil {
		return err
	}
	newStatus := "partially_paid"
	if totalPaid >= invoice.TotalPesewas {
		newStatus = "paid"
	}

	updated, err := h.Queries.SetInvoiceStatus(ctx, db.SetInvoiceStatusParams{ID: invoice.ID, Status: newStatus})
	if err != nil {
		return err
	}

	before, _ := json.Marshal(fiber.Map{"status": invoice.Status, "payment_status": payment.Status})
	after, _ := json.Marshal(fiber.Map{"status": updated.Status, "payment_status": "success", "method": method, "amount_pesewas": payment.AmountPesewas})
	if _, err := h.Queries.CreateAuditLogEntry(ctx, db.CreateAuditLogEntryParams{
		ActorID:      systemActorID,
		ActorType:    "system",
		Action:       "payment.success",
		TargetEntity: "invoice",
		TargetID:     invoice.ID,
		BeforeState:  before,
		AfterState:   after,
	}); err != nil {
		log.Printf("paystack: failed to write audit log for payment %s: %v", pspReference, err)
	}

	return nil
}

var errInvoiceNotPayable = errors.New("invoice is not in a payable state")

// loadPayableInvoice loads an invoice by reference and rejects states where
// starting a new payment attempt doesn't make sense (already fully settled,
// or never sent / no longer valid).
func (h *Handler) loadPayableInvoice(ctx context.Context, reference string) (db.Invoice, error) {
	invoice, err := h.Queries.GetInvoiceByReference(ctx, reference)
	if err != nil {
		return db.Invoice{}, err
	}
	switch invoice.Status {
	case "draft", "paid", "expired", "cancelled", "refunded":
		return db.Invoice{}, fmt.Errorf("%w: status is %s", errInvoiceNotPayable, invoice.Status)
	}
	return invoice, nil
}

func (h *Handler) amountOwedPesewas(ctx context.Context, invoice db.Invoice) (int64, error) {
	totalPaid, err := h.Queries.SumSuccessfulPaymentsByInvoice(ctx, invoice.ID)
	if err != nil {
		return 0, err
	}
	owed := invoice.TotalPesewas - totalPaid
	if owed < 0 {
		owed = 0
	}
	return owed, nil
}

// renderCheckout re-serves the same shape as GetInvoiceByReference so the
// verify endpoint can double as a "give me the fresh state" call.
func (h *Handler) renderCheckout(c *fiber.Ctx, reference string) error {
	invoice, err := h.Queries.GetInvoiceByReference(c.Context(), reference)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load invoice"})
	}
	lineItems, err := h.Queries.ListInvoiceLineItems(c.Context(), invoice.ID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load invoice line items"})
	}
	return c.JSON(fiber.Map{"invoice": invoice, "line_items": lineItems})
}

const paymentReferenceAlphabet = "abcdefghijklmnopqrstuvwxyz0123456789"

// generatePaymentReference makes a fresh Paystack transaction reference per
// attempt (rather than reusing the invoice reference), so a customer who
// retries after an abandoned/failed attempt doesn't collide with Paystack's
// own uniqueness requirement on transaction references.
func generatePaymentReference(invoiceReference string) (string, error) {
	b := make([]byte, 8)
	for i := range b {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(paymentReferenceAlphabet))))
		if err != nil {
			return "", err
		}
		b[i] = paymentReferenceAlphabet[n.Int64()]
	}
	return strings.ToLower(invoiceReference) + "-" + string(b), nil
}

// syntheticCustomerEmail covers Paystack's required "email" field: OrderxPay
// identifies customers by phone number (Section 4.6), not email, so this
// synthesizes a stable, clearly-non-real address rather than prompting the
// customer for one on a page designed to have no login/signup friction
// (Section 5.3).
func syntheticCustomerEmail(customerContact string) string {
	digits := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, customerContact)
	if digits == "" {
		digits = "customer"
	}
	return digits + "@checkout.orderxpay.app"
}

// paystackChannelToMethod maps Paystack's reported settlement channel onto
// our own payments.method enum, correcting the pre-payment guess recorded at
// initiation time (mobile money vs card is only known for certain once
// Paystack reports how the customer actually paid).
func paystackChannelToMethod(channel, fallback string) string {
	switch channel {
	case "mobile_money":
		return "momo"
	case "card":
		return "card"
	case "ussd":
		return "ussd"
	default:
		return fallback
	}
}
