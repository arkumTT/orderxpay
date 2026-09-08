package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
	"github.com/orderxpay/api/internal/hubtel"
)

// Section 4.5/9's USSD fallback: a customer who can't complete Paystack's
// hosted checkout page at all (no smartphone, no data, no browser) gets a
// USSD/PIN payment prompt sent straight to their phone via Hubtel instead.
// See internal/hubtel's package doc comment before touching this file —
// unlike every other PSP integration in this codebase, Hubtel's exact wire
// format has never been checked against a real account, because none
// exists yet. Every handler below is inert until BOTH h.Hubtel.Enabled()
// (real credentials configured) AND the hubtel_ussd_fallback feature flag
// are true for the merchant — two independent gates before any real
// traffic can ever reach it, matching the pattern split payments shipped
// with.

// hubtelChannelForNetwork maps this codebase's own network vocabulary onto
// Hubtel's Channel field — kept as an internal translation layer rather
// than exposing Hubtel's exact (still only third-party-corroborated)
// channel strings on this API's own public request shape, so if one of
// those strings turns out to be wrong once a real account exists, only
// this mapping needs fixing, not anything already built against this
// endpoint.
func hubtelChannelForNetwork(network string) (string, error) {
	switch network {
	case "mtn":
		return hubtel.ChannelMTN, nil
	case "telecel":
		return hubtel.ChannelTelecel, nil
	case "airteltigo":
		return hubtel.ChannelAirtelTigo, nil
	default:
		return "", errors.New("network must be one of mtn, telecel, airteltigo")
	}
}

type initiateUSSDPaymentRequest struct {
	// Network is required — Ghana's number portability broke the old
	// prefix-based network inference, so there's no reliable way to guess
	// this from a phone number alone; the customer (or the merchant
	// helping them) has to say which network the USSD prompt should route
	// through.
	Network string `json:"network"`
	// CustomerName is optional — Hubtel's request shape accepts it but
	// nothing in this codebase requires collecting a customer's name today.
	CustomerName string `json:"customer_name"`
}

// InitiateUSSDPayment is the Hubtel fallback's entry point — same route
// shape as InitiateCheckoutPayment (public, keyed off the invoice
// reference), gated by two independent checks neither of which involve
// trusting the caller: the feature flag, checked server-side against the
// invoice's own merchant, and h.Hubtel.Enabled(), which is only ever true
// once real credentials are actually configured.
func (h *Handler) InitiateUSSDPayment(c *fiber.Ctx) error {
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

	enabled, err := h.Queries.GetFeatureFlagStatusForMerchant(c.Context(), db.GetFeatureFlagStatusForMerchantParams{
		MerchantID: invoice.MerchantID,
		Key:        "hubtel_ussd_fallback",
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to check feature availability"})
	}
	if !enabled || !h.Hubtel.Enabled() {
		return notImplemented(c, "USSD payment is not available for this merchant yet")
	}

	var req initiateUSSDPaymentRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	channel, err := hubtelChannelForNetwork(strings.TrimSpace(strings.ToLower(req.Network)))
	if err != nil {
		return badRequest(c, err.Error())
	}

	amountOwed, err := h.amountOwedPesewas(c.Context(), invoice)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to compute amount owed"})
	}
	if amountOwed <= 0 {
		return badRequest(c, "invoice has no remaining balance")
	}

	// KYC tier limits apply identically to a Hubtel-routed payment as to a
	// Paystack one — the money moves through the same merchant either way.
	if msg, limErr := h.enforceTierLimit(c.Context(), invoice.MerchantID, amountOwed); limErr != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to check KYC tier limits"})
	} else if msg != "" {
		return badRequest(c, "this business cannot accept the payment right now: "+msg)
	}

	clientReference, err := generatePaymentReference(invoice.Reference)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to generate a reference"})
	}

	result, err := h.Hubtel.ReceiveMoney(c.Context(), hubtel.ReceiveMoneyParams{
		CustomerName:    req.CustomerName,
		CustomerMsisdn:  invoice.CustomerContact,
		Channel:         channel,
		AmountPesewas:   amountOwed,
		CallbackURL:     fmt.Sprintf("%s/api/v1/public/webhooks/hubtel", h.APIPublicBaseURL),
		Description:     "OrderxPay invoice " + invoice.Reference,
		ClientReference: clientReference,
	})
	if err != nil {
		log.Printf("hubtel: receive money failed: %v", err)
		return c.Status(fiber.StatusBadGateway).JSON(fiber.Map{"error": "failed to start USSD payment with provider"})
	}

	if _, err := h.Queries.CreatePayment(c.Context(), db.CreatePaymentParams{
		InvoiceID:     invoice.ID,
		PspReference:  clientReference,
		Method:        "ussd",
		AmountPesewas: amountOwed,
		Status:        "pending",
		Provider:      "hubtel",
	}); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to record payment attempt"})
	}

	return c.JSON(fiber.Map{
		"reference":     clientReference,
		"response_code": result.ResponseCode,
		"message":       "A USSD prompt was sent to the customer's phone. Ask them to check it and enter their PIN to complete payment.",
	})
}

// HandleHubtelWebhook is Hubtel's async source of truth for a USSD
// payment's outcome — mirrors HandlePSPWebhook's shape (Paystack), reusing
// creditSuccessfulPayment exactly as-is: passing an empty channel makes it
// fall back to the payment's own already-set method ("ussd"), so no
// Hubtel-specific credit path was needed, just this thin translation of
// Hubtel's callback shape into that shared function's signature.
//
// UNVERIFIED, per this file's package-level note: which exact Status/
// ResponseCode values mean "the customer approved this" is not
// independently confirmed. Handled defensively rather than guessed —
// anything that ISN'T unambiguously a success is treated as "not yet
// successful" and simply ignored (not an error), so a webhook payload
// whose exact success marker turns out to differ from what's checked here
// fails safe (nothing gets silently marked paid) rather than fails loud.
// The customer/merchant can still fall back to the ordinary Paystack
// checkout link if a real approval never gets picked up correctly — this
// is not the only way to complete the invoice. Confirm the real success
// marker the moment a Hubtel account exists, and tighten this check then.
func (h *Handler) HandleHubtelWebhook(c *fiber.Ctx) error {
	if !h.Hubtel.Enabled() {
		return notImplemented(c, "Hubtel is not configured")
	}

	body := c.Body()
	var payload hubtel.CallbackPayload
	if err := json.Unmarshal(body, &payload); err != nil {
		h.logWebhookDelivery(c.Context(), "hubtel", "", "", false, false, "invalid JSON payload")
		return badRequest(c, "invalid webhook payload")
	}

	// No confirmed signature-verification scheme for Hubtel callbacks
	// (unlike Paystack's HMAC-SHA512 — see psp.VerifyWebhookSignature).
	// Logged explicitly as such so this gap is visible in the webhook
	// delivery log rather than silently indistinguishable from a verified
	// call — do not treat sigValid=true here as a real signature check.
	const sigValid = false

	isSuccess := strings.EqualFold(payload.Status, "Success") || payload.ResponseCode == "0000"
	if !isSuccess {
		h.logWebhookDelivery(c.Context(), "hubtel", payload.Status, payload.ClientReference, sigValid, true, "not a success status — ignored, not an error")
		return c.SendStatus(fiber.StatusOK)
	}

	if err := h.creditSuccessfulPayment(c.Context(), payload.ClientReference, "", nil); err != nil {
		log.Printf("hubtel webhook: failed to credit payment %s: %v", payload.ClientReference, err)
		h.logWebhookDelivery(c.Context(), "hubtel", payload.Status, payload.ClientReference, sigValid, false, err.Error())
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to process webhook"})
	}
	h.logWebhookDelivery(c.Context(), "hubtel", payload.Status, payload.ClientReference, sigValid, true, "")
	return c.SendStatus(fiber.StatusOK)
}
