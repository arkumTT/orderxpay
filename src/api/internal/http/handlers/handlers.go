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
}

func New(pool *pgxpool.Pool, maker auth.Maker) *Handler {
	return &Handler{
		Queries:    db.New(pool),
		Pool:       pool,
		TokenMaker: maker,
	}
}
