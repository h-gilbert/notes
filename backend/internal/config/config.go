package config

import (
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Port           string
	DatabaseURL    string
	JWTSecret      string
	JWTExpiry      int // hours
	AllowedOrigins []string
	Environment    string // "development" or "production"
}

func Load() *Config {
	env := getEnv("ENVIRONMENT", "development")
	origins := getEnv("ALLOWED_ORIGINS", "")

	var allowedOrigins []string
	if origins != "" {
		allowedOrigins = strings.Split(origins, ",")
		for i := range allowedOrigins {
			allowedOrigins[i] = strings.TrimSpace(allowedOrigins[i])
		}
	} else if env == "development" {
		// Default development origins
		allowedOrigins = []string{"http://localhost:3030", "http://localhost:3000"}
	}

	return &Config{
		Port:           getEnv("PORT", "8080"),
		DatabaseURL:    getEnv("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/notes?sslmode=disable"),
		JWTSecret:      getEnv("JWT_SECRET", "your-secret-key-change-in-production"),
		JWTExpiry:      getEnvInt("JWT_EXPIRY_HOURS", 168), // 7 days
		AllowedOrigins: allowedOrigins,
		Environment:    env,
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}
