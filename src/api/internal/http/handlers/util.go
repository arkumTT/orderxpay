package handlers

import (
	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/orderxpay/api/internal/auth"
	"github.com/orderxpay/api/internal/middleware"
)

func parseUUIDParam(c *fiber.Ctx, name string) (pgtype.UUID, error) {
	return parseUUID(c.Params(name))
}

func parseUUID(s string) (pgtype.UUID, error) {
	id, err := uuid.Parse(s)
	if err != nil {
		return pgtype.UUID{}, err
	}
	return toPgUUID(id), nil
}

func toPgUUID(id uuid.UUID) pgtype.UUID {
	return pgtype.UUID{Bytes: id, Valid: true}
}

// uuidOrNull parses s as a UUID, or returns a null pgtype.UUID when s is empty.
func uuidOrNull(s string) (pgtype.UUID, error) {
	if s == "" {
		return pgtype.UUID{}, nil
	}
	return parseUUID(s)
}

func textOrNull(s string) pgtype.Text {
	if s == "" {
		return pgtype.Text{}
	}
	return pgtype.Text{String: s, Valid: true}
}

// float8OrNull converts an optional float64 request field (nil when the
// client sends it as JSON null / omits it) into pgtype.Float8.
func float8OrNull(f *float64) pgtype.Float8 {
	if f == nil {
		return pgtype.Float8{}
	}
	return pgtype.Float8{Float64: *f, Valid: true}
}

func badRequest(c *fiber.Ctx, msg string) error {
	return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": msg})
}

func notFound(c *fiber.Ctx) error {
	return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "not found"})
}

func notImplemented(c *fiber.Ctx, msg string) error {
	return c.Status(fiber.StatusNotImplemented).JSON(fiber.Map{"error": msg})
}

// actorPayload fetches the authenticated request's PASETO payload — set by
// middleware.RequireAuth earlier in the chain.
func actorPayload(c *fiber.Ctx) (*auth.Payload, bool) {
	payload, ok := c.Locals(middleware.AuthPayloadKey).(*auth.Payload)
	return payload, ok
}
