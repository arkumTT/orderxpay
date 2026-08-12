package handlers

import (
	"github.com/gofiber/fiber/v2"
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

// CreateSettlement (batch reconciliation run) is not yet implemented: it
// needs to aggregate gross collections, PSP fees, and commission from
// payments/fee_rules for a period (Section 7.2), which is business logic to
// design deliberately rather than scaffold ad hoc.
func (h *Handler) CreateSettlement(c *fiber.Ctx) error {
	return notImplemented(c, "settlement reconciliation not yet implemented — see Section 7.2 of the architecture doc")
}
