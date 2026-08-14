// Package handlers wires HTTP requests to the sqlc-generated data layer.
//
// Simple reference-data endpoints (merchants, staff, items, delivery options,
// fee rules, conversations, audit reads) are fully wired here. Endpoints that
// depend on unbuilt business logic — the invoice engine (Section 4.3/4.8),
// PSP webhook handling (Section 4.5), and settlement reconciliation
// (Section 7.2) — are left as explicit 501 stubs; see the TODO in each.
package handlers

import (
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/orderxpay/api/internal/auth"
	db "github.com/orderxpay/api/internal/db/sqlc"
)

type Handler struct {
	Queries    *db.Queries
	Pool       *pgxpool.Pool
	TokenMaker auth.Maker
	// DevMode gates dev-only endpoints (see auth.go: DevIssueMerchantToken) —
	// never true outside local development. Merchant/staff OTP sign-in
	// (Section 4.1) isn't built yet, so this is the only way the mobile app
	// can get a session to call anything beyond CreateMerchant.
	DevMode bool
}

func New(pool *pgxpool.Pool, maker auth.Maker, devMode bool) *Handler {
	return &Handler{
		Queries:    db.New(pool),
		Pool:       pool,
		TokenMaker: maker,
		DevMode:    devMode,
	}
}
