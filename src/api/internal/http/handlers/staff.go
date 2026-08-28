package handlers

import (
	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/crypto/bcrypt"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// stripStaffSecrets zeroes password_hash before a Staff row is ever
// serialized to a client — same rationale as stripMerchantSecrets.
func stripStaffSecrets(s db.Staff) db.Staff {
	s.PasswordHash = pgtype.Text{}
	return s
}

type createStaffRequest struct {
	Name     string `json:"name"`
	Phone    string `json:"phone"`
	Role     string `json:"role"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

// CreateStaff adds a merchant staff member (Section 4.9 multi-user roles).
// Email/password are required — set by the merchant on the staff member's
// behalf (they're told the password out-of-band) — so the staff member can
// log in themselves via MerchantLogin (auth.go) rather than sharing the
// owner's session.
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
	if req.Email == "" || req.Password == "" {
		return badRequest(c, "email and password are required so this staff member can log in")
	}
	if len(req.Password) < minPasswordLength {
		return badRequest(c, "password must be at least 8 characters")
	}
	role := req.Role
	if role == "" {
		role = "staff"
	}
	if role != "owner" && role != "staff" {
		return badRequest(c, "role must be owner or staff")
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to process password"})
	}

	staff, err := h.Queries.CreateStaff(c.Context(), db.CreateStaffParams{
		MerchantID:   merchantID,
		Name:         req.Name,
		Phone:        req.Phone,
		Role:         role,
		Email:        textOrNull(req.Email),
		PasswordHash: textOrNull(string(hash)),
	})
	if err != nil {
		return c.Status(fiber.StatusConflict).JSON(fiber.Map{"error": "staff with this phone or email may already exist"})
	}
	return c.Status(fiber.StatusCreated).JSON(stripStaffSecrets(staff))
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
	sanitized := make([]db.Staff, len(staff))
	for i, s := range staff {
		sanitized[i] = stripStaffSecrets(s)
	}
	return c.JSON(sanitized)
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
