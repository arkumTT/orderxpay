package main

import (
	"context"
	"log"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/orderxpay/api/internal/auth"
	"github.com/orderxpay/api/internal/config"
	"github.com/orderxpay/api/internal/server"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	ctx := context.Background()

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db: failed to create connection pool: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("db: failed to ping database: %v", err)
	}

	tokenMaker, err := auth.NewPasetoMaker(cfg.PasetoSymmetricKey)
	if err != nil {
		log.Fatalf("auth: %v", err)
	}

	app := server.New(server.Options{
		Pool:              pool,
		TokenMaker:        tokenMaker,
		DevMode:           cfg.Env == "development",
		PaystackSecretKey: cfg.PaystackSecretKey,
		WebBaseURL:        cfg.WebBaseURL,
	})

	log.Printf("orderxpay-api listening on :%s (%s)", cfg.Port, cfg.Env)
	if err := app.Listen(":" + cfg.Port); err != nil {
		log.Fatalf("server: %v", err)
	}
}
