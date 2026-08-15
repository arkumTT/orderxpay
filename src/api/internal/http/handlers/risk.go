package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// RunRiskScan is the on-demand equivalent of the continuous monitoring
// Section 7.6 describes — there's no background job scheduler in this
// stack, so a reviewer triggers a scan rather than rules running on a
// timer. Both rules upsert into risk_flags; CreateRiskFlag silently skips
// a finding that's already an open flag (risk_flags_dedupe_open), so
// running the scan repeatedly is always safe.
func (h *Handler) RunRiskScan(c *fiber.Ctx) error {
	dupCards, err := h.Queries.FindDuplicateGhanaCardFlags(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to scan for duplicate Ghana Cards"})
	}
	for _, row := range dupCards {
		details := fmt.Sprintf("Ghana Card %s also used by: %s", row.GhanaCardNumber, row.OtherMerchants)
		if err := h.Queries.CreateRiskFlag(c.Context(), db.CreateRiskFlagParams{
			MerchantID: row.MerchantID,
			FlagType:   "duplicate_ghana_card",
			DedupeKey:  row.GhanaCardNumber,
			Details:    details,
		}); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to record duplicate-card flag"})
		}
	}

	spikes, err := h.Queries.FindVelocitySpikes(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to scan for velocity spikes"})
	}
	today := time.Now().UTC().Format("2006-01-02")
	for _, row := range spikes {
		details := fmt.Sprintf(
			"%d invoices worth %s in the last 24h vs. a %.1f/day, %s/day trailing average",
			row.TodayCount, formatGHS(row.TodayValuePesewas), row.BaselineAvgCount, formatGHS(int64(row.BaselineAvgValuePesewas)),
		)
		if err := h.Queries.CreateRiskFlag(c.Context(), db.CreateRiskFlagParams{
			MerchantID: row.MerchantID,
			FlagType:   "velocity_spike",
			DedupeKey:  "velocity:" + today,
			Details:    details,
		}); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to record velocity flag"})
		}
	}

	return c.JSON(fiber.Map{
		"duplicate_ghana_card_candidates": len(dupCards),
		"velocity_spike_candidates":       len(spikes),
	})
}

func formatGHS(pesewas int64) string {
	return fmt.Sprintf("GHS %.2f", float64(pesewas)/100)
}

func (h *Handler) ListRiskFlagsAdmin(c *fiber.Ctx) error {
	limit := int32(c.QueryInt("limit", 100))
	offset := int32(c.QueryInt("offset", 0))

	flags, err := h.Queries.ListRiskFlagsAdmin(c.Context(), db.ListRiskFlagsAdminParams{
		StatusFilter: c.Query("status"),
		RowLimit:     limit,
		RowOffset:    offset,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list risk flags"})
	}
	return c.JSON(flags)
}

type resolveRiskFlagRequest struct {
	Status          string `json:"status"`
	ResolutionNotes string `json:"resolution_notes"`
}

// ResolveRiskFlag dismisses (false positive, no notes required) or
// escalates (feeds the AML/KYC obligations in Section 2.2 — notes required
// so there's a record of what happens next) an open flag. Always audited.
func (h *Handler) ResolveRiskFlag(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid risk flag id")
	}

	var req resolveRiskFlagRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Status != "dismissed" && req.Status != "escalated" {
		return badRequest(c, "status must be dismissed or escalated")
	}
	if req.Status == "escalated" && req.ResolutionNotes == "" {
		return badRequest(c, "resolution_notes is required when escalating")
	}

	flag, err := h.Queries.GetRiskFlag(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load risk flag"})
	}
	if flag.Status != "open" {
		return badRequest(c, "flag has already been resolved")
	}

	payload, ok := actorPayload(c)
	if !ok {
		return fiber.NewError(fiber.StatusUnauthorized, "missing auth payload")
	}

	updated, err := h.Queries.ResolveRiskFlag(c.Context(), db.ResolveRiskFlagParams{
		ID:              id,
		Status:          req.Status,
		ResolutionNotes: textOrNull(req.ResolutionNotes),
		ReviewedBy:      toPgUUID(payload.ActorID),
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update risk flag"})
	}

	before, _ := json.Marshal(fiber.Map{"status": flag.Status})
	after, _ := json.Marshal(fiber.Map{"status": updated.Status, "resolution_notes": req.ResolutionNotes})
	if err := writeAdminAuditLog(c, h, "risk_flag.resolve", "risk_flag", id, before, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(updated)
}
