package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"math/big"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

const (
	otpRequestWindow        = time.Hour
	otpMaxRequestsPerWindow = 5
	otpExpiry               = 10 * time.Minute
	otpMaxAttempts          = 5
	otpVerifiedWindow       = 30 * time.Minute
)

func generateOTPCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

func generateVerificationToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

type requestPhoneOTPRequest struct {
	Phone string `json:"phone"`
}

// RequestPhoneOTP generates a 6-digit code for Page 1 of registration
// (Section 4.1) — business name/category/phone must be OTP-verified before
// Page 2 (username/email/password) is allowed to create the merchant.
//
// No SMS provider is wired up (Section 9 — not yet selected), so this
// can't actually text the code to anyone. Rather than fake success, the
// code is logged server-side and, only when the API is running in
// ENV=development, returned directly in the response as dev_otp so the
// whole flow is genuinely testable end-to-end locally. This must be
// removed/replaced with a real SMS integration before real users register.
func (h *Handler) RequestPhoneOTP(c *fiber.Ctx) error {
	var req requestPhoneOTPRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Phone == "" {
		return badRequest(c, "phone is required")
	}

	count, err := h.Queries.CountRecentPhoneOTPs(c.Context(), db.CountRecentPhoneOTPsParams{
		Phone:     req.Phone,
		CreatedAt: pgtype.Timestamptz{Time: time.Now().Add(-otpRequestWindow), Valid: true},
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to check request rate"})
	}
	if count >= otpMaxRequestsPerWindow {
		return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{"error": "too many codes requested for this number — try again later"})
	}

	code, err := generateOTPCode()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to generate code"})
	}

	otp, err := h.Queries.CreatePhoneOTP(c.Context(), db.CreatePhoneOTPParams{
		Phone:     req.Phone,
		Code:      code,
		ExpiresAt: pgtype.Timestamptz{Time: time.Now().Add(otpExpiry), Valid: true},
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create code"})
	}

	log.Printf("otp: would SMS code %s to %s — no SMS provider wired up, dev-mode-only delivery", code, req.Phone)

	resp := fiber.Map{
		"expires_at":  otp.ExpiresAt.Time,
		"ttl_seconds": int(otpExpiry.Seconds()),
	}
	if h.DevMode {
		resp["dev_otp"] = code
	}
	return c.JSON(resp)
}

type verifyPhoneOTPRequest struct {
	Phone string `json:"phone"`
	Code  string `json:"code"`
}

// VerifyPhoneOTP checks a code against the most recently requested OTP for
// that phone, enforcing both expiry and a per-code attempt cap — once
// exhausted, the caller must request a fresh code (itself rate-limited by
// RequestPhoneOTP).
func (h *Handler) VerifyPhoneOTP(c *fiber.Ctx) error {
	var req verifyPhoneOTPRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Phone == "" || req.Code == "" {
		return badRequest(c, "phone and code are required")
	}

	otp, err := h.Queries.GetLatestPhoneOTP(c.Context(), req.Phone)
	if errors.Is(err, pgx.ErrNoRows) {
		return badRequest(c, "no code found for this number — request a new one")
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load code"})
	}

	if otp.VerifiedAt.Valid {
		return c.JSON(fiber.Map{"verified": true})
	}
	if time.Now().After(otp.ExpiresAt.Time) {
		return badRequest(c, "code expired — request a new one")
	}
	if otp.AttemptCount >= otpMaxAttempts {
		return badRequest(c, "too many attempts — request a new code")
	}

	if otp.Code != req.Code {
		if err := h.Queries.IncrementPhoneOTPAttempts(c.Context(), otp.ID); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to record attempt"})
		}
		remaining := otpMaxAttempts - (otp.AttemptCount + 1)
		if remaining < 0 {
			remaining = 0
		}
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error":              "invalid code",
			"attempts_remaining": remaining,
		})
	}

	if err := h.Queries.MarkPhoneOTPVerified(c.Context(), otp.ID); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to verify code"})
	}
	return c.JSON(fiber.Map{"verified": true})
}

// VerifyMerchantEmail is what a real "verify your email" link would hit —
// no email provider is wired up either (see CreateMerchant), so nothing
// sends this link today, but the verification mechanism itself is real:
// a live token genuinely flips email_verified_at.
func (h *Handler) VerifyMerchantEmail(c *fiber.Ctx) error {
	token := c.Query("token")
	if token == "" {
		return badRequest(c, "token is required")
	}

	ev, err := h.Queries.GetEmailVerificationByToken(c.Context(), token)
	if errors.Is(err, pgx.ErrNoRows) {
		return badRequest(c, "invalid or expired verification link")
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to look up verification link"})
	}
	if ev.UsedAt.Valid {
		return c.JSON(fiber.Map{"verified": true})
	}
	if time.Now().After(ev.ExpiresAt.Time) {
		return badRequest(c, "verification link has expired")
	}

	if err := h.Queries.MarkEmailVerificationUsed(c.Context(), ev.ID); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to verify email"})
	}
	if _, err := h.Queries.MarkMerchantEmailVerified(c.Context(), ev.MerchantID); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to verify email"})
	}
	return c.JSON(fiber.Map{"verified": true})
}
