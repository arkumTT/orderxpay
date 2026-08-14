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
