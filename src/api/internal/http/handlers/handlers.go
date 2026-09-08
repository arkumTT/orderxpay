// Package handlers wires HTTP requests to the sqlc-generated data layer.
//
// Simple reference-data endpoints (merchants, staff, items, delivery options,
// fee rules, conversations, audit reads) are fully wired here, as is the
// invoice engine (Section 4.3/4.8), Paystack payment collection (Section
// 4.5/9.1), and the settlement/payout engine (Section 7.2).
package handlers

import (
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/orderxpay/api/internal/auth"
	db "github.com/orderxpay/api/internal/db/sqlc"
	"github.com/orderxpay/api/internal/email"
	"github.com/orderxpay/api/internal/fcm"
	"github.com/orderxpay/api/internal/hubtel"
	"github.com/orderxpay/api/internal/psp"
	"github.com/orderxpay/api/internal/sms"
	"github.com/orderxpay/api/internal/whatsapp"
)

type Handler struct {
	Queries    *db.Queries
	Pool       *pgxpool.Pool
	TokenMaker auth.Maker
	// DevMode gates dev-only endpoints (see auth.go: DevIssueMerchantToken).
	// Never true outside local development.
	DevMode bool
	// PSP is nil-safe: psp.Client.Enabled() is false without a secret key,
	// and payment-initiation handlers check that before dereferencing.
	PSP        *psp.Client
	WebBaseURL string
	// WhatsApp is nil-safe, same posture as PSP — see whatsappClient in
	// integrations.go for the DB-secret-override-wins-over-env pattern.
	WhatsApp                   *whatsapp.Client
	WhatsAppAppSecret          string
	WhatsAppWebhookVerifyToken string
	// Section 4.2 — item photo uploads. UploadDir is a local filesystem
	// path (no cloud storage account exists); APIPublicBaseURL is this
	// API's own public origin, for building an absolute image_url.
	UploadDir        string
	APIPublicBaseURL string
	// Section 4.1/7.1 — the liveness-check selfie's storage, deliberately
	// separate from UploadDir/APIPublicBaseURL above: never served through
	// app.Static, only through the admin-authenticated GetKYCSelfiePhoto.
	KYCUploadDir string
	// SMS is nil-safe, same posture as PSP/WhatsApp — see smsClient in
	// integrations.go for the DB-secret-override-wins-over-env pattern.
	// Email has no DB-override path (SMTP is multiple values, not one
	// secret) — it's env-configured only, see email.Client's doc comment.
	SMS   *sms.Client
	Email *email.Client
	// FCM is nil-safe, same posture as PSP/WhatsApp/SMS — Section 4.10
	// Phase 2 push notifications, Android only (see internal/fcm).
	FCM *fcm.Client
	// Hubtel is nil-safe, same posture as PSP/WhatsApp/SMS/FCM — Section
	// 4.5/9's USSD fallback. See internal/hubtel's doc comment: unlike
	// every other client here, this one has never been checked against a
	// real account, since none exists yet.
	Hubtel *hubtel.Client
}

type Options struct {
	Pool              *pgxpool.Pool
	TokenMaker        auth.Maker
	DevMode           bool
	PaystackSecretKey string
	WebBaseURL        string

	WhatsAppAccessToken        string
	WhatsAppAppSecret          string
	WhatsAppWebhookVerifyToken string

	UploadDir        string
	APIPublicBaseURL string
	KYCUploadDir     string

	SMSAPIKey   string
	SMSSenderID string

	SMTPHost      string
	SMTPPort      string
	SMTPUsername  string
	SMTPPassword  string
	SMTPFromEmail string
	SMTPFromName  string

	HubtelClientID     string
	HubtelClientSecret string
	HubtelPOSSalesID   string

	FirebaseServiceAccountJSON string
}

func New(opts Options) *Handler {
	return &Handler{
		Queries:                    db.New(opts.Pool),
		Pool:                       opts.Pool,
		TokenMaker:                 opts.TokenMaker,
		DevMode:                    opts.DevMode,
		PSP:                        psp.NewClient(opts.PaystackSecretKey),
		WebBaseURL:                 opts.WebBaseURL,
		WhatsApp:                   whatsapp.NewClient(opts.WhatsAppAccessToken),
		WhatsAppAppSecret:          opts.WhatsAppAppSecret,
		WhatsAppWebhookVerifyToken: opts.WhatsAppWebhookVerifyToken,
		UploadDir:                  opts.UploadDir,
		APIPublicBaseURL:           opts.APIPublicBaseURL,
		KYCUploadDir:               opts.KYCUploadDir,
		SMS:                        sms.NewClient(opts.SMSAPIKey, opts.SMSSenderID),
		Email: email.NewClient(
			opts.SMTPHost, opts.SMTPPort, opts.SMTPUsername, opts.SMTPPassword,
			opts.SMTPFromEmail, opts.SMTPFromName,
		),
		FCM:    fcm.NewClient(opts.FirebaseServiceAccountJSON),
		Hubtel: hubtel.NewClient(opts.HubtelClientID, opts.HubtelClientSecret, opts.HubtelPOSSalesID),
	}
}
