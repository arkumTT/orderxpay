package handlers

import (
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

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

// UpdateMerchantStatus is a Back Office action (Section 7.1: suspend/restrict/activate).
// TODO: route through the maker-checker / audit-log conventions once Module 11 equivalent exists.
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

	merchant, err := h.Queries.UpdateMerchantStatus(c.Context(), db.UpdateMerchantStatusParams{
		ID:     id,
		Status: req.Status,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update merchant status"})
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

	merchant, err := h.Queries.UpdateMerchantKYCTier(c.Context(), db.UpdateMerchantKYCTierParams{
		ID:      id,
		KycTier: req.KYCTier,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update KYC tier"})
	}
	return c.JSON(merchant)
}
