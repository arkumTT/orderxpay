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
