package handlers

import (
	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

func parseUUIDParam(c *fiber.Ctx, name string) (pgtype.UUID, error) {
	id, err := uuid.Parse(c.Params(name))
	if err != nil {
		return pgtype.UUID{}, err
	}
	return toPgUUID(id), nil
}

func toPgUUID(id uuid.UUID) pgtype.UUID {
	return pgtype.UUID{Bytes: id, Valid: true}
}

func textOrNull(s string) pgtype.Text {
	if s == "" {
		return pgtype.Text{}
	}
	return pgtype.Text{String: s, Valid: true}
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
