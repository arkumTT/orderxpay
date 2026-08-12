package middleware

import (
	"strings"

	"github.com/gofiber/fiber/v2"

	"github.com/orderxpay/api/internal/auth"
)

const (
	AuthPayloadKey = "auth_payload"
	authHeaderKey  = "Authorization"
	authScheme     = "Bearer"
)

// RequireAuth verifies the PASETO bearer token and stores its payload in fiber.Ctx locals.
func RequireAuth(maker auth.Maker) fiber.Handler {
	return func(c *fiber.Ctx) error {
		header := c.Get(authHeaderKey)
		if header == "" {
			return fiber.NewError(fiber.StatusUnauthorized, "authorization header is required")
		}

		fields := strings.Fields(header)
		if len(fields) != 2 || !strings.EqualFold(fields[0], authScheme) {
			return fiber.NewError(fiber.StatusUnauthorized, "authorization header format must be 'Bearer <token>'")
		}

		payload, err := maker.VerifyToken(fields[1])
		if err != nil {
			return fiber.NewError(fiber.StatusUnauthorized, err.Error())
		}

		c.Locals(AuthPayloadKey, payload)
		return c.Next()
	}
}

// RequireActorType restricts a route to one or more actor types (e.g. admin_user-only routes).
func RequireActorType(types ...auth.ActorType) fiber.Handler {
	return func(c *fiber.Ctx) error {
		payload, ok := c.Locals(AuthPayloadKey).(*auth.Payload)
		if !ok {
			return fiber.NewError(fiber.StatusUnauthorized, "missing auth payload")
		}
		for _, t := range types {
			if payload.ActorType == t {
				return c.Next()
			}
		}
		return fiber.NewError(fiber.StatusForbidden, "actor type not permitted for this route")
	}
}
