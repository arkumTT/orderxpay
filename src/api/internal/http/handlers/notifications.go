package handlers

import (
	"context"
	"fmt"
	"log"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
	"github.com/orderxpay/api/internal/fcm"
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
// Real and persisted — created at the four trigger points that each also
// call pushToMerchant below (payment received, new order request, payout
// processed, KYC status change). Push is Android-only via FCM (Phase 2 —
// see internal/fcm); SMS/WhatsApp delivery still isn't built, since both
// depend on integrations this platform doesn't have yet (Section 7.3).
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

// pushToMerchant fans a push notification out to every device registered
// for the merchant (Section 4.10 Phase 2). Best-effort, same posture as
// every CreateNotification call it follows: a push failure is logged, never
// returned to the caller, since the in-app notification feed is already
// the source of truth and a real payment/order/payout/review action must
// never be undone or blocked by a notification delivery problem. A token
// FCM reports as no-longer-registered (app uninstalled, token rotated) is
// deleted rather than retried on the next call.
func (h *Handler) pushToMerchant(ctx context.Context, merchantID pgtype.UUID, title, body string, data map[string]string) {
	if !h.FCM.Enabled() {
		return
	}
	tokens, err := h.Queries.ListDeviceTokensByMerchant(ctx, merchantID)
	if err != nil {
		log.Printf("fcm: failed to list device tokens for merchant %s: %v", merchantID, err)
		return
	}
	for _, t := range tokens {
		if err := h.FCM.Send(ctx, t.FcmToken, title, body, data); err != nil {
			if fcm.IsUnregistered(err) {
				if delErr := h.Queries.DeleteDeviceToken(ctx, t.FcmToken); delErr != nil {
					log.Printf("fcm: failed to delete stale token: %v", delErr)
				}
				continue
			}
			log.Printf("fcm: failed to send push to merchant %s: %v", merchantID, err)
		}
	}
}

type registerDeviceTokenRequest struct {
	FcmToken string `json:"fcm_token"`
	Platform string `json:"platform"`
}

// RegisterDeviceToken is called once the merchant app has a live FCM
// token (on launch, and again whenever FCM rotates it — see
// api_client.dart's registerDeviceToken). Upserts on the token itself, so
// re-registering the same token is a no-op that just refreshes updated_at.
func (h *Handler) RegisterDeviceToken(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	var req registerDeviceTokenRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.FcmToken == "" {
		return badRequest(c, "fcm_token is required")
	}
	platform := req.Platform
	if platform == "" {
		platform = "android"
	}

	token, err := h.Queries.UpsertDeviceToken(c.Context(), db.UpsertDeviceTokenParams{
		MerchantID: merchantID,
		FcmToken:   req.FcmToken,
		Platform:   platform,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to register device token"})
	}
	return c.Status(fiber.StatusCreated).JSON(token)
}

type unregisterDeviceTokenRequest struct {
	FcmToken string `json:"fcm_token"`
}

// UnregisterDeviceToken is called on sign-out (see session.dart) so a
// signed-out device stops receiving pushes for a merchant it's no longer
// logged into, rather than waiting for FCM to eventually report the token
// unregistered.
func (h *Handler) UnregisterDeviceToken(c *fiber.Ctx) error {
	var req unregisterDeviceTokenRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.FcmToken == "" {
		return badRequest(c, "fcm_token is required")
	}
	if err := h.Queries.DeleteDeviceToken(c.Context(), req.FcmToken); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to unregister device token"})
	}
	return c.SendStatus(fiber.StatusNoContent)
}
