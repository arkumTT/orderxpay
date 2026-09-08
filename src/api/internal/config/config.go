package config

import (
	"fmt"
	"os"
	"strings"
)

type Config struct {
	Env                string
	Port               string
	DatabaseURL        string
	PasetoSymmetricKey string // must be exactly 32 bytes
	PaystackSecretKey  string // Section 9.1 — empty disables payment initiation, not a startup error
	WebBaseURL         string // customer-facing web app, for PSP callback_url construction

	// WhatsApp Cloud API (Section 4.4/6.2/7.3) — all three empty just means
	// the integration silently doesn't fire yet, same as PaystackSecretKey.
	WhatsAppAccessToken        string // Meta System User token, account-level (works across every merchant's phone number)
	WhatsAppAppSecret          string // Meta App's Basic Settings secret, for inbound webhook signature verification
	WhatsAppWebhookVerifyToken string // arbitrary string we choose; Meta echoes it back during the webhook subscribe handshake

	// Section 4.2 — item photo uploads, stored on local disk (no cloud
	// storage account exists). UploadDir is where files land on this
	// server; APIPublicBaseURL is this API's own public origin, used to
	// build the absolute image_url returned to clients (distinct from
	// WebBaseURL, which is the customer-facing web app's origin).
	UploadDir        string
	APIPublicBaseURL string

	// KYCUploadDir is a deliberately separate directory from UploadDir — the
	// liveness-check selfie captured during Tier 1 verification (Section
	// 4.1/7.1) is sensitive (someone's face, tied to a real identity
	// document) and must never be reachable through the public
	// app.Static("/uploads", ...) mount UploadDir is served from. Only
	// GetKYCSelfiePhoto (admin-authenticated, gated by the same
	// merchants.kyc_review permission as the review queue itself) reads
	// from here.
	KYCUploadDir string

	// Real OTP/verification-email delivery (Section 9 — previously
	// unwired; see otp.go/merchants.go). SMS via Arkesel (Ghana-focused,
	// plain REST API); email via generic SMTP so any provider works.
	SMSAPIKey   string
	SMSSenderID string

	// Section 4.10 Phase 2 — push notifications via Firebase Cloud
	// Messaging, Android only for now (see internal/fcm's doc comment).
	// Empty means push silently doesn't fire, same posture as the other
	// optional integrations above — the in-app notification feed (Phase 1)
	// still works regardless.
	FirebaseServiceAccountJSON string

	SMTPHost      string
	SMTPPort      string
	SMTPUsername  string
	SMTPPassword  string
	SMTPFromEmail string
	SMTPFromName  string

	// Hubtel USSD fallback (Section 4.5/9) — three values, not one
	// rotatable secret, so env-configured only, same posture as SMTP
	// above (see internal/hubtel's doc comment for what's unverified).
	// All three empty means the integration silently doesn't fire, same
	// as PaystackSecretKey/WhatsAppAccessToken/SMSAPIKey.
	HubtelClientID     string
	HubtelClientSecret string
	HubtelPOSSalesID   string
}

func Load() (Config, error) {
	loadDotEnv(".env")

	cfg := Config{
		Env:                getEnv("ENV", "development"),
		Port:               getEnv("PORT", "8080"),
		DatabaseURL:        os.Getenv("DATABASE_URL"),
		PasetoSymmetricKey: os.Getenv("PASETO_SYMMETRIC_KEY"),
		PaystackSecretKey:  os.Getenv("PAYSTACK_SECRET_KEY"),
		WebBaseURL:         getEnv("WEB_BASE_URL", "http://localhost:3000"),

		WhatsAppAccessToken:        os.Getenv("WHATSAPP_ACCESS_TOKEN"),
		WhatsAppAppSecret:          os.Getenv("WHATSAPP_APP_SECRET"),
		WhatsAppWebhookVerifyToken: os.Getenv("WHATSAPP_WEBHOOK_VERIFY_TOKEN"),

		UploadDir:        getEnv("UPLOAD_DIR", "./uploads"),
		APIPublicBaseURL: getEnv("API_PUBLIC_BASE_URL", "http://localhost:8080"),
		KYCUploadDir:     getEnv("KYC_UPLOAD_DIR", "./private_kyc_uploads"),

		SMSAPIKey:   os.Getenv("SMS_API_KEY"),
		SMSSenderID: os.Getenv("SMS_SENDER_ID"),

		FirebaseServiceAccountJSON: getEnv("FIREBASE_SERVICE_ACCOUNT_JSON", "./firebase-service-account.json"),

		SMTPHost:      os.Getenv("SMTP_HOST"),
		SMTPPort:      getEnv("SMTP_PORT", "587"),
		SMTPUsername:  os.Getenv("SMTP_USERNAME"),
		SMTPPassword:  os.Getenv("SMTP_PASSWORD"),
		SMTPFromEmail: os.Getenv("SMTP_FROM_EMAIL"),
		SMTPFromName:  getEnv("SMTP_FROM_NAME", "OrderxPay"),

		HubtelClientID:     os.Getenv("HUBTEL_CLIENT_ID"),
		HubtelClientSecret: os.Getenv("HUBTEL_CLIENT_SECRET"),
		HubtelPOSSalesID:   os.Getenv("HUBTEL_POS_SALES_ID"),
	}

	if cfg.DatabaseURL == "" {
		return cfg, fmt.Errorf("DATABASE_URL is required")
	}
	if len(cfg.PasetoSymmetricKey) != 32 {
		return cfg, fmt.Errorf("PASETO_SYMMETRIC_KEY must be exactly 32 bytes, got %d", len(cfg.PasetoSymmetricKey))
	}

	return cfg, nil
}

func getEnv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

// loadDotEnv is a minimal, dependency-free .env reader for local
// development — populates process env vars from the file without
// overriding any already set (so real deployments, which inject env vars
// directly and have no .env file, are unaffected). Missing file is not an
// error; it's the expected case outside local dev.
func loadDotEnv(path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		if _, exists := os.LookupEnv(key); exists {
			continue
		}
		os.Setenv(key, strings.TrimSpace(value))
	}
}
