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
	}

	return h
}

// HandleWebSocket upgrades HTTP connection to WebSocket
func (h *WebSocketHandler) HandleWebSocket(c *gin.Context) {
	// Get token from query param or Authorization header
	token := c.Query("token")
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
	userID, err := h.authService.ValidateToken(token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
		return
	}

	// Upgrade to WebSocket
	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
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
