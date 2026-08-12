package handlers

import (
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// GetGlobalFeeRule returns the platform-wide default commission (Section 7.4).
func (h *Handler) GetGlobalFeeRule(c *fiber.Ctx) error {
	rule, err := h.Queries.GetGlobalFeeRule(c.Context())
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load global fee rule"})
	}
	return c.JSON(rule)
}

type upsertFeeRuleRequest struct {
	CommissionBps  int32  `json:"commission_bps"`
	AllocationType string `json:"allocation_type"`
}

func (r upsertFeeRuleRequest) validate() error {
	if r.CommissionBps < 0 {
		return errors.New("commission_bps must not be negative")
	}
	switch r.AllocationType {
	case "customer_only", "merchant_only", "split":
	default:
		return errors.New("allocation_type must be one of customer_only, merchant_only, split")
	}
	return nil
}

// UpsertGlobalFeeRule is a Back Office pricing action (Section 7.4).
func (h *Handler) UpsertGlobalFeeRule(c *fiber.Ctx) error {
	var req upsertFeeRuleRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if err := req.validate(); err != nil {
		return badRequest(c, err.Error())
	}

	rule, err := h.Queries.UpsertGlobalFeeRule(c.Context(), db.UpsertGlobalFeeRuleParams{
		CommissionBps:  req.CommissionBps,
		AllocationType: req.AllocationType,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to upsert global fee rule"})
	}
	return c.JSON(rule)
}

// GetMerchantFeeRuleOrGlobal is called by the merchant app so the merchant can
// see exactly how commission is calculated on their transactions (Section
// 4.8: "full visibility ... so merchants trust the number"). Falls back to
// the platform default when no merchant-specific override exists.
func (h *Handler) GetMerchantFeeRuleOrGlobal(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	rule, err := h.Queries.GetFeeRuleByMerchant(c.Context(), merchantID)
	if errors.Is(err, pgx.ErrNoRows) {
		rule, err = h.Queries.GetGlobalFeeRule(c.Context())
		if errors.Is(err, pgx.ErrNoRows) {
			return notFound(c)
		}
	}
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load fee rule"})
	}
	return c.JSON(rule)
}

// UpsertMerchantFeeRule sets a merchant-specific commission override (Section 7.4).
func (h *Handler) UpsertMerchantFeeRule(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req upsertFeeRuleRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if err := req.validate(); err != nil {
		return badRequest(c, err.Error())
	}

	rule, err := h.Queries.UpsertMerchantFeeRule(c.Context(), db.UpsertMerchantFeeRuleParams{
		MerchantID:     merchantID,
		CommissionBps:  req.CommissionBps,
		AllocationType: req.AllocationType,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to upsert merchant fee rule"})
	}
	return c.JSON(rule)
}
