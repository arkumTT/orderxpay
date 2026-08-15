package handlers

import (
	"encoding/json"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// auditLogEntryView re-types before_state/after_state from []byte to
// json.RawMessage. sqlc scans jsonb columns as []byte, and Go's
// encoding/json base64-encodes a bare []byte field rather than inlining it
// as JSON — without this conversion the Back Office would render
// before/after state as opaque base64 strings instead of the actual diff.
type auditLogEntryView struct {
	ID           pgtype.UUID        `json:"id"`
	ActorID      pgtype.UUID        `json:"actor_id"`
	ActorType    string             `json:"actor_type"`
	Action       string             `json:"action"`
	TargetEntity string             `json:"target_entity"`
	TargetID     pgtype.UUID        `json:"target_id"`
	BeforeState  json.RawMessage    `json:"before_state"`
	AfterState   json.RawMessage    `json:"after_state"`
	CreatedAt    pgtype.Timestamptz `json:"created_at"`
	ActorName    *string            `json:"actor_name,omitempty"`
	ActorEmail   *string            `json:"actor_email,omitempty"`
}

// ListAuditLogForTarget backs the "audit trail" panel embedded on a specific
// record's detail view (e.g. one merchant's history). There is deliberately
// no public create endpoint: audit entries are written server-side by the
// handlers that perform the sensitive action itself, not submitted directly
// by a client.
func (h *Handler) ListAuditLogForTarget(c *fiber.Ctx) error {
	targetEntity := c.Query("target_entity")
	targetID, err := parseUUIDParam(c, "targetId")
	if targetEntity == "" || err != nil {
		return badRequest(c, "target_entity query param and a valid :targetId are required")
	}

	rows, err := h.Queries.ListAuditLogEntriesByTarget(c.Context(), db.ListAuditLogEntriesByTargetParams{
		TargetEntity: targetEntity,
		TargetID:     targetID,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list audit log"})
	}

	entries := make([]auditLogEntryView, len(rows))
	for i, r := range rows {
		entries[i] = auditLogEntryView{
			ID:           r.ID,
			ActorID:      r.ActorID,
			ActorType:    r.ActorType,
			Action:       r.Action,
			TargetEntity: r.TargetEntity,
			TargetID:     r.TargetID,
			BeforeState:  json.RawMessage(r.BeforeState),
			AfterState:   json.RawMessage(r.AfterState),
			CreatedAt:    r.CreatedAt,
		}
	}
	return c.JSON(entries)
}

// ListAuditLogAdmin is the Section 7.9 compliance log page — every sensitive
// back-office action across every entity, filterable and defaulting to the
// trailing 30 days so the page stays fast as the table grows.
func (h *Handler) ListAuditLogAdmin(c *fiber.Ctx) error {
	periodStart, periodEnd, err := parseReportPeriod(c)
	if err != nil {
		return badRequest(c, err.Error())
	}

	limit := int32(c.QueryInt("limit", 200))
	offset := int32(c.QueryInt("offset", 0))

	rows, err := h.Queries.ListAuditLogEntriesAdmin(c.Context(), db.ListAuditLogEntriesAdminParams{
		TargetEntity:    c.Query("target_entity"),
		ActionFilter:    c.Query("action"),
		ActorTypeFilter: c.Query("actor_type"),
		PeriodStart:     pgtype.Timestamptz{Time: periodStart, Valid: true},
		PeriodEnd:       pgtype.Timestamptz{Time: periodEnd, Valid: true},
		RowLimit:        limit,
		RowOffset:       offset,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list audit log"})
	}

	targetEntities, err := h.Queries.ListAuditLogTargetEntities(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list audit log target entities"})
	}

	entries := make([]auditLogEntryView, len(rows))
	for i, r := range rows {
		entries[i] = auditLogEntryView{
			ID:           r.ID,
			ActorID:      r.ActorID,
			ActorType:    r.ActorType,
			Action:       r.Action,
			TargetEntity: r.TargetEntity,
			TargetID:     r.TargetID,
			BeforeState:  json.RawMessage(r.BeforeState),
			AfterState:   json.RawMessage(r.AfterState),
			CreatedAt:    r.CreatedAt,
			ActorName:    pgTextPtr(r.ActorName),
			ActorEmail:   pgTextPtr(r.ActorEmail),
		}
	}

	return c.JSON(fiber.Map{
		"period_start":    periodStart.Format(dateLayout),
		"period_end":      periodEnd.AddDate(0, 0, -1).Format(dateLayout),
		"entries":         entries,
		"target_entities": targetEntities,
	})
}

func pgTextPtr(t pgtype.Text) *string {
	if !t.Valid {
		return nil
	}
	return &t.String
}
