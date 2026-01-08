package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// RateLimiter implements a simple token bucket rate limiter
type RateLimiter struct {
	requests    int           // requests per interval
	interval    time.Duration // time interval
	burst       int           // maximum burst size
	clients     map[string]*clientBucket
	mu          sync.RWMutex
	cleanupTick time.Duration
}

type clientBucket struct {
	tokens     float64
	lastAccess time.Time
}

// NewRateLimiter creates a new rate limiter
func NewRateLimiter(requests int, interval time.Duration, burst int) *RateLimiter {
	rl := &RateLimiter{
		requests:    requests,
		interval:    interval,
		burst:       burst,
		clients:     make(map[string]*clientBucket),
		cleanupTick: time.Minute * 5,
	}
	go rl.cleanup()
	return rl
}

// Allow checks if a request from the given key should be allowed
func (rl *RateLimiter) Allow(key string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	client, exists := rl.clients[key]

	if !exists {
		rl.clients[key] = &clientBucket{
			tokens:     float64(rl.burst - 1),
			lastAccess: now,
		}
		return true
	}

	// Calculate tokens to add based on time elapsed
	elapsed := now.Sub(client.lastAccess)
	tokensToAdd := float64(rl.requests) * (elapsed.Seconds() / rl.interval.Seconds())
	client.tokens = min(float64(rl.burst), client.tokens+tokensToAdd)
	client.lastAccess = now

	if client.tokens >= 1 {
		client.tokens--
		return true
	}

	return false
}

// cleanup removes stale entries
func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(rl.cleanupTick)
	for range ticker.C {
		rl.mu.Lock()
		cutoff := time.Now().Add(-rl.cleanupTick)
		for key, client := range rl.clients {
			if client.lastAccess.Before(cutoff) {
				delete(rl.clients, key)
			}
		}
		rl.mu.Unlock()
	}
}

// RateLimitMiddleware returns a Gin middleware for rate limiting
func RateLimitMiddleware(rl *RateLimiter) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Use IP address as the key
		key := c.ClientIP()

		if !rl.Allow(key) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "rate limit exceeded, please try again later",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// AuthRateLimiter is a stricter rate limiter for authentication endpoints
type AuthRateLimiter struct {
	*RateLimiter
	failedAttempts map[string]int
	lockoutTime    map[string]time.Time
	mu             sync.RWMutex
}

// NewAuthRateLimiter creates a rate limiter specifically for auth endpoints
// with additional protection against brute force attacks
func NewAuthRateLimiter() *AuthRateLimiter {
	return &AuthRateLimiter{
		RateLimiter:    NewRateLimiter(5, time.Minute, 10), // 5 requests per minute, burst of 10
		failedAttempts: make(map[string]int),
		lockoutTime:    make(map[string]time.Time),
	}
}

// RecordFailedAttempt records a failed login attempt
func (al *AuthRateLimiter) RecordFailedAttempt(key string) {
	al.mu.Lock()
	defer al.mu.Unlock()

	al.failedAttempts[key]++

	// Lockout after 5 failed attempts
	if al.failedAttempts[key] >= 5 {
		al.lockoutTime[key] = time.Now().Add(15 * time.Minute)
	}
}

// ResetFailedAttempts resets the failed attempt counter on successful login
func (al *AuthRateLimiter) ResetFailedAttempts(key string) {
	al.mu.Lock()
	defer al.mu.Unlock()

	delete(al.failedAttempts, key)
	delete(al.lockoutTime, key)
}

// IsLockedOut checks if an IP is currently locked out
func (al *AuthRateLimiter) IsLockedOut(key string) bool {
	al.mu.RLock()
	defer al.mu.RUnlock()

	lockout, exists := al.lockoutTime[key]
	if !exists {
		return false
	}

	if time.Now().After(lockout) {
		// Lockout expired, will be cleaned up later
		return false
	}

	return true
}

// AuthRateLimitMiddleware returns a Gin middleware for auth rate limiting
func AuthRateLimitMiddleware(al *AuthRateLimiter) gin.HandlerFunc {
	return func(c *gin.Context) {
		key := c.ClientIP()

		// Check if locked out
		if al.IsLockedOut(key) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "too many failed attempts, please try again later",
			})
			c.Abort()
			return
		}

		// Check rate limit
		if !al.Allow(key) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "rate limit exceeded, please try again later",
			})
			c.Abort()
			return
		}

		// Store the rate limiter in context for handlers to record failed attempts
		c.Set("authRateLimiter", al)
		c.Next()
	}
}
