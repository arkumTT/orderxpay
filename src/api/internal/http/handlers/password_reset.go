package handlers

import (
	"errors"
	"fmt"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/crypto/bcrypt"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type resetPasswordRequest struct {
	Phone       string `json:"phone"`
	NewPassword string `json:"new_password"`
}

func (r resetPasswordRequest) validate() error {
	if r.Phone == "" {
		return errors.New("phone is required")
	}
	if len(r.NewPassword) < minPasswordLength {
		return fmt.Errorf("new_password must be at least %d characters", minPasswordLength)
	}
	return nil
}

// ResetPassword is the self-service recovery path phone-first accounts have
// needed since CreateStaff/CreateMerchant stopped requiring an email —
// found while resolving whether email should ever be required (it
// shouldn't; see the roadmap): without this, a merchant or staff member who
// forgets their password has no way back into their own account, on any
// channel.
//
// The mobile flow is two calls before this one, not three: RequestPhoneOTP
// and VerifyPhoneOTP are already public and already used by registration to
// prove a caller controls a phone number. This endpoint reuses that same
// proof rather than asking for the code again — it checks
// GetRecentVerifiedPhoneOTP within otpVerifiedWindow, the exact freshness
// bound CreateMerchant already trusts to create a fully-authenticated
// account from nothing but a verified phone. Resetting a password is a
// smaller ask than that.
//
// Checks merchants first, then staff, for whichever account has this phone
// on file — same precedence as MerchantLogin. Unlike MerchantLogin's
// deliberately generic "invalid credentials", a phone with no account on
// either side gets a specific error: this request only reaches the account
// -lookup step after a real SMS OTP was verified, which is already a much
// higher bar than a login attempt, so there's much less to protect by
// staying vague — and a merchant who mistyped their number deserves that
// concrete feedback, not a dead end. Never returns a token: like
// registration, the caller is sent back to the login screen to sign in with
// the password they just set.
func (h *Handler) ResetPassword(c *fiber.Ctx) error {
	var req resetPasswordRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if err := req.validate(); err != nil {
		return badRequest(c, err.Error())
	}

	_, err := h.Queries.GetRecentVerifiedPhoneOTP(c.Context(), db.GetRecentVerifiedPhoneOTPParams{
		Phone:      req.Phone,
		VerifiedAt: pgtype.Timestamptz{Time: time.Now().Add(-otpVerifiedWindow), Valid: true},
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return badRequest(c, "phone not verified — please verify via OTP first")
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to check phone verification"})
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to process password"})
	}

	merchant, err := h.Queries.GetMerchantByPhone(c.Context(), req.Phone)
	if err == nil {
		if _, err := h.Queries.UpdateMerchantPassword(c.Context(), db.UpdateMerchantPasswordParams{
			ID:           merchant.ID,
			PasswordHash: textOrNull(string(hash)),
		}); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update password"})
		}
		return c.JSON(fiber.Map{"reset": true})
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to look up account"})
	}

	staff, err := h.Queries.GetStaffByPhone(c.Context(), req.Phone)
	if errors.Is(err, pgx.ErrNoRows) {
		return badRequest(c, "no account found for that phone number")
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to look up account"})
	}

	if _, err := h.Queries.UpdateStaffPassword(c.Context(), db.UpdateStaffPasswordParams{
		ID:           staff.ID,
		PasswordHash: textOrNull(string(hash)),
	}); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update password"})
	}
	return c.JSON(fiber.Map{"reset": true})
}
