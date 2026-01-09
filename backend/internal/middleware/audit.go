package middleware

import (
	"log"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// AuditAction represents the type of action being audited
type AuditAction string

const (
	AuditActionCreate AuditAction = "CREATE"
	AuditActionRead   AuditAction = "READ"
	AuditActionUpdate AuditAction = "UPDATE"
	AuditActionDelete AuditAction = "DELETE"
	AuditActionSync   AuditAction = "SYNC"
)

// AuditLog represents an audit log entry
type AuditLog struct {
	Timestamp  time.Time   `json:"timestamp"`
	UserID     string      `json:"user_id"`
	Action     AuditAction `json:"action"`
	Resource   string      `json:"resource"`
	ResourceID string      `json:"resource_id,omitempty"`
	ClientIP   string      `json:"client_ip"`
	UserAgent  string      `json:"user_agent"`
	StatusCode int         `json:"status_code"`
	Duration   int64       `json:"duration_ms"`
	Details    string      `json:"details,omitempty"`
}

// AuditLogger handles audit logging
type AuditLogger struct {
	enabled bool
}

// NewAuditLogger creates a new audit logger
func NewAuditLogger(enabled bool) *AuditLogger {
	return &AuditLogger{enabled: enabled}
}

// Log writes an audit log entry
func (a *AuditLogger) Log(entry AuditLog) {
	if !a.enabled {
		return
	}

	log.Printf("[AUDIT] %s | user=%s | action=%s | resource=%s | resource_id=%s | ip=%s | status=%d | duration=%dms | details=%s",
		entry.Timestamp.Format(time.RFC3339),
		entry.UserID,
		entry.Action,
		entry.Resource,
		entry.ResourceID,
		entry.ClientIP,
		entry.StatusCode,
		entry.Duration,
		entry.Details,
	)
}

// AuditMiddleware creates audit logging middleware for specific resource types
func AuditMiddleware(logger *AuditLogger, resource string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if !logger.enabled {
			c.Next()
			return
		}

		startTime := time.Now()

		// Get user ID from context (set by AuthMiddleware)
		userID := ""
		if uid, exists := c.Get("userID"); exists {
			if id, ok := uid.(uuid.UUID); ok {
				userID = id.String()
			}
		}

		// Determine action based on HTTP method
		action := methodToAction(c.Request.Method)

		// Get resource ID from URL params
		resourceID := c.Param("id")

		// Process request
		c.Next()

		// Calculate duration
		duration := time.Since(startTime).Milliseconds()

		// Log the audit entry
		entry := AuditLog{
			Timestamp:  startTime,
			UserID:     userID,
			Action:     action,
			Resource:   resource,
			ResourceID: resourceID,
			ClientIP:   c.ClientIP(),
			UserAgent:  c.Request.UserAgent(),
			StatusCode: c.Writer.Status(),
			Duration:   duration,
		}

		// Add details for specific actions
		if action == AuditActionDelete && c.Writer.Status() == 200 {
			entry.Details = "resource deleted successfully"
		}

		logger.Log(entry)
	}
}

// methodToAction converts HTTP method to audit action
func methodToAction(method string) AuditAction {
	switch method {
	case "POST":
		return AuditActionCreate
	case "GET":
		return AuditActionRead
	case "PUT", "PATCH":
		return AuditActionUpdate
	case "DELETE":
		return AuditActionDelete
	default:
		return AuditActionRead
	}
}

// LogAuthEvent logs authentication-related events
func (a *AuditLogger) LogAuthEvent(userID, action, clientIP, userAgent, details string, success bool) {
	if !a.enabled {
		return
	}

	status := "success"
	if !success {
		status = "failure"
	}

	log.Printf("[AUDIT-AUTH] %s | user=%s | action=%s | ip=%s | user_agent=%s | status=%s | details=%s",
		time.Now().Format(time.RFC3339),
		userID,
		action,
		clientIP,
		userAgent,
		status,
		details,
	)
}

// LogSyncEvent logs sync-related events
func (a *AuditLogger) LogSyncEvent(userID, clientIP string, changesCount, deletedCount int, duration int64) {
	if !a.enabled {
		return
	}

	log.Printf("[AUDIT-SYNC] %s | user=%s | ip=%s | changes=%d | deleted=%d | duration=%dms",
		time.Now().Format(time.RFC3339),
		userID,
		clientIP,
		changesCount,
		deletedCount,
		duration,
	)
}
