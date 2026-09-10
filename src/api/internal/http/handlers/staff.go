package handlers

import (
	"errors"
	"fmt"

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

// validate covers everything CreateStaff can check without a DB round trip.
// email is deliberately absent — a staff member logs in by phone or email
// (MerchantLogin), so a phone number and a password are enough to give
// them a working account, same as a phone-first merchant. A merchant who
// onboarded without an email can now add staff the same way.
func (r createStaffRequest) validate() error {
	if r.Name == "" || r.Phone == "" {
		return errors.New("name and phone are required")
	}
	if r.Password == "" {
		return errors.New("a password is required so this staff member can log in")
	}
	if len(r.Password) < minPasswordLength {
		return fmt.Errorf("password must be at least %d characters", minPasswordLength)
	}
	if r.Role != "" && r.Role != "owner" && r.Role != "staff" {
		return errors.New("role must be owner or staff")
	}
	return nil
}

// CreateStaff adds a merchant staff member (Section 4.9 multi-user roles).
// The password is set by the merchant on the staff member's behalf (told
// to them out-of-band) so the staff member can log in themselves via
// MerchantLogin (auth.go) rather than sharing the owner's session. Email
// is optional — see createStaffRequest.validate.
func (h *Handler) CreateStaff(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req createStaffRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if err := req.validate(); err != nil {
		return badRequest(c, err.Error())
	}
	role := req.Role
	if role == "" {
		role = "staff"
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
