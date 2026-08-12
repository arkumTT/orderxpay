package handlers

import (
	"github.com/gofiber/fiber/v2"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type logConversationRequest struct {
	CustomerContact string `json:"customer_contact"`
	Channel         string `json:"channel"`      // whatsapp | sms | email
	Direction       string `json:"direction"`    // inbound | outbound
	MessageType     string `json:"message_type"` // transactional | marketing
	TemplateID      string `json:"template_id"`
	Consent         bool   `json:"consent"`
}

// LogConversation records a message for the WhatsApp/SMS/email module
// (Section 6.4) — transactional vs. marketing messages carry different
// consent and billing rules, so both fields are required, not inferred.
func (h *Handler) LogConversation(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req logConversationRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.CustomerContact == "" {
		return badRequest(c, "customer_contact is required")
	}
	switch req.Channel {
	case "whatsapp", "sms", "email":
	default:
		return badRequest(c, "channel must be one of whatsapp, sms, email")
	}
	switch req.Direction {
	case "inbound", "outbound":
	default:
		return badRequest(c, "direction must be inbound or outbound")
	}
	switch req.MessageType {
	case "transactional", "marketing":
	default:
		return badRequest(c, "message_type must be transactional or marketing")
	}
	if req.MessageType == "marketing" && !req.Consent {
		return badRequest(c, "marketing messages require recorded consent (Data Protection Act, WhatsApp commerce policy)")
	}

	convo, err := h.Queries.CreateConversation(c.Context(), db.CreateConversationParams{
		MerchantID:      merchantID,
		CustomerContact: req.CustomerContact,
		Channel:         req.Channel,
		Direction:       req.Direction,
		MessageType:     req.MessageType,
		TemplateID:      textOrNull(req.TemplateID),
		Consent:         req.Consent,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to log conversation"})
	}
	return c.Status(fiber.StatusCreated).JSON(convo)
}

func (h *Handler) ListConversations(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	customerContact := c.Query("customer_contact")
	if customerContact == "" {
		return badRequest(c, "customer_contact query param is required")
	}
	limit := int32(c.QueryInt("limit", 50))

	convos, err := h.Queries.ListConversationsByMerchant(c.Context(), db.ListConversationsByMerchantParams{
		MerchantID:      merchantID,
		CustomerContact: customerContact,
		Limit:           limit,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list conversations"})
	}
	return c.JSON(convos)
}
