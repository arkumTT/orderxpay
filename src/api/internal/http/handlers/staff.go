package handlers

import (
	"github.com/gofiber/fiber/v2"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type createStaffRequest struct {
	Name  string `json:"name"`
	Phone string `json:"phone"`
	Role  string `json:"role"`
}

// CreateStaff adds a merchant staff member (Section 4.9 multi-user roles).
func (h *Handler) CreateStaff(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req createStaffRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Name == "" || req.Phone == "" {
		return badRequest(c, "name and phone are required")
	}
	role := req.Role
	if role == "" {
		role = "staff"
	}
	if role != "owner" && role != "staff" {
		return badRequest(c, "role must be owner or staff")
	}

	staff, err := h.Queries.CreateStaff(c.Context(), db.CreateStaffParams{
		MerchantID: merchantID,
		Name:       req.Name,
		Phone:      req.Phone,
		Role:       role,
	})
	if err != nil {
		return c.Status(fiber.StatusConflict).JSON(fiber.Map{"error": "staff with this phone may already exist"})
	}
	return c.Status(fiber.StatusCreated).JSON(staff)
}

func (h *Handler) ListStaff(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	staff, err := h.Queries.ListStaffByMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list staff"})
	}
	return c.JSON(staff)
}

func (h *Handler) DeleteStaff(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	staffID, err := parseUUIDParam(c, "staffId")
	if err != nil {
		return badRequest(c, "invalid staff id")
	}
	rows, err := h.Queries.DeleteStaff(c.Context(), db.DeleteStaffParams{ID: staffID, MerchantID: merchantID})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to delete staff"})
	}
	if rows == 0 {
		return notFound(c)
	}
	return c.SendStatus(fiber.StatusNoContent)
}
