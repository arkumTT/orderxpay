package handlers

import (
	"github.com/gofiber/fiber/v2"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// ListMerchantNotes and CreateMerchantNote back the Section 7.1 merchant
// detail view's "notes/flags from support or compliance staff" panel — a
// freeform annotation trail, distinct from the automated risk_flags table
// surfaced separately by ListMerchantRiskFlags.
func (h *Handler) ListMerchantNotes(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	notes, err := h.Queries.ListMerchantNotes(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list notes"})
	}
	return c.JSON(notes)
}

type createMerchantNoteRequest struct {
	Body string `json:"body"`
}

func (h *Handler) CreateMerchantNote(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req createMerchantNoteRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Body == "" {
		return badRequest(c, "body is required")
	}

	payload, ok := actorPayload(c)
	if !ok {
		return fiber.NewError(fiber.StatusUnauthorized, "missing auth payload")
	}

	note, err := h.Queries.CreateMerchantNote(c.Context(), db.CreateMerchantNoteParams{
		MerchantID: merchantID,
		AuthorID:   toPgUUID(payload.ActorID),
		Body:       req.Body,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create note"})
	}
	return c.Status(fiber.StatusCreated).JSON(note)
}

// ListMerchantRiskFlags is the merchant-scoped counterpart to
// ListRiskFlagsAdmin (Section 7.6), reused here so the detail view can show
// one merchant's automated fraud flags without a separate round trip
// through the cross-merchant risk queue.
func (h *Handler) ListMerchantRiskFlags(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	flags, err := h.Queries.ListRiskFlagsByMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list risk flags"})
	}
	return c.JSON(flags)
}
