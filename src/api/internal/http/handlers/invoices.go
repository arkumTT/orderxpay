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
	if invoice.Status == "draft" {
		// A draft was never sent — treat it the same as "doesn't exist" to
		// an unauthenticated caller rather than leaking it.
		return notFound(c)
	}

	lineItems, err := h.Queries.ListInvoiceLineItems(c.Context(), invoice.ID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load invoice line items"})
	}

	paid, owed, err := h.paymentProgress(c.Context(), invoice)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to compute amount owed"})
	}

	return c.JSON(fiber.Map{
		"invoice":             invoice,
		"line_items":          lineItems,
		"amount_paid_pesewas": paid,
		"amount_owed_pesewas": owed,
	})
}

// GetInvoiceDetail backs the merchant app's Records detail view — nested
// under /merchants/:id, so RequireOwnMerchant already guarantees :id is the
// caller's own merchant; this additionally checks :invoiceId actually
// belongs to it. Includes payment progress (paid vs. owed) and every
// payment attempt, so a partially-paid invoice shows real numbers rather
// than just the original total.
func (h *Handler) GetInvoiceDetail(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	invoiceID, err := parseUUIDParam(c, "invoiceId")
	if err != nil {
		return badRequest(c, "invalid invoice id")
	}

	invoice, err := h.Queries.GetInvoice(c.Context(), invoiceID)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load invoice"})
	}
	if invoice.MerchantID != merchantID {
		return notFound(c)
	}

	lineItems, err := h.Queries.ListInvoiceLineItems(c.Context(), invoice.ID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load invoice line items"})
	}
	payments, err := h.Queries.ListPaymentsByInvoice(c.Context(), invoice.ID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load payments"})
	}
	paid, owed, err := h.paymentProgress(c.Context(), invoice)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to compute amount owed"})
	}

	return c.JSON(fiber.Map{
		"invoice":             invoice,
		"line_items":          lineItems,
		"payments":            payments,
		"amount_paid_pesewas": paid,
		"amount_owed_pesewas": owed,
	})
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

type createInvoiceRequest struct {
	CustomerContact     string            `json:"customer_contact"`
	LineItems           []lineItemRequest `json:"line_items"`
	DeliveryOptionID    string            `json:"delivery_option_id"`
	DeliveryAddress     string            `json:"delivery_address"`
	DeliveryFeeHandling string            `json:"delivery_fee_handling"` // "bundled" | "external"
	DeliveryFeePesewas  int64             `json:"delivery_fee_pesewas"`
}

// CreateInvoice builds an order from the catalog or quick-add custom lines,
// computes subtotal/service-charge/total per the merchant's fee-allocation
// rule, and issues a payment-ready invoice (Section 4.3/4.8).
func (h *Handler) CreateInvoice(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req createInvoiceRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.CustomerContact == "" {
		return badRequest(c, "customer_contact is required")
	}

	deliveryOptionID, err := uuidOrNull(req.DeliveryOptionID)
	if err != nil {
		return badRequest(c, "invalid delivery_option_id")
	}
	if req.DeliveryFeeHandling != "" && req.DeliveryFeeHandling != "bundled" && req.DeliveryFeeHandling != "external" {
		return badRequest(c, "delivery_fee_handling must be bundled or external")
	}

	invoice, lineItems, err := h.createInvoiceCore(c.Context(), createInvoiceCoreParams{
		MerchantID:          merchantID,
		CustomerContact:     req.CustomerContact,
		LineItems:           req.LineItems,
		DeliveryOptionID:    deliveryOptionID,
		DeliveryAddress:     req.DeliveryAddress,
		DeliveryFeeHandling: req.DeliveryFeeHandling,
		DeliveryFeePesewas:  req.DeliveryFeePesewas,
	})
	if err != nil {
		if isValidationError(err) {
			return badRequest(c, err.Error())
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create invoice"})
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{"invoice": invoice, "line_items": lineItems})
}
