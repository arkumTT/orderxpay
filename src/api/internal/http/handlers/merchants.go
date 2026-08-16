package handlers

import (
	"encoding/json"
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type createMerchantRequest struct {
	BusinessName string `json:"business_name"`
	Category     string `json:"category"`
	Phone        string `json:"phone"`
}

// CreateMerchant is the merchant self-serve sign-up (Section 4.1, Tier 0 KYC).
func (h *Handler) CreateMerchant(c *fiber.Ctx) error {
	var req createMerchantRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.BusinessName == "" || req.Phone == "" {
		return badRequest(c, "business_name and phone are required")
	}

	merchant, err := h.Queries.CreateMerchant(c.Context(), db.CreateMerchantParams{
		BusinessName: req.BusinessName,
		Category:     textOrNull(req.Category),
		Phone:        req.Phone,
	})
	if err != nil {
		return c.Status(fiber.StatusConflict).JSON(fiber.Map{"error": "merchant with this phone may already exist"})
	}
	return c.Status(fiber.StatusCreated).JSON(merchant)
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
	return c.JSON(merchant)
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
	return c.JSON(merchants)
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

	return c.JSON(merchant)
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

	return c.JSON(merchant)
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
	return c.JSON(merchant)
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
	return c.JSON(merchant)
}
