package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// Section 4.1/7.1: the volume caps that make a KYC tier mean something.
//
// Before the business-type fork, kyc_tier was a label — set on approval and
// read by nothing. These are the checks that turn it into a control, and
// they run at both ends of the money path: when a merchant raises an
// invoice (so they find out while they can still change it) and again when
// a customer starts a payment (the backstop that actually holds, since an
// invoice can be raised before a limit is reached and paid after).
//
// IMPORTANT: every limit ships unset, meaning no cap. Tier thresholds for
// this kind of account are set by Bank of Ghana guidance and are not
// invented here — the mechanism is complete and does nothing until real,
// verified figures are entered in Back Office. See the 000029 migration.

// tierLimit is db.KycTierLimit with the nullable columns collapsed: 0 means
// "no cap", which is also what an unset column reads as. Nothing else in
// the codebase should have to reason about pgtype.Int8 to answer "is this
// merchant over their limit".
type tierLimit struct {
	PerTransactionPesewas int64
	DailyPesewas          int64
	CumulativePesewas     int64
}

func tierLimitFrom(row db.KycTierLimit) tierLimit {
	return tierLimit{
		PerTransactionPesewas: int64OrZero(row.PerTransactionPesewas),
		DailyPesewas:          int64OrZero(row.DailyPesewas),
		CumulativePesewas:     int64OrZero(row.CumulativePesewas),
	}
}

func int64OrZero(v pgtype.Int8) int64 {
	if !v.Valid {
		return 0
	}
	return v.Int64
}

// volumeUsage is what the merchant has already collected, from
// GetMerchantVolume. Both figures are gross of refunds by design.
type volumeUsage struct {
	TodayPesewas      int64
	CumulativePesewas int64
}

// upgradePrompt is the second half of every limit message: a limit the
// merchant can do nothing about is a dead end, so each tier names the step
// that raises it. Tier 2 is the top of the ladder, so it points at support.
func upgradePrompt(tier int16) string {
	switch tier {
	case 0:
		return "Verify your Ghana Card to raise it."
	case 1:
		return "Register your business and verify to raise it."
	default:
		return "Contact support to review your limits."
	}
}

// checkTierLimit reports whether amountPesewas may proceed, returning a
// merchant-readable explanation when it may not and "" when it may.
//
// The daily and cumulative checks test usage *plus* the new amount, not
// usage alone: a merchant ₵1 under their daily cap cannot take a ₵500
// payment. Any cap left at 0 is skipped entirely.
func checkTierLimit(tier int16, l tierLimit, u volumeUsage, amountPesewas int64) string {
	if amountPesewas <= 0 {
		return ""
	}
	if l.PerTransactionPesewas > 0 && amountPesewas > l.PerTransactionPesewas {
		return fmt.Sprintf(
			"%s is over the %s single-payment limit for Tier %d. %s",
			formatPesewas(amountPesewas), formatPesewas(l.PerTransactionPesewas), tier, upgradePrompt(tier),
		)
	}
	if l.DailyPesewas > 0 && u.TodayPesewas+amountPesewas > l.DailyPesewas {
		return fmt.Sprintf(
			"this would take today's collections past the %s daily limit for Tier %d — %s of today's limit is left. %s",
			formatPesewas(l.DailyPesewas), tier, formatPesewas(remaining(l.DailyPesewas, u.TodayPesewas)), upgradePrompt(tier),
		)
	}
	if l.CumulativePesewas > 0 && u.CumulativePesewas+amountPesewas > l.CumulativePesewas {
		return fmt.Sprintf(
			"this would take total collections past the %s lifetime limit for Tier %d — %s is left. %s",
			formatPesewas(l.CumulativePesewas), tier, formatPesewas(remaining(l.CumulativePesewas, u.CumulativePesewas)), upgradePrompt(tier),
		)
	}
	return ""
}

// remaining never reports a negative headroom: a merchant already past a
// cap has none left, and "-₵40.00 is left" is not a sentence.
func remaining(limit, used int64) int64 {
	if used >= limit {
		return 0
	}
	return limit - used
}

// enforceTierLimit loads the merchant's tier, its limits and their current
// usage, and applies checkTierLimit. A missing limits row is treated as
// uncapped rather than as an error — the row set is seeded by migration,
// and a limits lookup failing is not a reason to stop a merchant trading.
func (h *Handler) enforceTierLimit(ctx context.Context, merchantID pgtype.UUID, amountPesewas int64) (string, error) {
	merchant, err := h.Queries.GetMerchant(ctx, merchantID)
	if err != nil {
		return "", err
	}
	return h.enforceTierLimitFor(ctx, merchantID, merchant.KycTier, amountPesewas)
}

// enforceTierLimitFor is enforceTierLimit for a caller that already holds
// the merchant row — createInvoiceCore loads it to check suspension and to
// read the fee allocation, and reloading it here would be a wasted query on
// the hot path of every invoice.
func (h *Handler) enforceTierLimitFor(ctx context.Context, merchantID pgtype.UUID, tier int16, amountPesewas int64) (string, error) {
	limit, err := h.tierLimitFor(ctx, tier)
	if err != nil {
		return "", err
	}
	if limit == (tierLimit{}) {
		// Nothing capped at this tier — skip the volume aggregate entirely.
		return "", nil
	}
	vol, err := h.Queries.GetMerchantVolume(ctx, merchantID)
	if err != nil {
		return "", err
	}
	usage := volumeUsage{TodayPesewas: vol.TodayPesewas, CumulativePesewas: vol.CumulativePesewas}
	return checkTierLimit(tier, limit, usage, amountPesewas), nil
}

func (h *Handler) tierLimitFor(ctx context.Context, tier int16) (tierLimit, error) {
	row, err := h.Queries.GetKYCTierLimit(ctx, tier)
	if errors.Is(err, pgx.ErrNoRows) {
		return tierLimit{}, nil
	} else if err != nil {
		return tierLimit{}, err
	}
	return tierLimitFrom(row), nil
}

// GetMerchantLimits backs the app's limits card (Section 4.1): what the
// merchant's tier allows, what they've used, and what's left. Returned even
// when everything is uncapped so the app can say so plainly rather than
// showing an empty widget.
func (h *Handler) GetMerchantLimits(c *fiber.Ctx) error {
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
	limit, err := h.tierLimitFor(c.Context(), merchant.KycTier)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load tier limits"})
	}
	vol, err := h.Queries.GetMerchantVolume(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load collected volume"})
	}

	return c.JSON(fiber.Map{
		"kyc_tier":      merchant.KycTier,
		"business_type": merchant.BusinessType,
		// 0 means uncapped on every limit field, matching tierLimit.
		"per_transaction_limit_pesewas": limit.PerTransactionPesewas,
		"daily_limit_pesewas":           limit.DailyPesewas,
		"cumulative_limit_pesewas":      limit.CumulativePesewas,
		"today_pesewas":                 vol.TodayPesewas,
		"cumulative_pesewas":            vol.CumulativePesewas,
		"daily_remaining_pesewas":       remaining(limit.DailyPesewas, vol.TodayPesewas),
		"cumulative_remaining_pesewas":  remaining(limit.CumulativePesewas, vol.CumulativePesewas),
	})
}

// ListKYCTierLimits and UpdateKYCTierLimit back the Back Office limits
// page. Both sit behind merchants.kyc_review — the same permission that
// gates approving a tier gates deciding what a tier is worth.
func (h *Handler) ListKYCTierLimits(c *fiber.Ctx) error {
	rows, err := h.Queries.ListKYCTierLimits(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list tier limits"})
	}
	return c.JSON(rows)
}

type updateTierLimitRequest struct {
	// Pointers, not values: null means "no cap" and 0 is rejected. Without
	// the distinction, clearing a limit and setting it to zero would be the
	// same request, and one of those must not silently block all trading.
	PerTransactionPesewas *int64 `json:"per_transaction_pesewas"`
	DailyPesewas          *int64 `json:"daily_pesewas"`
	CumulativePesewas     *int64 `json:"cumulative_pesewas"`
}

func (r updateTierLimitRequest) validate() error {
	for label, v := range map[string]*int64{
		"per_transaction_pesewas": r.PerTransactionPesewas,
		"daily_pesewas":           r.DailyPesewas,
		"cumulative_pesewas":      r.CumulativePesewas,
	} {
		if v != nil && *v <= 0 {
			return fmt.Errorf("%s must be greater than zero, or null for no limit", label)
		}
	}
	if r.PerTransactionPesewas != nil && r.DailyPesewas != nil && *r.PerTransactionPesewas > *r.DailyPesewas {
		return errors.New("per_transaction_pesewas cannot exceed daily_pesewas — the single-payment limit would be unreachable")
	}
	if r.DailyPesewas != nil && r.CumulativePesewas != nil && *r.DailyPesewas > *r.CumulativePesewas {
		return errors.New("daily_pesewas cannot exceed cumulative_pesewas — the daily limit would be unreachable")
	}
	return nil
}

func (h *Handler) UpdateKYCTierLimit(c *fiber.Ctx) error {
	tier := c.QueryInt("tier", -1)
	if v, err := c.ParamsInt("tier"); err == nil {
		tier = v
	}
	if tier < 0 || tier > 2 {
		return badRequest(c, "tier must be 0, 1 or 2")
	}

	var req updateTierLimitRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if err := req.validate(); err != nil {
		return badRequest(c, err.Error())
	}

	before, err := h.Queries.GetKYCTierLimit(c.Context(), int16(tier))
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load tier limit"})
	}

	updated, err := h.Queries.UpdateKYCTierLimit(c.Context(), db.UpdateKYCTierLimitParams{
		Tier:                  int16(tier),
		PerTransactionPesewas: nullableInt8(req.PerTransactionPesewas),
		DailyPesewas:          nullableInt8(req.DailyPesewas),
		CumulativePesewas:     nullableInt8(req.CumulativePesewas),
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update tier limit"})
	}

	// Section 7.9: changing what a tier is allowed to move is a sensitive
	// action, in the same class as approving the tier itself.
	beforeJSON, _ := json.Marshal(before)
	afterJSON, _ := json.Marshal(updated)
	if err := writeAdminAuditLog(c, h, "kyc.tier_limit_change", "kyc_tier_limit", pgtype.UUID{}, beforeJSON, afterJSON); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(updated)
}

func nullableInt8(v *int64) pgtype.Int8 {
	if v == nil {
		return pgtype.Int8{}
	}
	return pgtype.Int8{Int64: *v, Valid: true}
}
