package middleware

import (
	"os"

	"github.com/gin-gonic/gin"
)

// SecurityHeaders adds essential security headers to all responses
func SecurityHeaders() gin.HandlerFunc {
	isProduction := os.Getenv("ENVIRONMENT") == "production"

	return func(c *gin.Context) {
		// Prevent MIME type sniffing
		c.Writer.Header().Set("X-Content-Type-Options", "nosniff")

		// Prevent clickjacking
		c.Writer.Header().Set("X-Frame-Options", "DENY")

		// XSS protection for older browsers
		c.Writer.Header().Set("X-XSS-Protection", "1; mode=block")

		// Control referrer information
		c.Writer.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")

		// Permissions policy - restrict features
		c.Writer.Header().Set("Permissions-Policy", "geolocation=(), microphone=(), camera=()")

		// HTTP Strict Transport Security (HSTS) - only in production
		// Tells browsers to only use HTTPS for this domain for 1 year
		if isProduction {
			c.Writer.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}

		// Content Security Policy - restrict resource loading
		// Note: API typically doesn't serve HTML, but good defense-in-depth
		c.Writer.Header().Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")

		c.Next()
	}
}
