package handlers

import (
	"fmt"

	"github.com/gofiber/fiber/v2"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// formatPesewas renders integer pesewas as "GH₵12.34" without ever touching
// a float, matching this codebase's money-as-integer discipline.
func formatPesewas(pesewas int64) string {
	sign := ""
	if pesewas < 0 {
		sign = "-"
		pesewas = -pesewas
	}
	return fmt.Sprintf("%sGH₵%d.%02d", sign, pesewas/100, pesewas%100)
}

// ListNotifications is the merchant app's in-app alert feed (Section 4.10).
// Real and persisted — created at the four trigger points documented on
// createNotification below. Push/SMS/WhatsApp delivery isn't built (no push
// provider; SMS/WhatsApp both depend on integrations this platform doesn't
// have yet — Section 7.3), so this is in-app only.
func (h *Handler) ListNotifications(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	limit := int32(c.QueryInt("limit", 50))
	offset := int32(c.QueryInt("offset", 0))

	notifications, err := h.Queries.ListNotificationsByMerchant(c.Context(), db.ListNotificationsByMerchantParams{
		MerchantID: merchantID,
		Limit:      limit,
		Offset:     offset,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list notifications"})
	}
	unread, err := h.Queries.CountUnreadNotifications(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to count unread notifications"})
	}
	return c.JSON(fiber.Map{"notifications": notifications, "unread_count": unread})
}

func (h *Handler) MarkNotificationRead(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	notificationID, err := parseUUIDParam(c, "notificationId")
	if err != nil {
		return badRequest(c, "invalid notification id")
	}

	rows, err := h.Queries.MarkNotificationRead(c.Context(), db.MarkNotificationReadParams{
		ID:         notificationID,
		MerchantID: merchantID,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to mark notification read"})
	}
	if rows == 0 {
		return notFound(c)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *Handler) MarkAllNotificationsRead(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	if err := h.Queries.MarkAllNotificationsRead(c.Context(), merchantID); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to mark notifications read"})
	}
	return c.SendStatus(fiber.StatusNoContent)
}
