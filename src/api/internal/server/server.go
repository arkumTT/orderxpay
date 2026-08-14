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

type Options struct {
	Pool              *pgxpool.Pool
	TokenMaker        auth.Maker
	DevMode           bool
	PaystackSecretKey string
	WebBaseURL        string
}

func New(opts Options) *fiber.App {
	app := fiber.New(fiber.Config{
		AppName: "orderxpay-api",
	})

	app.Use(recover.New())
	app.Use(logger.New())
	app.Use(cors.New())

	h := handlers.New(handlers.Options{
		Pool:              opts.Pool,
		TokenMaker:        opts.TokenMaker,
		DevMode:           opts.DevMode,
		PaystackSecretKey: opts.PaystackSecretKey,
		WebBaseURL:        opts.WebBaseURL,
	})
	orderxpayhttp.RegisterRoutes(app, h)

	return app
}
