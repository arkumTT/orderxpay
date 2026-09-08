package handlers

import (
	"encoding/json"
	"errors"
	"fmt"

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

// Section 4.8, revised again in migration 000028: admins tune what the
// platform actually pays out and what it keeps — the PSP collection fee it
// passes through, its own margin, and the floor and cap that keep that
// margin viable at both ends of the ticket range. commission_bps is derived
// server-side (see fee_rules.sql) so it can never drift from collection +
// margin.
//
// The payout side is deliberately not a percentage any more: the PSP charges
// a flat amount per transfer, so it is priced as a flat withdrawal fee,
// waived above a threshold to nudge merchants into batching.
type upsertFeeRuleRequest struct {
	CollectionFeeBps int32  `json:"collection_fee_bps"`
	MarginBps        int32  `json:"margin_bps"`
	AllocationType   string `json:"allocation_type"`

	// Clamps on the platform's own margin per invoice, never on the PSP
	// pass-through — so a capped invoice can still never cost more to
	// process than it charges. Zero means unclamped on either end.
	MarginFloorPesewas int64 `json:"margin_floor_pesewas"`
	MarginCapPesewas   int64 `json:"margin_cap_pesewas"`

	WithdrawalFeeMomoPesewas   int64 `json:"withdrawal_fee_momo_pesewas"`
	WithdrawalFeeBankPesewas   int64 `json:"withdrawal_fee_bank_pesewas"`
	WithdrawalFeeWaiverPesewas int64 `json:"withdrawal_fee_waiver_pesewas"`
}

func (r upsertFeeRuleRequest) validate() error {
	if r.CollectionFeeBps < 0 || r.MarginBps < 0 {
		return errors.New("collection_fee_bps and margin_bps must not be negative")
	}
	// At or above 100% the customer-borne gross-up in computeInvoiceAmounts
	// has no solution — the customer would owe infinity.
	if r.CollectionFeeBps+r.MarginBps >= 10000 {
		return errors.New("collection_fee_bps + margin_bps must be under 10000 bps (100%)")
	}
	if r.MarginFloorPesewas < 0 || r.MarginCapPesewas < 0 {
		return errors.New("margin_floor_pesewas and margin_cap_pesewas must not be negative")
	}
	if r.MarginCapPesewas > 0 && r.MarginCapPesewas < r.MarginFloorPesewas {
		return errors.New("margin_cap_pesewas must not be below margin_floor_pesewas")
	}
	if r.WithdrawalFeeMomoPesewas < 0 || r.WithdrawalFeeBankPesewas < 0 || r.WithdrawalFeeWaiverPesewas < 0 {
		return errors.New("withdrawal fees must not be negative")
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
		CollectionFeeBps:           req.CollectionFeeBps,
		MarginFloorPesewas:         req.MarginFloorPesewas,
		MarginCapPesewas:           req.MarginCapPesewas,
		WithdrawalFeeMomoPesewas:   req.WithdrawalFeeMomoPesewas,
		WithdrawalFeeBankPesewas:   req.WithdrawalFeeBankPesewas,
		WithdrawalFeeWaiverPesewas: req.WithdrawalFeeWaiverPesewas,
		MarginBps:                  req.MarginBps,
		AllocationType:             req.AllocationType,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to upsert global fee rule"})
	}

	var beforeJSON []byte
	if beforeErr == nil {
		beforeJSON, _ = json.Marshal(fiber.Map{
			"collection_fee_bps": before.CollectionFeeBps, "margin_bps": before.MarginBps,
			"commission_bps": before.CommissionBps, "allocation_type": before.AllocationType,
			"margin_floor_pesewas": before.MarginFloorPesewas, "margin_cap_pesewas": before.MarginCapPesewas,
			"withdrawal_fee_momo_pesewas":   before.WithdrawalFeeMomoPesewas,
			"withdrawal_fee_bank_pesewas":   before.WithdrawalFeeBankPesewas,
			"withdrawal_fee_waiver_pesewas": before.WithdrawalFeeWaiverPesewas,
		})
	}
	after, _ := json.Marshal(fiber.Map{
		"collection_fee_bps": rule.CollectionFeeBps, "margin_bps": rule.MarginBps,
		"commission_bps": rule.CommissionBps, "allocation_type": rule.AllocationType,
		"margin_floor_pesewas": rule.MarginFloorPesewas, "margin_cap_pesewas": rule.MarginCapPesewas,
		"withdrawal_fee_momo_pesewas":   rule.WithdrawalFeeMomoPesewas,
		"withdrawal_fee_bank_pesewas":   rule.WithdrawalFeeBankPesewas,
		"withdrawal_fee_waiver_pesewas": rule.WithdrawalFeeWaiverPesewas,
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
		MerchantID:                 merchantID,
		CollectionFeeBps:           req.CollectionFeeBps,
		MarginFloorPesewas:         req.MarginFloorPesewas,
		MarginCapPesewas:           req.MarginCapPesewas,
		WithdrawalFeeMomoPesewas:   req.WithdrawalFeeMomoPesewas,
		WithdrawalFeeBankPesewas:   req.WithdrawalFeeBankPesewas,
		WithdrawalFeeWaiverPesewas: req.WithdrawalFeeWaiverPesewas,
		MarginBps:                  req.MarginBps,
		AllocationType:             req.AllocationType,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to upsert merchant fee rule"})
	}

	var beforeJSON []byte
	if beforeErr == nil {
		beforeJSON, _ = json.Marshal(fiber.Map{
			"collection_fee_bps": before.CollectionFeeBps, "margin_bps": before.MarginBps,
			"commission_bps": before.CommissionBps, "allocation_type": before.AllocationType,
			"margin_floor_pesewas": before.MarginFloorPesewas, "margin_cap_pesewas": before.MarginCapPesewas,
			"withdrawal_fee_momo_pesewas":   before.WithdrawalFeeMomoPesewas,
			"withdrawal_fee_bank_pesewas":   before.WithdrawalFeeBankPesewas,
			"withdrawal_fee_waiver_pesewas": before.WithdrawalFeeWaiverPesewas,
		})
	}
	after, _ := json.Marshal(fiber.Map{
		"collection_fee_bps": rule.CollectionFeeBps, "margin_bps": rule.MarginBps,
		"commission_bps": rule.CommissionBps, "allocation_type": rule.AllocationType,
		"margin_floor_pesewas": rule.MarginFloorPesewas, "margin_cap_pesewas": rule.MarginCapPesewas,
		"withdrawal_fee_momo_pesewas":   rule.WithdrawalFeeMomoPesewas,
		"withdrawal_fee_bank_pesewas":   rule.WithdrawalFeeBankPesewas,
		"withdrawal_fee_waiver_pesewas": rule.WithdrawalFeeWaiverPesewas,
	})
	if err := writeAdminAuditLog(c, h, "fee_rule.merchant_override", "merchant", merchantID, beforeJSON, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(rule)
}

// merchantSetRateCapBps hard-caps what a verified registered merchant can
// set their own commission rate to (Section 4.8 / fee-architecture brief's
// "Merchant-set rates"). 5% is a deliberate, conservative application-code
// ceiling, not a figure derived from card-scheme rules or BoG guidance —
// the risk it guards against is a merchant setting an outsized "service
// charge" that becomes a surcharging problem on OrderxPay's own Paystack
// merchant-of-record account, not theirs, since every merchant here is a
// sub-merchant invisible to Visa/Mastercard's own rules.
const merchantSetRateCapBps = 500

type setMerchantOwnFeeRuleRequest struct {
	// CommissionBps is the merchant's requested TOTAL blended rate — what
	// GetMerchantFeeRuleOrGlobal already shows them as commission_bps.
	// They're choosing an outcome ("customers see 3.5%"), not tuning
	// collection_fee_bps/margin_bps as separate levers; SetMerchantOwnFeeRule
	// derives the margin from whichever of those two this request implies.
	CommissionBps int32 `json:"commission_bps"`
}

// deriveMerchantSetMarginBps is SetMerchantOwnFeeRule's validation, pulled
// out as a pure function for testability (same pattern as
// proratedCommissionPesewas in payments.go and withdrawalFee in
// settlements.go). Rejects a requested total commission_bps above the hard
// cap or below the real PSP pass-through cost — the merchant is choosing a
// margin on top of that cost, never the cost itself — and otherwise
// returns the margin that total implies.
func deriveMerchantSetMarginBps(requestedCommissionBps, collectionFeeBps int32) (int32, error) {
	if requestedCommissionBps < 0 {
		return 0, errors.New("commission_bps must not be negative")
	}
	if requestedCommissionBps > merchantSetRateCapBps {
		return 0, fmt.Errorf("commission_bps cannot exceed %d (%.2f%%)", merchantSetRateCapBps, float64(merchantSetRateCapBps)/100)
	}
	if requestedCommissionBps < collectionFeeBps {
		return 0, fmt.Errorf(
			"commission_bps cannot go below the %d bps (%.2f%%) collection fee, which is the payment provider's real cost, not OrderxPay's margin",
			collectionFeeBps, float64(collectionFeeBps)/100)
	}
	return requestedCommissionBps - collectionFeeBps, nil
}

// SetMerchantOwnFeeRule lets a verified registered merchant set their own
// commission rate, immediately and without a Back Office review step — the
// merchantSetRateCapBps ceiling above is the safety control, not a human in
// the loop. Gated on business_type == "registered" rather than kyc_tier
// directly: Tier 2 always implies registered (ApproveMerchantKYC sets both
// together), but a Back Office kyc_tier override (UpdateMerchantKYCTier)
// deliberately does NOT touch business_type, and a tier bumped that way
// without ever having supplied registration evidence shouldn't unlock this.
//
// collection_fee_bps, allocation_type, the margin floor/cap, and the
// withdrawal fees are deliberately NOT settable here — those are either
// real PSP-cost pass-through or operational mechanics, not "the merchant's
// rate." They're carried forward unchanged from whatever fee rule already
// applies to this merchant (their own prior override, or the platform
// default), so only the requested commission_bps actually moves.
func (h *Handler) SetMerchantOwnFeeRule(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	merchant, err := h.Queries.GetMerchant(c.Context(), merchantID)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}
	if !merchant.BusinessType.Valid || merchant.BusinessType.String != "registered" {
		return fiber.NewError(fiber.StatusForbidden, "setting your own rate is available to verified registered businesses only")
	}

	var req setMerchantOwnFeeRuleRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	current, err := h.Queries.GetFeeRuleByMerchant(c.Context(), merchantID)
	if errors.Is(err, pgx.ErrNoRows) {
		current, err = h.Queries.GetGlobalFeeRule(c.Context())
	}
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load current fee rule"})
	}

	marginBps, err := deriveMerchantSetMarginBps(req.CommissionBps, current.CollectionFeeBps)
	if err != nil {
		return badRequest(c, err.Error())
	}

	rule, err := h.Queries.UpsertMerchantFeeRule(c.Context(), db.UpsertMerchantFeeRuleParams{
		MerchantID:                 merchantID,
		CollectionFeeBps:           current.CollectionFeeBps,
		MarginBps:                  marginBps,
		AllocationType:             current.AllocationType,
		MarginFloorPesewas:         current.MarginFloorPesewas,
		MarginCapPesewas:           current.MarginCapPesewas,
		WithdrawalFeeMomoPesewas:   current.WithdrawalFeeMomoPesewas,
		WithdrawalFeeBankPesewas:   current.WithdrawalFeeBankPesewas,
		WithdrawalFeeWaiverPesewas: current.WithdrawalFeeWaiverPesewas,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to set your rate"})
	}

	// Unlike UpdateMerchantFeeSettings/UpdateMerchantWhatsAppSettings
	// (ordinary merchant self-service, not audit-logged), a self-set
	// pricing rate is consequential enough to want a real trail — and
	// writeActorAuditLog attributes it correctly to the merchant/staff
	// actor who actually made the change, not to a Back Office user.
	before, _ := json.Marshal(fiber.Map{"commission_bps": current.CommissionBps})
	after, _ := json.Marshal(fiber.Map{"commission_bps": rule.CommissionBps, "margin_bps": rule.MarginBps})
	if err := writeActorAuditLog(c, h, "fee_rule.merchant_self_set", "merchant", merchantID, before, after); err != nil {
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
