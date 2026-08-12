package handlers

import (
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// GetInvoiceByReference backs the hosted checkout page (Section 5.1) —
// intentionally unauthenticated: the reference number in the payment link/QR
// is the bearer credential (Section 5.3), so it should be rate-limited and
// given a short expiry once that middleware exists.
func (h *Handler) GetInvoiceByReference(c *fiber.Ctx) error {
	reference := c.Params("reference")
	if reference == "" {
		return badRequest(c, "reference is required")
	}

	invoice, err := h.Queries.GetInvoiceByReference(c.Context(), reference)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load invoice"})
	}

	lineItems, err := h.Queries.ListInvoiceLineItems(c.Context(), invoice.ID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load invoice line items"})
	}

	return c.JSON(fiber.Map{"invoice": invoice, "line_items": lineItems})
}

func (h *Handler) ListInvoicesByMerchant(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	limit := int32(c.QueryInt("limit", 50))
	offset := int32(c.QueryInt("offset", 0))

	invoices, err := h.Queries.ListInvoicesByMerchant(c.Context(), db.ListInvoicesByMerchantParams{
		MerchantID:   merchantID,
		StatusFilter: c.Query("status"),
		Limit:        limit,
		Offset:       offset,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list invoices"})
	}
	return c.JSON(invoices)
}

// CreateInvoice is not yet implemented: it depends on the order/invoice
// engine (Section 4.3) — computing subtotal/service-charge/total from line
// items per the merchant's fee-allocation rule (Section 4.8) — which needs
// its own design pass rather than being scaffolded ad hoc.
func (h *Handler) CreateInvoice(c *fiber.Ctx) error {
	return notImplemented(c, "invoice engine not yet implemented — see Section 4.3/4.8 of the architecture doc")
}
