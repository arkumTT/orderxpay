package handlers

import (
	"encoding/json"
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

// Section 4.8 (revised): admins tune the three components that make up the
// blended platform rate — collection fee, payout fee, margin — instead of
// typing the blended commission_bps figure directly. commission_bps is
// derived server-side (see fee_rules.sql) so it can never drift from the
// sum of its parts.
type upsertFeeRuleRequest struct {
	CollectionFeeBps int32  `json:"collection_fee_bps"`
	PayoutFeeBps     int32  `json:"payout_fee_bps"`
	MarginBps        int32  `json:"margin_bps"`
	AllocationType   string `json:"allocation_type"`
}

func (r upsertFeeRuleRequest) validate() error {
	if r.CollectionFeeBps < 0 || r.PayoutFeeBps < 0 || r.MarginBps < 0 {
		return errors.New("collection_fee_bps, payout_fee_bps, and margin_bps must not be negative")
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

	before, beforeErr := h.Queries.GetGlobalFeeRule(c.Context())

	rule, err := h.Queries.UpsertGlobalFeeRule(c.Context(), db.UpsertGlobalFeeRuleParams{
		CollectionFeeBps: req.CollectionFeeBps,
		PayoutFeeBps:     req.PayoutFeeBps,
		MarginBps:        req.MarginBps,
		AllocationType:   req.AllocationType,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to upsert global fee rule"})
	}

	var beforeJSON []byte
	if beforeErr == nil {
		beforeJSON, _ = json.Marshal(fiber.Map{
			"collection_fee_bps": before.CollectionFeeBps, "payout_fee_bps": before.PayoutFeeBps,
			"margin_bps": before.MarginBps, "commission_bps": before.CommissionBps, "allocation_type": before.AllocationType,
		})
	}
	after, _ := json.Marshal(fiber.Map{
		"collection_fee_bps": rule.CollectionFeeBps, "payout_fee_bps": rule.PayoutFeeBps,
		"margin_bps": rule.MarginBps, "commission_bps": rule.CommissionBps, "allocation_type": rule.AllocationType,
	})
	if err := writeAdminAuditLog(c, h, "fee_rule.global_update", "fee_rule", rule.ID, beforeJSON, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
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

	before, beforeErr := h.Queries.GetFeeRuleByMerchant(c.Context(), merchantID)

	rule, err := h.Queries.UpsertMerchantFeeRule(c.Context(), db.UpsertMerchantFeeRuleParams{
		MerchantID:       merchantID,
		CollectionFeeBps: req.CollectionFeeBps,
		PayoutFeeBps:     req.PayoutFeeBps,
		MarginBps:        req.MarginBps,
		AllocationType:   req.AllocationType,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to upsert merchant fee rule"})
	}

	var beforeJSON []byte
	if beforeErr == nil {
		beforeJSON, _ = json.Marshal(fiber.Map{
			"collection_fee_bps": before.CollectionFeeBps, "payout_fee_bps": before.PayoutFeeBps,
			"margin_bps": before.MarginBps, "commission_bps": before.CommissionBps, "allocation_type": before.AllocationType,
		})
	}
	after, _ := json.Marshal(fiber.Map{
		"collection_fee_bps": rule.CollectionFeeBps, "payout_fee_bps": rule.PayoutFeeBps,
		"margin_bps": rule.MarginBps, "commission_bps": rule.CommissionBps, "allocation_type": rule.AllocationType,
	})
	if err := writeAdminAuditLog(c, h, "fee_rule.merchant_override", "merchant", merchantID, beforeJSON, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(rule)
}

// ListFeeRuleOverrides backs the pricing page's override list (Section 7.4).
func (h *Handler) ListFeeRuleOverrides(c *fiber.Ctx) error {
	overrides, err := h.Queries.ListMerchantFeeRuleOverrides(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list fee rule overrides"})
	}
	return c.JSON(overrides)
}

// DeleteMerchantFeeRule reverts a merchant back to the platform default —
// the counterpart to UpsertMerchantFeeRule, which had no way to undo an
// override once set.
func (h *Handler) DeleteMerchantFeeRule(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	before, err := h.Queries.GetFeeRuleByMerchant(c.Context(), merchantID)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load fee rule"})
	}

	if err := h.Queries.DeleteMerchantFeeRule(c.Context(), merchantID); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to remove fee rule override"})
	}

	beforeJSON, _ := json.Marshal(fiber.Map{"commission_bps": before.CommissionBps, "allocation_type": before.AllocationType})
	if err := writeAdminAuditLog(c, h, "fee_rule.merchant_override_removed", "merchant", merchantID, beforeJSON, nil); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.SendStatus(fiber.StatusNoContent)
}
