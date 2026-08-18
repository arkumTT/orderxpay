package handlers

import (
	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type createDeliveryOptionRequest struct {
	Type               string `json:"type"` // own_contact | verified_provider
	ContactName        string `json:"contact_name"`
	ContactPhone       string `json:"contact_phone"`
	ProviderKey        string `json:"provider_key"`
	DeepLinkTemplate   string `json:"deep_link_template"`
	FeeHandlingDefault string `json:"fee_handling_default"` // bundled | external
	FlatFeePesewas     *int64 `json:"flat_fee_pesewas"`
	ServiceZone        string `json:"service_zone"`
}

// CreateDeliveryOption configures a merchant's delivery choice (Section 4.11,
// tiers 1 & 2). The verified-provider list itself is maintained by the Back
// Office (Section 7.3 / 9.4), not hardcoded here.
func (h *Handler) CreateDeliveryOption(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req createDeliveryOptionRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Type != "own_contact" && req.Type != "verified_provider" {
		return badRequest(c, "type must be own_contact or verified_provider")
	}
	feeHandling := req.FeeHandlingDefault
	if feeHandling == "" {
		feeHandling = "external"
	}
	if feeHandling != "bundled" && feeHandling != "external" {
		return badRequest(c, "fee_handling_default must be bundled or external")
	}

	var flatFee pgtype.Int8
	if req.FlatFeePesewas != nil {
		flatFee = pgtype.Int8{Int64: *req.FlatFeePesewas, Valid: true}
	}

	option, err := h.Queries.CreateDeliveryOption(c.Context(), db.CreateDeliveryOptionParams{
		MerchantID:         merchantID,
		Type:               req.Type,
		ContactName:        textOrNull(req.ContactName),
		ContactPhone:       textOrNull(req.ContactPhone),
		ProviderKey:        textOrNull(req.ProviderKey),
		DeepLinkTemplate:   textOrNull(req.DeepLinkTemplate),
		FeeHandlingDefault: feeHandling,
		FlatFeePesewas:     flatFee,
		ServiceZone:        textOrNull(req.ServiceZone),
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create delivery option"})
	}
	return c.Status(fiber.StatusCreated).JSON(option)
}

func (h *Handler) ListDeliveryOptions(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	options, err := h.Queries.ListDeliveryOptionsByMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list delivery options"})
	}
	return c.JSON(options)
}

type setDeliveryOptionStatusRequest struct {
	Status string `json:"status"` // active | inactive
}

func (h *Handler) SetDeliveryOptionStatus(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	optionID, err := parseUUIDParam(c, "optionId")
	if err != nil {
		return badRequest(c, "invalid delivery option id")
	}

	var req setDeliveryOptionStatusRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Status != "active" && req.Status != "inactive" {
		return badRequest(c, "status must be active or inactive")
	}

	rows, err := h.Queries.SetDeliveryOptionStatus(c.Context(), db.SetDeliveryOptionStatusParams{
		ID:         optionID,
		Status:     req.Status,
		MerchantID: merchantID,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update delivery option"})
	}
	if rows == 0 {
		return notFound(c)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

type updateDeliveryOptionRequest struct {
	ContactName        string `json:"contact_name"`
	ContactPhone       string `json:"contact_phone"`
	FlatFeePesewas     *int64 `json:"flat_fee_pesewas"`
	ServiceZone        string `json:"service_zone"`
	FeeHandlingDefault string `json:"fee_handling_default"` // bundled | external
	Status             string `json:"status"`               // active | inactive
}

// UpdateDeliveryOption is the full edit path (Section 4.11, fuller Delivery
// Settings page) — backs both the contact/provider edit sheet and the
// inline fee-handling selector on already-enabled catalog providers.
// SetDeliveryOptionStatus above stays as the narrow status-only toggle
// used by the catalog provider on/off switch.
func (h *Handler) UpdateDeliveryOption(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	optionID, err := parseUUIDParam(c, "optionId")
	if err != nil {
		return badRequest(c, "invalid delivery option id")
	}

	var req updateDeliveryOptionRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Status != "active" && req.Status != "inactive" {
		return badRequest(c, "status must be active or inactive")
	}
	feeHandling := req.FeeHandlingDefault
	if feeHandling == "" {
		feeHandling = "external"
	}
	if feeHandling != "bundled" && feeHandling != "external" {
		return badRequest(c, "fee_handling_default must be bundled or external")
	}

	var flatFee pgtype.Int8
	if req.FlatFeePesewas != nil {
		flatFee = pgtype.Int8{Int64: *req.FlatFeePesewas, Valid: true}
	}

	rows, err := h.Queries.UpdateDeliveryOption(c.Context(), db.UpdateDeliveryOptionParams{
		ID:                 optionID,
		ContactName:        textOrNull(req.ContactName),
		ContactPhone:       textOrNull(req.ContactPhone),
		FlatFeePesewas:     flatFee,
		ServiceZone:        textOrNull(req.ServiceZone),
		FeeHandlingDefault: feeHandling,
		Status:             req.Status,
		MerchantID:         merchantID,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update delivery option"})
	}
	if rows == 0 {
		return notFound(c)
	}
	return c.SendStatus(fiber.StatusNoContent)
}
