package middleware

import (
	"crypto/rand"
	"encoding/base64"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

const (
	// CSRFTokenHeader is the header name for the CSRF token
	CSRFTokenHeader = "X-CSRF-Token"
	// CSRFCookieName is the cookie name for the CSRF token
	CSRFCookieName = "csrf_token"
	// CSRFTokenLength is the length of the generated token
	CSRFTokenLength = 32
)

// CSRFConfig holds CSRF middleware configuration
type CSRFConfig struct {
	// TokenLength is the length of the CSRF token
	TokenLength int
	// CookieMaxAge is the max age for the CSRF cookie
	CookieMaxAge int
	// CookieSecure sets the Secure flag on the cookie
	CookieSecure bool
	// CookieSameSite sets the SameSite attribute on the cookie
	CookieSameSite http.SameSite
	// ExemptMethods are HTTP methods that don't require CSRF validation
	ExemptMethods []string
	// ExemptPaths are URL paths that don't require CSRF validation
	ExemptPaths []string
	// ExemptPathPrefixes are URL path prefixes that don't require CSRF validation
	// Useful for APIs that use Bearer token authentication (immune to CSRF)
	ExemptPathPrefixes []string
}

// DefaultCSRFConfig returns a default CSRF configuration
func DefaultCSRFConfig(isProduction bool) CSRFConfig {
	return CSRFConfig{
		TokenLength:    CSRFTokenLength,
		CookieMaxAge:   3600, // 1 hour
		CookieSecure:   isProduction,
		CookieSameSite: http.SameSiteStrictMode,
		ExemptMethods:  []string{"GET", "HEAD", "OPTIONS"},
		ExemptPaths: []string{
			"/health",
			"/api/auth/login",
			"/api/auth/register",
			"/api/auth/refresh",
			"/api/auth/logout",
			"/api/ws", // WebSocket uses its own auth mechanism
		},
		// Exempt paths that use Bearer token authentication (immune to CSRF)
		ExemptPathPrefixes: []string{
			"/api/notes", // Notes API uses JWT auth, not vulnerable to CSRF
		},
	}
}

// CSRFMiddleware provides CSRF protection
type CSRFMiddleware struct {
	config     CSRFConfig
	tokens     map[string]tokenEntry
	mu         sync.RWMutex
	cleanupTick time.Duration
}

type tokenEntry struct {
	token     string
	expiresAt time.Time
}

// NewCSRFMiddleware creates a new CSRF middleware instance
func NewCSRFMiddleware(config CSRFConfig) *CSRFMiddleware {
	csrf := &CSRFMiddleware{
		config:      config,
		tokens:      make(map[string]tokenEntry),
		cleanupTick: 15 * time.Minute,
	}
	go csrf.cleanup()
	return csrf
}

// Handler returns the Gin middleware handler
func (csrf *CSRFMiddleware) Handler() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path

		// Check if path is exempt (exact match)
		for _, exemptPath := range csrf.config.ExemptPaths {
			if path == exemptPath {
				c.Next()
				return
			}
		}

		// Check if path matches an exempt prefix (for APIs with Bearer auth)
		for _, prefix := range csrf.config.ExemptPathPrefixes {
			if len(path) >= len(prefix) && path[:len(prefix)] == prefix {
				c.Next()
				return
			}
		}

		// Check if method is exempt
		method := c.Request.Method
		for _, m := range csrf.config.ExemptMethods {
			if method == m {
				// For exempt methods (GET, etc.), set CSRF token cookie if not present
				csrf.ensureTokenCookie(c)
				c.Next()
				return
			}
		}

		// Validate CSRF token for state-changing requests
		cookieToken, err := c.Cookie(CSRFCookieName)
		if err != nil || cookieToken == "" {
			c.JSON(http.StatusForbidden, gin.H{"error": "missing CSRF token cookie"})
			c.Abort()
			return
		}

		headerToken := c.GetHeader(CSRFTokenHeader)
		if headerToken == "" {
			c.JSON(http.StatusForbidden, gin.H{"error": "missing CSRF token header"})
			c.Abort()
			return
		}

		// Double-submit cookie pattern: compare cookie and header tokens
		if cookieToken != headerToken {
			c.JSON(http.StatusForbidden, gin.H{"error": "CSRF token mismatch"})
			c.Abort()
			return
		}

		// Validate token is in our store (optional additional validation)
		if !csrf.validateToken(cookieToken) {
			c.JSON(http.StatusForbidden, gin.H{"error": "invalid CSRF token"})
			c.Abort()
			return
		}

		c.Next()
	}
}

// GenerateToken generates a new CSRF token and stores it
func (csrf *CSRFMiddleware) GenerateToken() (string, error) {
	token, err := generateRandomToken(csrf.config.TokenLength)
	if err != nil {
		return "", err
	}

	csrf.mu.Lock()
	csrf.tokens[token] = tokenEntry{
		token:     token,
		expiresAt: time.Now().Add(time.Duration(csrf.config.CookieMaxAge) * time.Second),
	}
	csrf.mu.Unlock()

	return token, nil
}

// validateToken checks if the token exists and is not expired
func (csrf *CSRFMiddleware) validateToken(token string) bool {
	csrf.mu.RLock()
	entry, exists := csrf.tokens[token]
	csrf.mu.RUnlock()

	if !exists {
		return false
	}

	if time.Now().After(entry.expiresAt) {
		// Token expired, remove it
		csrf.mu.Lock()
		delete(csrf.tokens, token)
		csrf.mu.Unlock()
		return false
	}

	return true
}

// ensureTokenCookie ensures a CSRF token cookie is set
func (csrf *CSRFMiddleware) ensureTokenCookie(c *gin.Context) {
	_, err := c.Cookie(CSRFCookieName)
	if err != nil {
		// No cookie, generate and set one
		token, err := csrf.GenerateToken()
		if err != nil {
			return // Silently fail, will be handled on next request
		}
		csrf.setTokenCookie(c, token)
	}
}

// setTokenCookie sets the CSRF token cookie
func (csrf *CSRFMiddleware) setTokenCookie(c *gin.Context, token string) {
	c.SetSameSite(csrf.config.CookieSameSite)
	c.SetCookie(
		CSRFCookieName,
		token,
		csrf.config.CookieMaxAge,
		"/",
		"",
		csrf.config.CookieSecure,
		false, // httpOnly must be false so JavaScript can read it
	)
}

// SetTokenForResponse sets the CSRF token cookie and returns the token
// Call this after successful login/register
func (csrf *CSRFMiddleware) SetTokenForResponse(c *gin.Context) (string, error) {
	token, err := csrf.GenerateToken()
	if err != nil {
		return "", err
	}
	csrf.setTokenCookie(c, token)
	return token, nil
}

// cleanup removes expired tokens periodically
func (csrf *CSRFMiddleware) cleanup() {
	ticker := time.NewTicker(csrf.cleanupTick)
	for range ticker.C {
		csrf.mu.Lock()
		now := time.Now()
		for token, entry := range csrf.tokens {
			if now.After(entry.expiresAt) {
				delete(csrf.tokens, token)
			}
		}
		csrf.mu.Unlock()
	}
}

// generateRandomToken generates a cryptographically secure random token
func generateRandomToken(length int) (string, error) {
	bytes := make([]byte, length)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.URLEncoding.EncodeToString(bytes), nil
}
