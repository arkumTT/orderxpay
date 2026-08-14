// Package handlers wires HTTP requests to the sqlc-generated data layer.
//
// Simple reference-data endpoints (merchants, staff, items, delivery options,
// fee rules, conversations, audit reads) are fully wired here, as is the
// invoice engine (Section 4.3/4.8) and Paystack payment collection (Section
// 4.5/9.1). Settlement reconciliation (Section 7.2) is still an explicit 501
// stub; see the TODO there.
package handlers

import (
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/orderxpay/api/internal/auth"
	db "github.com/orderxpay/api/internal/db/sqlc"
	"github.com/orderxpay/api/internal/psp"
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
	// PSP is nil-safe: psp.Client.Enabled() is false without a secret key,
	// and payment-initiation handlers check that before dereferencing.
	PSP        *psp.Client
	WebBaseURL string
}

type Options struct {
	Pool              *pgxpool.Pool
	TokenMaker        auth.Maker
	DevMode           bool
	PaystackSecretKey string
	WebBaseURL        string
}

func New(opts Options) *Handler {
	return &Handler{
		Queries:    db.New(opts.Pool),
		Pool:       opts.Pool,
		TokenMaker: opts.TokenMaker,
		DevMode:    opts.DevMode,
		PSP:        psp.NewClient(opts.PaystackSecretKey),
		WebBaseURL: opts.WebBaseURL,
	}
}
