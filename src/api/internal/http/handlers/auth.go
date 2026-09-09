package handlers

import (
	"errors"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"

	"github.com/orderxpay/api/internal/auth"
	db "github.com/orderxpay/api/internal/db/sqlc"
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
	Phone    string `json:"phone"`
	Password string `json:"password"`
}

// validate requires a password and exactly one way to say who's logging
// in. If a caller sends both email and phone (the mobile login screen
// never does — it sends whichever one field the merchant typed), email
// wins; that's a precedence rule for a malformed request, not something
// worth rejecting outright.
func (r merchantLoginRequest) validate() error {
	if r.Password == "" {
		return errors.New("password is required")
	}
	if r.Email == "" && r.Phone == "" {
		return errors.New("email or phone is required")
	}
	return nil
}

// MerchantLogin authenticates a merchant owner or a staff member (Section
// 4.1/4.9) by password, from one shared mobile login screen, identified by
// either email or phone — exactly one is expected per request (the mobile
// login screen sends whichever the merchant typed, sniffed by an "@").
// Phone exists as an identifier because CreateMerchant no longer requires
// an email at signup (Section 4.1 phone-first registration): a merchant
// who never added one still needs a way in.
//
// It checks the merchants table first, then staff, for whichever
// identifier was given — both are independent spaces per identifier (a
// merchant's email/phone isn't guaranteed unique against a different
// merchant's staff email/phone), so collisions across the two tables
// aren't prevented today; this was already true of the email path and the
// phone path deliberately mirrors it rather than inventing a different
// precedence rule for one identifier and not the other. The generic
// "invalid credentials" error on every failure path is deliberate — it
// never reveals whether an identifier exists in either table.
func (h *Handler) MerchantLogin(c *fiber.Ctx) error {
	var req merchantLoginRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if err := req.validate(); err != nil {
		return badRequest(c, err.Error())
	}

	var merchant db.Merchant
	var err error
	if req.Email != "" {
		merchant, err = h.Queries.GetMerchantByEmail(c.Context(), req.Email)
	} else {
		merchant, err = h.Queries.GetMerchantByPhone(c.Context(), req.Phone)
	}
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

	var staff db.Staff
	if req.Email != "" {
		staff, err = h.Queries.GetStaffByEmail(c.Context(), req.Email)
	} else {
		staff, err = h.Queries.GetStaffByPhone(c.Context(), req.Phone)
	}
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
