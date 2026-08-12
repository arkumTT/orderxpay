package handlers

import (
	"github.com/gofiber/fiber/v2"
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

// HandlePSPWebhook is not yet implemented: it must (a) verify the PSP's
// webhook signature, (b) upsert on psp_reference so a retried callback never
// double-credits an invoice (idempotency — Section 4.5, 8), and (c) update
// invoice status including partial-payment handling. This depends on which
// PSP is selected (Section 9.1: Paystack/Hubtel/ExpressPay/Flutterwave) —
// each has a different signature scheme.
func (h *Handler) HandlePSPWebhook(c *fiber.Ctx) error {
	return notImplemented(c, "PSP webhook handling not yet implemented — see Section 4.5/9.1 of the architecture doc")
}
