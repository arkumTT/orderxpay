package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
	"github.com/orderxpay/api/internal/whatsapp"
)

// VerifyWhatsAppWebhook is Meta's GET subscribe handshake (Section 4.4/7.3)
// — done once, when the webhook URL is registered in the Meta App console.
// Must echo hub.challenge back verbatim as plain text when hub.verify_token
// matches WHATSAPP_WEBHOOK_VERIFY_TOKEN, or Meta refuses to save the URL.
func (h *Handler) VerifyWhatsAppWebhook(c *fiber.Ctx) error {
	if h.WhatsAppWebhookVerifyToken == "" ||
		c.Query("hub.mode") != "subscribe" ||
		c.Query("hub.verify_token") != h.WhatsAppWebhookVerifyToken {
		return c.SendStatus(fiber.StatusForbidden)
	}
	return c.SendString(c.Query("hub.challenge"))
}

type whatsappWebhookPayload struct {
	Entry []struct {
		Changes []struct {
			Value struct {
				Metadata struct {
					PhoneNumberID string `json:"phone_number_id"`
				} `json:"metadata"`
				Messages []struct {
					From string `json:"from"`
					Type string `json:"type"`
					Text struct {
						Body string `json:"body"`
					} `json:"text"`
				} `json:"messages"`
			} `json:"value"`
		} `json:"changes"`
	} `json:"entry"`
}

// HandleWhatsAppWebhook receives inbound messages — the mechanism behind
// Section 4.4's merchant auto-reply. Each merchant has their own
// phone_number_id registered under the platform's single WhatsApp Business
// Account, so the receiving number in the payload (not any per-merchant
// credential) is what attributes an inbound message to a merchant. A reply
// here is a plain session message, valid because it's within Meta's
// 24-hour customer-service window (replying to an inbound message) — no
// pre-approved template needed, unlike a business-initiated message.
func (h *Handler) HandleWhatsAppWebhook(c *fiber.Ctx) error {
	body := c.Body()
	signature := c.Get("X-Hub-Signature-256")
	sigValid := whatsapp.VerifyWebhookSignature(h.WhatsAppAppSecret, body, signature)
	if !sigValid {
		h.logWebhookDelivery(c.Context(), "whatsapp", "", "", false, false, "invalid signature")
		return badRequest(c, "invalid webhook signature")
	}

	var payload whatsappWebhookPayload
	if err := json.Unmarshal(body, &payload); err != nil {
		h.logWebhookDelivery(c.Context(), "whatsapp", "", "", sigValid, false, "invalid JSON payload")
		return badRequest(c, "invalid webhook payload")
	}

	for _, entry := range payload.Entry {
		for _, change := range entry.Changes {
			phoneNumberID := change.Value.Metadata.PhoneNumberID
			for _, msg := range change.Value.Messages {
				if msg.Type != "text" {
					continue
				}
				h.processInboundWhatsAppMessage(c.Context(), phoneNumberID, msg.From, msg.Text.Body)
			}
		}
	}
	h.logWebhookDelivery(c.Context(), "whatsapp", "messages", "", sigValid, true, "")
	return c.SendStatus(fiber.StatusOK)
}

// processInboundWhatsAppMessage logs the inbound message, then — if the
// owning merchant has auto-reply on — sends their configured greeting back
// and logs that too. Every failure here is logged and swallowed rather
// than turned into a webhook error response: Meta retries a non-2xx
// delivery, and a merchant lookup miss or a down WhatsApp client isn't
// something retrying the same webhook body would ever fix.
func (h *Handler) processInboundWhatsAppMessage(ctx context.Context, phoneNumberID, from, body string) {
	merchant, err := h.Queries.GetMerchantByWhatsAppPhoneNumberID(ctx, phoneNumberID)
	if errors.Is(err, pgx.ErrNoRows) {
		log.Printf("whatsapp webhook: no merchant registered for phone_number_id %s — ignoring", phoneNumberID)
		return
	} else if err != nil {
		log.Printf("whatsapp webhook: failed to look up merchant for phone_number_id %s: %v", phoneNumberID, err)
		return
	}

	if _, err := h.Queries.CreateConversation(ctx, db.CreateConversationParams{
		MerchantID:      merchant.ID,
		CustomerContact: from,
		Channel:         "whatsapp",
		Direction:       "inbound",
		MessageType:     "transactional",
		Consent:         true,
	}); err != nil {
		log.Printf("whatsapp webhook: failed to log inbound message from %s: %v", from, err)
	}

	if !merchant.WhatsappAutoReplyEnabled || !merchant.WhatsappGreetingMessage.Valid || merchant.WhatsappGreetingMessage.String == "" {
		return
	}

	client := h.whatsappClient(ctx)
	if !client.Enabled() {
		return
	}
	if _, err := client.SendText(ctx, whatsapp.SendTextParams{
		PhoneNumberID: phoneNumberID,
		To:            from,
		Body:          merchant.WhatsappGreetingMessage.String,
	}); err != nil {
		log.Printf("whatsapp webhook: failed to send auto-reply to %s: %v", from, err)
		return
	}

	if _, err := h.Queries.CreateConversation(ctx, db.CreateConversationParams{
		MerchantID:      merchant.ID,
		CustomerContact: from,
		Channel:         "whatsapp",
		Direction:       "outbound",
		MessageType:     "transactional",
		Consent:         true,
	}); err != nil {
		log.Printf("whatsapp webhook: failed to log outbound auto-reply to %s: %v", from, err)
	}
}

type setMerchantWhatsAppPhoneNumberRequest struct {
	PhoneNumberID string `json:"phone_number_id"`
}

// SetMerchantWhatsAppPhoneNumberID is the Back Office provisioning step
// (Section 7.3): after an admin registers the merchant's number under the
// platform WhatsApp Business Account in Meta's console, the resulting
// phone_number_id is recorded here so inbound webhooks resolve to this
// merchant. There's no merchant self-service path for this — registering a
// number with Meta is an admin action, not something the mobile app does.
func (h *Handler) SetMerchantWhatsAppPhoneNumberID(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req setMerchantWhatsAppPhoneNumberRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	merchant, err := h.Queries.UpdateMerchantWhatsAppPhoneNumberID(c.Context(), db.UpdateMerchantWhatsAppPhoneNumberIDParams{
		ID:                    id,
		WhatsappPhoneNumberID: textOrNull(req.PhoneNumberID),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusConflict).JSON(fiber.Map{"error": "phone_number_id may already be assigned to another merchant"})
	}
	return c.JSON(stripMerchantSecrets(merchant))
}
