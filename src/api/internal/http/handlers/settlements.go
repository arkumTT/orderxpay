package handlers

import (
	"encoding/json"
	"errors"
	"log"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/orderxpay/api/internal/auth"
	db "github.com/orderxpay/api/internal/db/sqlc"
	"github.com/orderxpay/api/internal/middleware"
)

func (h *Handler) ListSettlements(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	settlements, err := h.Queries.ListSettlementsByMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list settlements"})
	}
	return c.JSON(settlements)
}

// ListAllSettlements backs the Back Office 7.2 landing page — a
// cross-merchant view (unlike ListSettlements, which is scoped to one
// merchant's detail page).
func (h *Handler) ListAllSettlements(c *fiber.Ctx) error {
	limit := int32(c.QueryInt("limit", 50))
	offset := int32(c.QueryInt("offset", 0))

	settlements, err := h.Queries.ListSettlementsAdmin(c.Context(), db.ListSettlementsAdminParams{
		StatusFilter: c.Query("status"),
		RowLimit:     limit,
		RowOffset:    offset,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list settlements"})
	}
	return c.JSON(settlements)
}

const dateLayout = "2006-01-02"

type generateSettlementRequest struct {
	MerchantID  string `json:"merchant_id"`
	PeriodStart string `json:"period_start"` // "2026-08-01"
	PeriodEnd   string `json:"period_end"`   // inclusive calendar date, e.g. "2026-08-14"
}

// GenerateSettlement is the Section 7.2 batch-run: aggregates every
// not-yet-settled successful payment for a merchant within a calendar-date
// period into one payout record, and atomically marks those payments as
// claimed by it so a second run (accidental or scheduled) can never double
// -pay them. This is the "scheduled batch runs" half of 7.2's payout batch
// management — see UpdateSettlementStatus for the manual mark-paid step
// that actually executing the payout (still off-platform for now, per the
// Phase 1 roadmap's "manual payout") reduces to.
func (h *Handler) GenerateSettlement(c *fiber.Ctx) error {
	var req generateSettlementRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	merchantID, err := parseUUID(req.MerchantID)
	if err != nil {
		return badRequest(c, "invalid merchant_id")
	}
	periodStart, err := time.Parse(dateLayout, req.PeriodStart)
	if err != nil {
		return badRequest(c, "period_start must be YYYY-MM-DD")
	}
	periodEndDate, err := time.Parse(dateLayout, req.PeriodEnd)
	if err != nil {
		return badRequest(c, "period_end must be YYYY-MM-DD")
	}
	if periodEndDate.Before(periodStart) {
		return badRequest(c, "period_end must be on or after period_start")
	}
	// period_end is inclusive as given by the caller; the exclusive
	// upper bound for the timestamptz range is the start of the next day.
	rangeEnd := periodEndDate.AddDate(0, 0, 1)

	if _, err := h.Queries.GetMerchant(c.Context(), merchantID); errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}

	tx, err := h.Pool.Begin(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to start transaction"})
	}
	defer tx.Rollback(c.Context())
	qtx := h.Queries.WithTx(tx)

	aggParams := db.ComputeSettlementAggregateParams{
		MerchantID:  merchantID,
		PeriodStart: pgtype.Timestamptz{Time: periodStart, Valid: true},
		PeriodEnd:   pgtype.Timestamptz{Time: rangeEnd, Valid: true},
	}
	agg, err := qtx.ComputeSettlementAggregate(c.Context(), aggParams)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to compute settlement aggregate"})
	}
	if agg.PaymentCount == 0 {
		return badRequest(c, "no unsettled successful payments for this merchant in the given period")
	}

	settlement, err := qtx.CreateSettlement(c.Context(), db.CreateSettlementParams{
		MerchantID:              merchantID,
		PeriodStart:             pgtype.Date{Time: periodStart, Valid: true},
		PeriodEnd:               pgtype.Date{Time: periodEndDate, Valid: true},
		GrossCollectionsPesewas: agg.GrossCollectionsPesewas,
		PspFeesPesewas:          agg.PspFeesPesewas,
		CommissionPesewas:       agg.CommissionPesewas,
		NetPayoutPesewas:        agg.NetPayoutPesewas,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create settlement"})
	}

	if err := qtx.MarkPaymentsSettled(c.Context(), db.MarkPaymentsSettledParams{
		SettlementID: settlement.ID,
		MerchantID:   merchantID,
		PeriodStart:  aggParams.PeriodStart,
		PeriodEnd:    aggParams.PeriodEnd,
	}); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to mark payments settled"})
	}

	after, _ := json.Marshal(fiber.Map{
		"status":                    settlement.Status,
		"gross_collections_pesewas": settlement.GrossCollectionsPesewas,
		"psp_fees_pesewas":          settlement.PspFeesPesewas,
		"commission_pesewas":        settlement.CommissionPesewas,
		"net_payout_pesewas":        settlement.NetPayoutPesewas,
		"payment_count":             agg.PaymentCount,
		"period_start":              req.PeriodStart,
		"period_end":                req.PeriodEnd,
	})
	if err := writeAdminAuditLog(c, h, "settlement.generate", "settlement", settlement.ID, nil, after); err != nil {
		log.Printf("settlements: failed to write audit log for generate: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	if err := tx.Commit(c.Context()); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to commit settlement"})
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{
		"settlement":    settlement,
		"payment_count": agg.PaymentCount,
	})
}

// settlementStatusTransitions enumerates the only moves UpdateSettlementStatus
// accepts — a settlement can advance from pending, or fail out of either
// non-terminal state, but never un-pay or un-fail.
var settlementStatusTransitions = map[string][]string{
	"pending":    {"processing", "paid", "failed"},
	"processing": {"paid", "failed"},
}

type updateSettlementStatusRequest struct {
	Status string `json:"status"`
}

// UpdateSettlementStatus is the manual half of Section 7.2's payout batch
// management: back-office staff mark a settlement paid once they've
// actually sent the money (Phase 1 payouts are manual — see the roadmap),
// or failed if it needs to move to the exception queue. Always audited
// (Section 7.9 explicitly calls out manual payout as a sensitive action).
func (h *Handler) UpdateSettlementStatus(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid settlement id")
	}

	var req updateSettlementStatusRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	settlement, err := h.Queries.GetSettlement(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load settlement"})
	}

	allowed := settlementStatusTransitions[settlement.Status]
	valid := false
	for _, s := range allowed {
		if s == req.Status {
			valid = true
			break
		}
	}
	if !valid {
		return badRequest(c, "cannot move settlement from "+settlement.Status+" to "+req.Status)
	}

	updated, err := h.Queries.SetSettlementStatus(c.Context(), db.SetSettlementStatusParams{ID: id, Status: req.Status})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update settlement status"})
	}

	before, _ := json.Marshal(fiber.Map{"status": settlement.Status})
	after, _ := json.Marshal(fiber.Map{"status": updated.Status})
	if err := writeAdminAuditLog(c, h, "settlement.status_change", "settlement", id, before, after); err != nil {
		log.Printf("settlements: failed to write audit log for status change: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(updated)
}

// writeAdminAuditLog records a Back Office action against the authenticated
// admin user (Section 7.9) — separate from the "system" actor used for
// PSP-webhook-driven changes in payments.go.
func writeAdminAuditLog(c *fiber.Ctx, h *Handler, action, targetEntity string, targetID pgtype.UUID, before, after []byte) error {
	payload, ok := c.Locals(middleware.AuthPayloadKey).(*auth.Payload)
	if !ok {
		return fiber.NewError(fiber.StatusUnauthorized, "missing auth payload")
	}
	_, err := h.Queries.CreateAuditLogEntry(c.Context(), db.CreateAuditLogEntryParams{
		ActorID:      toPgUUID(payload.ActorID),
		ActorType:    string(auth.ActorUser),
		Action:       action,
		TargetEntity: targetEntity,
		TargetID:     targetID,
		BeforeState:  before,
		AfterState:   after,
	})
	return err
}
