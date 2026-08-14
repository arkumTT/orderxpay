package server

import (
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/orderxpay/api/internal/auth"
	orderxpayhttp "github.com/orderxpay/api/internal/http"
	"github.com/orderxpay/api/internal/http/handlers"
)

func New(pool *pgxpool.Pool, tokenMaker auth.Maker, devMode bool) *fiber.App {
	app := fiber.New(fiber.Config{
		AppName: "orderxpay-api",
	})

	app.Use(recover.New())
	app.Use(logger.New())
	app.Use(cors.New())

	h := handlers.New(pool, tokenMaker, devMode)
	orderxpayhttp.RegisterRoutes(app, h)

	return app
}
