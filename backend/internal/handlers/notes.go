package handlers

import (
	"encoding/json"
	"errors"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/hamishgilbert/notes-app/backend/internal/middleware"
	"github.com/hamishgilbert/notes-app/backend/internal/models"
	"github.com/hamishgilbert/notes-app/backend/internal/repository"
	"github.com/hamishgilbert/notes-app/backend/internal/services"
	"github.com/hamishgilbert/notes-app/backend/internal/websocket"
	"github.com/hamishgilbert/notes-app/backend/pkg/response"
)

type NotesHandler struct {
	noteRepo    *repository.NoteRepository
	syncService *services.SyncService
	wsHub       *websocket.Hub
}

func NewNotesHandler(noteRepo *repository.NoteRepository, syncService *services.SyncService, wsHub *websocket.Hub) *NotesHandler {
	return &NotesHandler{
		noteRepo:    noteRepo,
		syncService: syncService,
		wsHub:       wsHub,
	}
}

func (h *NotesHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var since *time.Time
	if sinceStr := c.Query("since"); sinceStr != "" {
		t, err := time.Parse(services.ISO8601Format, sinceStr)
		if err == nil {
			since = &t
		}
	}

	notes, err := h.noteRepo.GetAllByUserID(c.Request.Context(), userID, since)
	if err != nil {
		response.InternalError(c, "failed to fetch notes")
		return
	}

	// Also get deleted notes since
	deletedIDs, err := h.noteRepo.GetDeletedSince(c.Request.Context(), userID, since)
	if err != nil {
		response.InternalError(c, "failed to fetch deleted notes")
		return
	}

	noteDTOs := make([]models.NoteDTO, len(notes))
	for i, note := range notes {
		noteDTOs[i] = h.syncService.NoteToDTO(&note)
	}

	deletedIDStrings := make([]string, len(deletedIDs))
	for i, id := range deletedIDs {
		deletedIDStrings[i] = id.String()
	}

	response.Success(c, models.SyncResponse{
		Notes:           noteDTOs,
		DeletedNoteIDs:  deletedIDStrings,
		ServerTimestamp: time.Now().UTC().Format(services.ISO8601Format),
	})
}

func (h *NotesHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var dto models.NoteDTO
	if err := c.ShouldBindJSON(&dto); err != nil {
		response.BadRequest(c, "invalid request body")
		return
	}

	// Generate new ID if not provided
	if dto.ID == "" {
		dto.ID = uuid.New().String()
	}

	// Set timestamps if not provided
	now := time.Now().UTC().Format(services.ISO8601Format)
	if dto.CreatedAt == "" {
		dto.CreatedAt = now
	}
	if dto.UpdatedAt == "" {
		dto.UpdatedAt = now
	}

	note, err := h.syncService.DTOToNote(dto, userID)
	if err != nil {
		response.BadRequest(c, "invalid note data")
		return
	}

	if err := h.noteRepo.Create(c.Request.Context(), note); err != nil {
		response.InternalError(c, "failed to create note")
		return
	}

	noteDTO := h.syncService.NoteToDTO(note)

	// Broadcast to other connections
	h.broadcastNoteChange(userID, websocket.MessageTypeNoteCreated, noteDTO)

	response.Created(c, noteDTO)
}

func (h *NotesHandler) Get(c *gin.Context) {
	userID := middleware.GetUserID(c)

	noteID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.BadRequest(c, "invalid note ID")
		return
	}

	note, err := h.noteRepo.GetByID(c.Request.Context(), noteID, userID)
	if err != nil {
		if errors.Is(err, repository.ErrNoteNotFound) {
			response.NotFound(c, "note not found")
			return
		}
		response.InternalError(c, "failed to fetch note")
		return
	}

	response.Success(c, h.syncService.NoteToDTO(note))
}

func (h *NotesHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)

	noteID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.BadRequest(c, "invalid note ID")
		return
	}

	var dto models.NoteDTO
	if err := c.ShouldBindJSON(&dto); err != nil {
		response.BadRequest(c, "invalid request body")
		return
	}

	// Ensure ID matches URL
	dto.ID = noteID.String()

	// Update timestamp
	dto.UpdatedAt = time.Now().UTC().Format(services.ISO8601Format)

	note, err := h.syncService.DTOToNote(dto, userID)
	if err != nil {
		response.BadRequest(c, "invalid note data")
		return
	}

	if err := h.noteRepo.Update(c.Request.Context(), note); err != nil {
		if errors.Is(err, repository.ErrNoteNotFound) {
			response.NotFound(c, "note not found")
			return
		}
		response.InternalError(c, "failed to update note")
		return
	}

	noteDTO := h.syncService.NoteToDTO(note)

	// Broadcast to other connections
	h.broadcastNoteChange(userID, websocket.MessageTypeNoteUpdated, noteDTO)

	response.Success(c, noteDTO)
}

func (h *NotesHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)

	noteID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		response.BadRequest(c, "invalid note ID")
		return
	}

	if err := h.noteRepo.SoftDelete(c.Request.Context(), noteID, userID); err != nil {
		if errors.Is(err, repository.ErrNoteNotFound) {
			response.NotFound(c, "note not found")
			return
		}
		response.InternalError(c, "failed to delete note")
		return
	}

	// Broadcast deletion to other connections
	h.broadcastNoteDelete(userID, noteID.String())

	response.NoContent(c)
}

// broadcastNoteChange sends a note created/updated message to all user's WebSocket connections
func (h *NotesHandler) broadcastNoteChange(userID uuid.UUID, msgType websocket.MessageType, note models.NoteDTO) {
	if h.wsHub == nil {
		return
	}

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

	h.wsHub.BroadcastToUser(userID, data, "")
}

// broadcastNoteDelete sends a note deleted message to all user's WebSocket connections
func (h *NotesHandler) broadcastNoteDelete(userID uuid.UUID, noteID string) {
	if h.wsHub == nil {
		return
	}

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

	h.wsHub.BroadcastToUser(userID, data, "")
}
