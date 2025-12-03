package handlers

import (
	"encoding/json"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/hamishgilbert/notes-app/backend/internal/middleware"
	"github.com/hamishgilbert/notes-app/backend/internal/models"
	"github.com/hamishgilbert/notes-app/backend/internal/services"
	"github.com/hamishgilbert/notes-app/backend/internal/websocket"
	"github.com/hamishgilbert/notes-app/backend/pkg/response"
)

type SyncHandler struct {
	syncService *services.SyncService
	wsHub       *websocket.Hub
}

func NewSyncHandler(syncService *services.SyncService, wsHub *websocket.Hub) *SyncHandler {
	return &SyncHandler{
		syncService: syncService,
		wsHub:       wsHub,
	}
}

func (h *SyncHandler) Sync(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req models.SyncRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request body")
		return
	}

	// Get the connection ID from context to exclude sender from broadcasts
	connectionID, _ := c.Get("ws_connection_id")
	connID, _ := connectionID.(string)

	resp, err := h.syncService.Sync(c.Request.Context(), userID, &req)
	if err != nil {
		response.InternalError(c, "sync failed")
		return
	}

	// Broadcast changes to other WebSocket connections
	if h.wsHub != nil {
		// Broadcast updated/created notes
		for _, noteDTO := range req.Changes {
			h.broadcastNoteChange(userID, websocket.MessageTypeNoteUpdated, noteDTO, connID)
		}

		// Broadcast deletions
		for _, noteID := range req.DeletedIDs {
			h.broadcastNoteDelete(userID, noteID, connID)
		}
	}

	response.Success(c, resp)
}

// broadcastNoteChange sends a note updated message to all user's WebSocket connections except the sender
func (h *SyncHandler) broadcastNoteChange(userID uuid.UUID, msgType websocket.MessageType, note models.NoteDTO, excludeConnID string) {
	msg := websocket.WSMessage{
		Type: msgType,
		Payload: websocket.NoteChangePayload{
			Note: note,
		},
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return
	}

	h.wsHub.BroadcastToUser(userID, data, excludeConnID)
}

// broadcastNoteDelete sends a note deleted message to all user's WebSocket connections except the sender
func (h *SyncHandler) broadcastNoteDelete(userID uuid.UUID, noteID string, excludeConnID string) {
	msg := websocket.WSMessage{
		Type: websocket.MessageTypeNoteDeleted,
		Payload: websocket.NoteDeletePayload{
			NoteID: noteID,
		},
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return
	}

	h.wsHub.BroadcastToUser(userID, data, excludeConnID)
}
