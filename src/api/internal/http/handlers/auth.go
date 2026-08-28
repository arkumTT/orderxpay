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

type merchantLoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// MerchantLogin authenticates a merchant owner or a staff member (Section
// 4.1/4.9) by email+password, from one shared mobile login screen. It
// checks the merchants table first, then staff — both are independent
// email spaces (a merchant's email isn't guaranteed unique against a
// different merchant's staff email), so collisions across the two tables
// aren't prevented today. The generic "invalid credentials" error on every
// failure path is deliberate — it never reveals whether an email exists in
// either table.
func (h *Handler) MerchantLogin(c *fiber.Ctx) error {
	var req merchantLoginRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Email == "" || req.Password == "" {
		return badRequest(c, "email and password are required")
	}

	merchant, err := h.Queries.GetMerchantByEmail(c.Context(), req.Email)
	if err == nil {
		if !merchant.PasswordHash.Valid ||
			bcrypt.CompareHashAndPassword([]byte(merchant.PasswordHash.String), []byte(req.Password)) != nil {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "invalid credentials"})
		}
		if merchant.Status == "suspended" {
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{"error": "merchant account is suspended"})
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
			"access_token":   token,
			"expires_at":     payload.ExpiredAt,
			"merchant_id":    merchant.ID,
			"actor_type":     string(auth.ActorMerchant),
			"business_name":  merchant.BusinessName,
			"email_verified": merchant.EmailVerifiedAt.Valid,
		})
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to look up account"})
	}

	staff, err := h.Queries.GetStaffByEmail(c.Context(), req.Email)
	if errors.Is(err, pgx.ErrNoRows) {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "invalid credentials"})
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to look up account"})
	}
	if !staff.PasswordHash.Valid ||
		bcrypt.CompareHashAndPassword([]byte(staff.PasswordHash.String), []byte(req.Password)) != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "invalid credentials"})
	}

	staffID := staff.ID.Bytes
	merchantID := staff.MerchantID.Bytes
	token, payload, err := h.TokenMaker.CreateToken(auth.CreateTokenParams{
		ActorID:    staffID,
		ActorType:  auth.ActorStaff,
		MerchantID: merchantID,
		Duration:   merchantTokenDuration,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create token"})
	}

	merchant, err = h.Queries.GetMerchant(c.Context(), staff.MerchantID)
	businessName := ""
	if err == nil {
		businessName = merchant.BusinessName
	}

	return c.JSON(fiber.Map{
		"access_token":  token,
		"expires_at":    payload.ExpiredAt,
		"merchant_id":   staff.MerchantID,
		"actor_type":    string(auth.ActorStaff),
		"business_name": businessName,
	})
}

const merchantTokenDuration = 24 * time.Hour

type devIssueTokenRequest struct {
	MerchantID string `json:"merchant_id"`
}

// DevIssueMerchantToken is a raw session bootstrap for a merchant that
// already exists, bypassing login entirely — same idea as cmd/devtoken,
// exposed over HTTP for quick backend/curl testing without going through
// the real MerchantLogin flow. Registered under /api/v1/public but refuses
// to do anything unless h.DevMode is true (ENV=development) — see
// cmd/api/main.go.
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
