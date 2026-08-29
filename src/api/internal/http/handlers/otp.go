package handlers

import (
	"context"
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
	"github.com/orderxpay/api/internal/sms"
)

const (
	otpRequestWindow        = time.Hour
	otpMaxRequestsPerWindow = 5
	otpExpiry               = 10 * time.Minute
	otpMaxAttempts          = 5
	otpVerifiedWindow       = 30 * time.Minute
)

func sendOTPSMSAsync(client *sms.Client, phone, message string) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := client.Send(ctx, phone, message); err != nil {
		log.Printf("otp: failed to SMS code to %s: %v", phone, err)
	}
}

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
// Sent via sms.Client (Arkesel) when SMS_API_KEY is configured — see
// smsClient in integrations.go for the DB-secret-override path. A send
// failure is logged, not surfaced as a request failure: the code was
// already persisted and is still valid, and dev_otp (dev mode only)
// remains available as a fallback way to complete the flow. When no SMS
// provider is configured at all (Enabled() false), this silently falls
// back to the old log-only behavior — same graceful-degrade posture as
// every other optional integration in this codebase.
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

	client := h.smsClient(c.Context())
	if client.Enabled() {
		// Dispatched in the background, deliberately not awaited: the code
		// is already persisted and valid the moment this request returns,
		// so there's no reason to make the merchant's "Send OTP" tap sit
		// through however long the SMS provider (or the network path to
		// it) takes to respond. Found live: with a real Arkesel endpoint
		// but an unreachable network path, this blocked the response for
		// the full 15s client timeout — a bad tap-and-wait experience for
		// something that should feel instant. Uses its own bounded
		// context rather than c.Context(), which is canceled once the
		// HTTP response is written and the request handler returns.
		message := fmt.Sprintf("Your OrderxPay verification code is %s. It expires in %d minutes.", code, int(otpExpiry.Minutes()))
		go sendOTPSMSAsync(client, req.Phone, message)
	} else {
		log.Printf("otp: would SMS code %s to %s — no SMS provider configured, dev-mode-only delivery", code, req.Phone)
	}

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
