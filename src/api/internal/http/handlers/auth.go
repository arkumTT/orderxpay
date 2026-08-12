package handlers

import (
	"errors"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"

	"github.com/orderxpay/api/internal/auth"
)

const adminTokenDuration = 12 * time.Hour

type adminLoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// AdminLogin authenticates Back Office staff (Section 7.8: Super Admin,
// Compliance/KYC Reviewer, Finance/Settlement, Support). There is no public
// admin-signup endpoint — admin_users are provisioned out-of-band (seed
// script / direct DB insert by a Super Admin), never self-registered.
func (h *Handler) AdminLogin(c *fiber.Ctx) error {
	var req adminLoginRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Email == "" || req.Password == "" {
		return badRequest(c, "email and password are required")
	}

	user, err := h.Queries.GetAdminUserByEmail(c.Context(), req.Email)
	if errors.Is(err, pgx.ErrNoRows) {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "invalid credentials"})
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to look up admin user"})
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "invalid credentials"})
	}

	actorID := user.ID.Bytes
	token, payload, err := h.TokenMaker.CreateToken(actorID, auth.ActorAdminUser, [16]byte{}, user.Role, adminTokenDuration)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create token"})
	}

	return c.JSON(fiber.Map{
		"access_token": token,
		"expires_at":   payload.ExpiredAt,
		"role":         user.Role,
	})
}

// RequestMerchantOTP / VerifyMerchantOTP back the merchant app's phone + OTP
// sign-up (Section 4.1). Not yet implemented: OTP delivery depends on the
// SMS provider integration (Section 9), which hasn't been selected.
func (h *Handler) RequestMerchantOTP(c *fiber.Ctx) error {
	return notImplemented(c, "OTP delivery not yet implemented — depends on SMS provider selection (Section 9)")
}

func (h *Handler) VerifyMerchantOTP(c *fiber.Ctx) error {
	return notImplemented(c, "OTP verification not yet implemented — depends on SMS provider selection (Section 9)")
}
