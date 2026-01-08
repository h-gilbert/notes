package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Port              string
	DatabaseURL       string
	JWTSecret         string
	JWTExpiry         int // minutes for access token
	RefreshExpiry     int // hours for refresh token
	AllowedOrigins    []string
	Environment       string // "development" or "production"
	MaxRequestBodyMB  int
	RateLimitRequests int // requests per minute
	RateLimitBurst    int // burst size
}

// Load loads configuration from environment variables.
// Returns an error if required configuration is missing in production.
func Load() (*Config, error) {
	env := getEnv("ENVIRONMENT", "development")
	origins := getEnv("ALLOWED_ORIGINS", "")

	// JWT Secret is required in production
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		if env == "production" {
			return nil, fmt.Errorf("JWT_SECRET environment variable is required in production")
		}
		// Only allow insecure default in development
		jwtSecret = "dev-only-insecure-secret-do-not-use-in-production"
	}

	// Validate JWT secret length
	if len(jwtSecret) < 32 && env == "production" {
		return nil, fmt.Errorf("JWT_SECRET must be at least 32 characters in production")
	}

	var allowedOrigins []string
	if origins != "" {
		allowedOrigins = strings.Split(origins, ",")
		for i := range allowedOrigins {
			allowedOrigins[i] = strings.TrimSpace(allowedOrigins[i])
		}
	} else if env == "development" {
		// Default development origins
		allowedOrigins = []string{"http://localhost:3030", "http://localhost:3000"}
	} else {
		return nil, fmt.Errorf("ALLOWED_ORIGINS environment variable is required in production")
	}

	return &Config{
		Port:              getEnv("PORT", "8080"),
		DatabaseURL:       getEnv("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/notes?sslmode=disable"),
		JWTSecret:         jwtSecret,
		JWTExpiry:         getEnvInt("JWT_EXPIRY_MINUTES", 60),    // 1 hour default
		RefreshExpiry:     getEnvInt("REFRESH_EXPIRY_HOURS", 168), // 7 days default
		AllowedOrigins:    allowedOrigins,
		Environment:       env,
		MaxRequestBodyMB:  getEnvInt("MAX_REQUEST_BODY_MB", 10),
		RateLimitRequests: getEnvInt("RATE_LIMIT_REQUESTS", 100), // per minute
		RateLimitBurst:    getEnvInt("RATE_LIMIT_BURST", 20),
	}, nil
}

// IsDevelopment returns true if running in development mode
func (c *Config) IsDevelopment() bool {
	return c.Environment == "development"
}

// IsProduction returns true if running in production mode
func (c *Config) IsProduction() bool {
	return c.Environment == "production"
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
