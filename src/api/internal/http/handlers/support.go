package handlers

import (
	"errors"
	"fmt"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
)

// SupportSearch is the Section 7.10 helpdesk console's lookup — a single
// query box a support agent can type a merchant name/phone, or a customer
// phone/invoice reference, into. Read-only: the "Support" role is scoped to
// support.view + merchants.view only, no mutation permissions.
func (h *Handler) SupportSearch(c *fiber.Ctx) error {
	query := c.Query("q")
	if len(query) < 2 {
		return badRequest(c, "q must be at least 2 characters")
	}

	invoices, err := h.Queries.SearchInvoicesForSupport(c.Context(), query)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to search transactions"})
	}
	merchants, err := h.Queries.SearchMerchantsForSupport(c.Context(), query)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to search merchants"})
	}

	return c.JSON(fiber.Map{
		"invoices":  invoices,
		"merchants": merchants,
	})
}

// GetSupportTransaction assembles everything a support agent needs for one
// transaction: the invoice, its line items, its payment attempts, and (for
// anything still unpaid) the real hosted checkout link — there's no
// WhatsApp/SMS provider integrated (Section 4.4 is still a stub), so
// "resend the payment link" means handing the agent the link to relay
// themselves, not an automated send.
func (h *Handler) GetSupportTransaction(c *fiber.Ctx) error {
	reference := c.Params("reference")
	if reference == "" {
		return badRequest(c, "reference is required")
	}

	invoice, err := h.Queries.GetSupportTransaction(c.Context(), reference)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load transaction"})
	}

	lineItems, err := h.Queries.ListInvoiceLineItems(c.Context(), invoice.ID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load line items"})
	}

	payments, err := h.Queries.ListPaymentsByInvoice(c.Context(), invoice.ID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load payments"})
	}

	var checkoutURL string
	if invoice.Status != "paid" && invoice.Status != "cancelled" && invoice.Status != "refunded" {
		checkoutURL = fmt.Sprintf("%s/checkout/%s", h.WebBaseURL, invoice.Reference)
	}

	return c.JSON(fiber.Map{
		"invoice":      invoice,
		"line_items":   lineItems,
		"payments":     payments,
		"checkout_url": checkoutURL,
	})
}
