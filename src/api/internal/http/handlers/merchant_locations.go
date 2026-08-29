package handlers

import (
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type createMerchantLocationRequest struct {
	Label     string `json:"label"`
	Address   string `json:"address"`
	Phone     string `json:"phone"`
	IsDefault bool   `json:"is_default"`
}

// CreateMerchantLocation adds a pickup/delivery reference point (feedback
// item 4). Deliberately flat and merchant-managed — not tied to any
// delivery_options row — so it works equally for a merchant's own rider,
// a verified third-party provider, or a customer arranging their own
// pickup. The first location a merchant ever adds becomes the default
// automatically, so there's always one to pre-fill with once any exist.
func (h *Handler) CreateMerchantLocation(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req createMerchantLocationRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Label == "" {
		return badRequest(c, "label is required")
	}
	if req.Address == "" {
		return badRequest(c, "address is required")
	}

	existing, err := h.Queries.ListMerchantLocationsByMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to check existing locations"})
	}
	makeDefault := req.IsDefault || len(existing) == 0

	if makeDefault {
		if err := h.Queries.ClearDefaultMerchantLocation(c.Context(), merchantID); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to clear existing default location"})
		}
	}

	location, err := h.Queries.CreateMerchantLocation(c.Context(), db.CreateMerchantLocationParams{
		MerchantID: merchantID,
		Label:      req.Label,
		Address:    req.Address,
		Phone:      textOrNull(req.Phone),
		IsDefault:  makeDefault,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create location"})
	}
	return c.Status(fiber.StatusCreated).JSON(location)
}

func (h *Handler) ListMerchantLocations(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	locations, err := h.Queries.ListMerchantLocationsByMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list locations"})
	}
	return c.JSON(locations)
}

type updateMerchantLocationRequest struct {
	Label   string `json:"label"`
	Address string `json:"address"`
	Phone   string `json:"phone"`
	Status  string `json:"status"` // active | inactive
}

func (h *Handler) UpdateMerchantLocation(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	locationID, err := parseUUIDParam(c, "locationId")
	if err != nil {
		return badRequest(c, "invalid location id")
	}

	var req updateMerchantLocationRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Label == "" {
		return badRequest(c, "label is required")
	}
	if req.Address == "" {
		return badRequest(c, "address is required")
	}
	if req.Status != "active" && req.Status != "inactive" {
		return badRequest(c, "status must be active or inactive")
	}

	rows, err := h.Queries.UpdateMerchantLocation(c.Context(), db.UpdateMerchantLocationParams{
		ID:         locationID,
		Label:      req.Label,
		Address:    req.Address,
		Phone:      textOrNull(req.Phone),
		Status:     req.Status,
		MerchantID: merchantID,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update location"})
	}
	if rows == 0 {
		return notFound(c)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

// SetDefaultMerchantLocation promotes one location to default, clearing
// whatever the previous default was first (ClearDefaultMerchantLocation)
// so the partial unique index on (merchant_id) WHERE is_default never sees
// two defaults for the same merchant, even transiently within the request.
func (h *Handler) SetDefaultMerchantLocation(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	locationID, err := parseUUIDParam(c, "locationId")
	if err != nil {
		return badRequest(c, "invalid location id")
	}

	if _, err := h.Queries.GetMerchantLocation(c.Context(), locationID); errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load location"})
	}

	if err := h.Queries.ClearDefaultMerchantLocation(c.Context(), merchantID); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to clear existing default location"})
	}
	rows, err := h.Queries.SetDefaultMerchantLocation(c.Context(), db.SetDefaultMerchantLocationParams{
		ID:         locationID,
		MerchantID: merchantID,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to set default location"})
	}
	if rows == 0 {
		return notFound(c)
	}
	return c.SendStatus(fiber.StatusNoContent)
}
