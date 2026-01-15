package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/hamishgilbert/notes-app/backend/internal/middleware"
	"github.com/hamishgilbert/notes-app/backend/internal/services"
	ws "github.com/hamishgilbert/notes-app/backend/internal/websocket"
)

// WebSocket authentication protocol name
const wsAuthProtocol = "access_token"

type WebSocketHandler struct {
	hub            *ws.Hub
	authService    *services.AuthService
	upgrader       websocket.Upgrader
	allowedOrigins []string
}

func NewWebSocketHandler(hub *ws.Hub, authService *services.AuthService, allowedOrigins []string) *WebSocketHandler {
	h := &WebSocketHandler{
		hub:            hub,
		authService:    authService,
		allowedOrigins: allowedOrigins,
	}

	h.upgrader = websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin: func(r *http.Request) bool {
			origin := r.Header.Get("Origin")
			if origin == "" {
				// Allow requests without origin (non-browser clients)
				return true
			}
			return middleware.IsOriginAllowed(origin, h.allowedOrigins)
		},
		// Allow the access_token subprotocol for authentication
		Subprotocols: []string{wsAuthProtocol},
	}

	return h
}

// HandleWebSocket upgrades HTTP connection to WebSocket
func (h *WebSocketHandler) HandleWebSocket(c *gin.Context) {
	// Get token from (in order of preference):
	// 1. Sec-WebSocket-Protocol header (most secure - not logged, not in URL)
	// 2. Authorization header (Bearer token)
	token := ""
	useSubprotocol := false

	// Check Sec-WebSocket-Protocol header for token
	// Format: "access_token, <actual-token>"
	protocols := c.Request.Header.Get("Sec-WebSocket-Protocol")
	if protocols != "" {
		parts := strings.Split(protocols, ",")
		for i, part := range parts {
			part = strings.TrimSpace(part)
			if part == wsAuthProtocol && i+1 < len(parts) {
				// Next part is the token
				token = strings.TrimSpace(parts[i+1])
				useSubprotocol = true
				break
			}
		}
	}

	// Fallback to Authorization header
	if token == "" {
		authHeader := c.GetHeader("Authorization")
		if authHeader != "" {
			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) == 2 && strings.ToLower(parts[0]) == "bearer" {
				token = parts[1]
			}
		}
	}

	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing authentication token"})
		return
	}

	// Validate token
	userID, err := h.authService.ValidateTokenWithContext(c.Request.Context(), token)
	if err != nil {
		if err == services.ErrTokenRevoked {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "token has been revoked"})
		} else {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
		}
		return
	}

	// Prepare response headers for subprotocol
	var responseHeader http.Header
	if useSubprotocol {
		responseHeader = http.Header{}
		responseHeader.Set("Sec-WebSocket-Protocol", wsAuthProtocol)
	}

	// Upgrade to WebSocket
	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, responseHeader)
	if err != nil {
		// Upgrade already sends error response
		return
	}

	// Create client and register with hub
	client := ws.NewClient(h.hub, conn, userID)
	h.hub.Register(client)

	// Start read/write pumps in goroutines
	go client.WritePump()
	go client.ReadPump()
}
