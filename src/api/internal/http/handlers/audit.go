package handlers

import (
	"github.com/gofiber/fiber/v2"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// ListAuditLogForTarget backs the Back Office audit trail view (Section 7.9).
// There is deliberately no public create endpoint: audit entries are written
// server-side by the handlers that perform the sensitive action itself, not
// submitted directly by a client.
func (h *Handler) ListAuditLogForTarget(c *fiber.Ctx) error {
	targetEntity := c.Query("target_entity")
	targetID, err := parseUUIDParam(c, "targetId")
	if targetEntity == "" || err != nil {
		return badRequest(c, "target_entity query param and a valid :targetId are required")
	}

	entries, err := h.Queries.ListAuditLogEntriesByTarget(c.Context(), db.ListAuditLogEntriesByTargetParams{
		TargetEntity: targetEntity,
		TargetID:     targetID,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list audit log"})
	}
	return c.JSON(entries)
}
