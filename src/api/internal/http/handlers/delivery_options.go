package handlers

import (
	"github.com/gofiber/fiber/v2"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type createDeliveryOptionRequest struct {
	Type               string `json:"type"` // own_contact | verified_provider
	ContactName        string `json:"contact_name"`
	ContactPhone       string `json:"contact_phone"`
	ProviderKey        string `json:"provider_key"`
	DeepLinkTemplate   string `json:"deep_link_template"`
	FeeHandlingDefault string `json:"fee_handling_default"` // bundled | external
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

	option, err := h.Queries.CreateDeliveryOption(c.Context(), db.CreateDeliveryOptionParams{
		MerchantID:         merchantID,
		Type:               req.Type,
		ContactName:        textOrNull(req.ContactName),
		ContactPhone:       textOrNull(req.ContactPhone),
		ProviderKey:        textOrNull(req.ProviderKey),
		DeepLinkTemplate:   textOrNull(req.DeepLinkTemplate),
		FeeHandlingDefault: feeHandling,
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

	if err := h.Queries.SetDeliveryOptionStatus(c.Context(), db.SetDeliveryOptionStatusParams{
		ID:     optionID,
		Status: req.Status,
	}); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update delivery option"})
	}
	return c.SendStatus(fiber.StatusNoContent)
}
