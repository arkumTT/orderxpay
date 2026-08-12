package config

import (
	"fmt"
	"os"
)

type Config struct {
	Env                string
	Port               string
	DatabaseURL        string
	PasetoSymmetricKey string // must be exactly 32 bytes
}

func Load() (Config, error) {
	cfg := Config{
		Env:                getEnv("ENV", "development"),
		Port:               getEnv("PORT", "8080"),
		DatabaseURL:        os.Getenv("DATABASE_URL"),
		PasetoSymmetricKey: os.Getenv("PASETO_SYMMETRIC_KEY"),
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
