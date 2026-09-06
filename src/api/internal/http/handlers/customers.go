package handlers

import (
	"github.com/gofiber/fiber/v2"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// CreateCustomer is the manual "+ Add Customer" path (Section 4.3 order
// flow revision). It shares UpsertCustomer with the automatic save that
// happens after every invoice send — adding a customer who already
// exists (same contact) just updates their name rather than erroring on
// a duplicate.
func (h *Handler) CreateCustomer(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req struct {
		Name    string `json:"name"`
		Contact string `json:"contact"`
	}
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Contact == "" {
		return badRequest(c, "contact is required")
	}

	customer, err := h.Queries.UpsertCustomer(c.Context(), db.UpsertCustomerParams{
		MerchantID: merchantID,
		Contact:    req.Contact,
		Name:       textOrNull(req.Name),
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to save customer"})
	}
	return c.Status(fiber.StatusCreated).JSON(customer)
}

// ListCustomers backs both the Customers page (More → Customers) and the
// "choose from saved customers" picker on New Order.
func (h *Handler) ListCustomers(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	customers, err := h.Queries.ListCustomers(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list customers"})
	}
	return c.JSON(customers)
}

func (h *Handler) UpdateCustomer(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	customerID, err := parseUUIDParam(c, "customerId")
	if err != nil {
		return badRequest(c, "invalid customer id")
	}

	var req struct {
		Name    string `json:"name"`
		Contact string `json:"contact"`
	}
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Contact == "" {
		return badRequest(c, "contact is required")
	}

	rows, err := h.Queries.UpdateCustomer(c.Context(), db.UpdateCustomerParams{
		ID:         customerID,
		MerchantID: merchantID,
		Name:       textOrNull(req.Name),
		Contact:    req.Contact,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update customer"})
	}
	if rows == 0 {
		return notFound(c)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *Handler) DeleteCustomer(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	customerID, err := parseUUIDParam(c, "customerId")
	if err != nil {
		return badRequest(c, "invalid customer id")
	}
	rows, err := h.Queries.DeleteCustomer(c.Context(), db.DeleteCustomerParams{ID: customerID, MerchantID: merchantID})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to delete customer"})
	}
	if rows == 0 {
		return notFound(c)
	}
	return c.SendStatus(fiber.StatusNoContent)
}
