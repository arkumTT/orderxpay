package handlers

import (
	"errors"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"

	"github.com/orderxpay/api/internal/auth"
)

const userTokenDuration = 12 * time.Hour

type userLoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// UserLogin authenticates Back Office users (Section 7.8 RBAC: roles like
// Super Admin, Compliance Reviewer, Finance, Support — see
// db/migrations/000002_rbac_users.up.sql for the seeded catalog). There is
// no public signup endpoint — users are provisioned out-of-band via
// cmd/seed (first user) or by an existing Super Admin (everyone after).
func (h *Handler) UserLogin(c *fiber.Ctx) error {
	var req userLoginRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Email == "" || req.Password == "" {
		return badRequest(c, "email and password are required")
	}

	user, err := h.Queries.GetUserByEmail(c.Context(), req.Email)
	if errors.Is(err, pgx.ErrNoRows) {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "invalid credentials"})
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to look up user"})
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "invalid credentials"})
	}
	if user.Status != "active" {
		return c.Status(fiber.StatusForbidden).JSON(fiber.Map{"error": "user account is not active"})
	}

	roles, err := h.Queries.ListUserRoles(c.Context(), user.ID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load roles"})
	}
	permissionKeys, err := h.Queries.GetUserPermissionKeys(c.Context(), user.ID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load permissions"})
	}

	roleNames := make([]string, len(roles))
	for i, r := range roles {
		roleNames[i] = r.Name
	}

	actorID := user.ID.Bytes
	token, payload, err := h.TokenMaker.CreateToken(auth.CreateTokenParams{
		ActorID:     actorID,
		ActorType:   auth.ActorUser,
		Roles:       roleNames,
		Permissions: permissionKeys,
		Duration:    userTokenDuration,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create token"})
	}

	return c.JSON(fiber.Map{
		"access_token": token,
		"expires_at":   payload.ExpiredAt,
		"roles":        roleNames,
		"permissions":  permissionKeys,
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

const merchantTokenDuration = 24 * time.Hour

type devIssueTokenRequest struct {
	MerchantID string `json:"merchant_id"`
}

// DevIssueMerchantToken stands in for RequestMerchantOTP/VerifyMerchantOTP
// until that's built — same idea as cmd/devtoken, exposed over HTTP so the
// mobile app can get a session automatically right after onboarding instead
// of a developer running a CLI command by hand. Registered under
// /api/v1/public but refuses to do anything unless h.DevMode is true
// (ENV=development) — see cmd/api/main.go.
func (h *Handler) DevIssueMerchantToken(c *fiber.Ctx) error {
	if !h.DevMode {
		return notFound(c)
	}

	var req devIssueTokenRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	merchantID, err := parseUUID(req.MerchantID)
	if err != nil {
		return badRequest(c, "invalid merchant_id")
	}

	merchant, err := h.Queries.GetMerchant(c.Context(), merchantID)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}

	actorID := merchant.ID.Bytes
	token, payload, err := h.TokenMaker.CreateToken(auth.CreateTokenParams{
		ActorID:    actorID,
		ActorType:  auth.ActorMerchant,
		MerchantID: actorID,
		Duration:   merchantTokenDuration,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create token"})
	}

	return c.JSON(fiber.Map{
		"access_token": token,
		"expires_at":   payload.ExpiredAt,
	})
}
