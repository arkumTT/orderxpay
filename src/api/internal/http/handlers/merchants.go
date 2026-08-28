package handlers

import (
	"encoding/json"
	"errors"
	"log"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/crypto/bcrypt"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

const emailVerificationExpiry = 24 * time.Hour

const minPasswordLength = 8

// stripMerchantSecrets zeroes password_hash before a Merchant row is ever
// serialized to a client — no handler should return a bcrypt hash, even to
// an authenticated admin or the merchant themselves.
func stripMerchantSecrets(m db.Merchant) db.Merchant {
	m.PasswordHash = pgtype.Text{}
	return m
}

type createMerchantRequest struct {
	BusinessName string `json:"business_name"`
	Category     string `json:"category"`
	Phone        string `json:"phone"`
	Username     string `json:"username"`
	Email        string `json:"email"`
	Password     string `json:"password"`
}

// CreateMerchant is Page 2 of the real registration flow (Section 4.1):
// Page 1 (business_name/category/phone) must already have a phone verified
// via RequestPhoneOTP/VerifyPhoneOTP (otp.go) within the last 30 minutes —
// this handler re-checks that server-side rather than trusting the client
// to have done Page 1 honestly. Page 2 itself supplies username/email/
// password.
//
// The merchant is created with email_verified_at unset; a real
// verification token is generated and would be emailed, but no email
// provider is wired up (Section 9), so — same honesty as the OTP side —
// the token/link is only exposed in the response when running in
// ENV=development. Email verification is advisory, not a login gate: see
// MerchantLogin, which returns email_verified so the app can show that
// state without blocking access.
func (h *Handler) CreateMerchant(c *fiber.Ctx) error {
	var req createMerchantRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.BusinessName == "" || req.Phone == "" {
		return badRequest(c, "business_name and phone are required")
	}
	if req.Username == "" {
		return badRequest(c, "username is required")
	}
	if req.Email == "" || req.Password == "" {
		return badRequest(c, "email and password are required")
	}
	if len(req.Password) < minPasswordLength {
		return badRequest(c, "password must be at least 8 characters")
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

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to process password"})
	}

	merchant, err := h.Queries.CreateMerchant(c.Context(), db.CreateMerchantParams{
		BusinessName: req.BusinessName,
		Category:     textOrNull(req.Category),
		Phone:        req.Phone,
		Username:     textOrNull(req.Username),
		Email:        textOrNull(req.Email),
		PasswordHash: textOrNull(string(hash)),
	})
	if err != nil {
		return c.Status(fiber.StatusConflict).JSON(fiber.Map{"error": "merchant with this phone, username, or email may already exist"})
	}

	var devToken string
	token, err := generateVerificationToken()
	if err != nil {
		log.Printf("email verification: failed to generate token for merchant %s: %v", merchant.ID, err)
	} else {
		ev, err := h.Queries.CreateEmailVerification(c.Context(), db.CreateEmailVerificationParams{
			MerchantID: merchant.ID,
			Token:      token,
			ExpiresAt:  pgtype.Timestamptz{Time: time.Now().Add(emailVerificationExpiry), Valid: true},
		})
		if err != nil {
			log.Printf("email verification: failed to create record for merchant %s: %v", merchant.ID, err)
		} else {
			log.Printf("email verification: would email %s a link with token %s — no email provider wired up, dev-mode-only delivery", req.Email, token)
			if h.DevMode {
				devToken = ev.Token
			}
		}
	}

	return c.Status(fiber.StatusCreated).JSON(createMerchantResponse{
		Merchant:            stripMerchantSecrets(merchant),
		DevEmailVerifyToken: devToken,
	})
}

type createMerchantResponse struct {
	db.Merchant
	DevEmailVerifyToken string `json:"dev_email_verify_token,omitempty"`
}

type merchantPublicProfile struct {
	ID           string `json:"id"`
	BusinessName string `json:"business_name"`
	Category     string `json:"category,omitempty"`
	Status       string `json:"status"`
}

// GetMerchantPublicProfile is what the hosted catalog page (Section 4.6) is
// allowed to show an unauthenticated customer — deliberately excludes
// payout_account_ref and other fields from the full Merchant record.
func (h *Handler) GetMerchantPublicProfile(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	merchant, err := h.Queries.GetMerchant(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}

	return c.JSON(merchantPublicProfile{
		ID:           c.Params("id"),
		BusinessName: merchant.BusinessName,
		Category:     merchant.Category.String,
		Status:       merchant.Status,
	})
}

func (h *Handler) GetMerchant(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	merchant, err := h.Queries.GetMerchant(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}
	return c.JSON(stripMerchantSecrets(merchant))
}

// ListMerchants backs the Back Office merchant list (Section 7.1).
func (h *Handler) ListMerchants(c *fiber.Ctx) error {
	limit := int32(c.QueryInt("limit", 50))
	offset := int32(c.QueryInt("offset", 0))

	merchants, err := h.Queries.ListMerchants(c.Context(), db.ListMerchantsParams{
		Limit:        limit,
		Offset:       offset,
		StatusFilter: c.Query("status"),
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list merchants"})
	}
	sanitized := make([]db.Merchant, len(merchants))
	for i, m := range merchants {
		sanitized[i] = stripMerchantSecrets(m)
	}
	return c.JSON(sanitized)
}

type updateMerchantStatusRequest struct {
	Status string `json:"status"`
}

// UpdateMerchantStatus is a Back Office action (Section 7.1: suspend/restrict/activate) —
// suspending immediately blocks new invoice creation (see CreateInvoice) and
// payouts (see settlement generation), without touching historical data.
func (h *Handler) UpdateMerchantStatus(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req updateMerchantStatusRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	switch req.Status {
	case "pending", "active", "restricted", "suspended":
	default:
		return badRequest(c, "status must be one of pending, active, restricted, suspended")
	}

	before, err := h.Queries.GetMerchant(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}

	merchant, err := h.Queries.UpdateMerchantStatus(c.Context(), db.UpdateMerchantStatusParams{
		ID:     id,
		Status: req.Status,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update merchant status"})
	}

	beforeJSON, _ := json.Marshal(fiber.Map{"status": before.Status})
	afterJSON, _ := json.Marshal(fiber.Map{"status": merchant.Status})
	if err := writeAdminAuditLog(c, h, "merchant.status_change", "merchant", id, beforeJSON, afterJSON); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(stripMerchantSecrets(merchant))
}

type updateMerchantKYCTierRequest struct {
	KYCTier int16 `json:"kyc_tier"`
}

// UpdateMerchantKYCTier is a Back Office KYC review action (Section 7.1).
func (h *Handler) UpdateMerchantKYCTier(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req updateMerchantKYCTierRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.KYCTier != 0 && req.KYCTier != 1 {
		return badRequest(c, "kyc_tier must be 0 or 1")
	}

	before, err := h.Queries.GetMerchant(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}

	merchant, err := h.Queries.UpdateMerchantKYCTier(c.Context(), db.UpdateMerchantKYCTierParams{
		ID:      id,
		KycTier: req.KYCTier,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update KYC tier"})
	}

	beforeJSON, _ := json.Marshal(fiber.Map{"kyc_tier": before.KycTier})
	afterJSON, _ := json.Marshal(fiber.Map{"kyc_tier": merchant.KycTier})
	if err := writeAdminAuditLog(c, h, "merchant.kyc_tier_change", "merchant", id, beforeJSON, afterJSON); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(stripMerchantSecrets(merchant))
}

type updateMerchantFeeSettingsRequest struct {
	ServiceChargeAllocation string  `json:"service_charge_allocation"` // customer_only | merchant_only | split
	ServiceChargeSplitBps   *int32  `json:"service_charge_split_bps"`  // required when allocation is split; % of the commission charged to the customer
	PayoutFeeAbsorption     *string `json:"payout_fee_absorption"`     // merchant_absorbed | blended_into_rate; defaults to merchant_absorbed if omitted
}

// UpdateMerchantFeeSettings is the merchant app's own fee-allocation control
// (Section 4.8) — this is what the invoice engine reads at invoice-creation
// time (see internal/http/handlers/invoice_engine.go).
func (h *Handler) UpdateMerchantFeeSettings(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req updateMerchantFeeSettingsRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	var splitBps pgtype.Int4
	switch req.ServiceChargeAllocation {
	case "customer_only", "merchant_only":
	case "split":
		if req.ServiceChargeSplitBps == nil || *req.ServiceChargeSplitBps < 0 || *req.ServiceChargeSplitBps > 10000 {
			return badRequest(c, "service_charge_split_bps must be between 0 and 10000 when allocation is split")
		}
		splitBps = pgtype.Int4{Int32: *req.ServiceChargeSplitBps, Valid: true}
	default:
		return badRequest(c, "service_charge_allocation must be one of customer_only, merchant_only, split")
	}

	payoutFeeAbsorption := "merchant_absorbed"
	if req.PayoutFeeAbsorption != nil {
		switch *req.PayoutFeeAbsorption {
		case "merchant_absorbed", "blended_into_rate":
			payoutFeeAbsorption = *req.PayoutFeeAbsorption
		default:
			return badRequest(c, "payout_fee_absorption must be one of merchant_absorbed, blended_into_rate")
		}
	}

	merchant, err := h.Queries.UpdateMerchantFeeSettings(c.Context(), db.UpdateMerchantFeeSettingsParams{
		ID:                      id,
		ServiceChargeAllocation: req.ServiceChargeAllocation,
		ServiceChargeSplitBps:   splitBps,
		PayoutFeeAbsorption:     payoutFeeAbsorption,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update fee settings"})
	}
	return c.JSON(stripMerchantSecrets(merchant))
}

type updateMerchantWhatsAppSettingsRequest struct {
	AutoReplyEnabled bool    `json:"auto_reply_enabled"`
	GreetingMessage  *string `json:"greeting_message"` // null/omitted clears the override — app falls back to its generated default
}

// UpdateMerchantWhatsAppSettings is the merchant app's own WhatsApp
// auto-reply preferences (Section 4.4/6.2). These are real, persisted
// settings, but nothing actually fires on them yet — the WhatsApp Business
// Solution Provider connection they'd drive isn't built (integrations.
// provider_key = 'whatsapp_bsp', Section 7.3).
func (h *Handler) UpdateMerchantWhatsAppSettings(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req updateMerchantWhatsAppSettingsRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	var greeting pgtype.Text
	if req.GreetingMessage != nil && *req.GreetingMessage != "" {
		greeting = pgtype.Text{String: *req.GreetingMessage, Valid: true}
	}

	merchant, err := h.Queries.UpdateMerchantWhatsAppSettings(c.Context(), db.UpdateMerchantWhatsAppSettingsParams{
		ID:                       id,
		WhatsappAutoReplyEnabled: req.AutoReplyEnabled,
		WhatsappGreetingMessage:  greeting,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update whatsapp settings"})
	}
	return c.JSON(stripMerchantSecrets(merchant))
}

type updateMerchantDeliveryEnabledRequest struct {
	Enabled bool `json:"enabled"`
}

// UpdateMerchantDeliveryEnabled is the master "Offer delivery" switch
// (Section 4.11, Prompt 9) — when off, the merchant app hides delivery
// selection at invoice creation entirely rather than showing an empty list.
func (h *Handler) UpdateMerchantDeliveryEnabled(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req updateMerchantDeliveryEnabledRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	merchant, err := h.Queries.UpdateMerchantDeliveryEnabled(c.Context(), db.UpdateMerchantDeliveryEnabledParams{
		ID:              id,
		DeliveryEnabled: req.Enabled,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update delivery settings"})
	}
	return c.JSON(stripMerchantSecrets(merchant))
}
