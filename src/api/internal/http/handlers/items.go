package handlers

import (
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type itemRequest struct {
	Name               string `json:"name"`
	UnitPricePesewas   int64  `json:"unit_price_pesewas"`
	QtyUnit            string `json:"qty_unit"`
	ImageURL           string `json:"image_url"`
	AvailabilityStatus string `json:"availability_status"`
}

func (r itemRequest) validate() error {
	if r.Name == "" {
		return errors.New("name is required")
	}
	if r.UnitPricePesewas < 0 {
		return errors.New("unit_price_pesewas must not be negative")
	}
	switch r.AvailabilityStatus {
	case "", "in_stock", "out_of_stock", "made_to_order":
	default:
		return errors.New("availability_status must be one of in_stock, out_of_stock, made_to_order")
	}
	return nil
}

// CreateItem adds to the merchant's catalog (Section 4.2) — the same record
// powers the hosted catalog page (Section 4.6).
func (h *Handler) CreateItem(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req itemRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if err := req.validate(); err != nil {
		return badRequest(c, err.Error())
	}
	availability := req.AvailabilityStatus
	if availability == "" {
		availability = "in_stock"
	}

	item, err := h.Queries.CreateItem(c.Context(), db.CreateItemParams{
		MerchantID:         merchantID,
		Name:               req.Name,
		UnitPricePesewas:   req.UnitPricePesewas,
		QtyUnit:            textOrNull(req.QtyUnit),
		ImageUrl:           textOrNull(req.ImageURL),
		AvailabilityStatus: availability,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create item"})
	}
	return c.Status(fiber.StatusCreated).JSON(item)
}

func (h *Handler) GetItem(c *fiber.Ctx) error {
	itemID, err := parseUUIDParam(c, "itemId")
	if err != nil {
		return badRequest(c, "invalid item id")
	}

	item, err := h.Queries.GetItem(c.Context(), itemID)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load item"})
	}
	return c.JSON(item)
}

func (h *Handler) ListItems(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	items, err := h.Queries.ListItemsByMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list items"})
	}
	return c.JSON(items)
}

func (h *Handler) UpdateItem(c *fiber.Ctx) error {
	itemID, err := parseUUIDParam(c, "itemId")
	if err != nil {
		return badRequest(c, "invalid item id")
	}

	var req itemRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if err := req.validate(); err != nil {
		return badRequest(c, err.Error())
	}
	availability := req.AvailabilityStatus
	if availability == "" {
		availability = "in_stock"
	}

	item, err := h.Queries.UpdateItem(c.Context(), db.UpdateItemParams{
		ID:                 itemID,
		Name:               req.Name,
		UnitPricePesewas:   req.UnitPricePesewas,
		QtyUnit:            textOrNull(req.QtyUnit),
		ImageUrl:           textOrNull(req.ImageURL),
		AvailabilityStatus: availability,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update item"})
	}
	return c.JSON(item)
}

// ArchiveItem is a soft-delete (Section 4.2: "archive vs. delete").
func (h *Handler) ArchiveItem(c *fiber.Ctx) error {
	itemID, err := parseUUIDParam(c, "itemId")
	if err != nil {
		return badRequest(c, "invalid item id")
	}
	if err := h.Queries.ArchiveItem(c.Context(), itemID); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to archive item"})
	}
	return c.SendStatus(fiber.StatusNoContent)
}
