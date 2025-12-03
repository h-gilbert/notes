package websocket

import "github.com/hamishgilbert/notes-app/backend/internal/models"

type MessageType string

const (
	MessageTypeNoteCreated  MessageType = "note_created"
	MessageTypeNoteUpdated  MessageType = "note_updated"
	MessageTypeNoteDeleted  MessageType = "note_deleted"
	MessageTypeSyncRequest  MessageType = "sync_request"
	MessageTypeSyncResponse MessageType = "sync_response"
	MessageTypePing         MessageType = "ping"
	MessageTypePong         MessageType = "pong"
)

// WSMessage is the envelope for all WebSocket messages
type WSMessage struct {
	Type    MessageType `json:"type"`
	Payload interface{} `json:"payload,omitempty"`
}

// NoteChangePayload is sent when a note is created or updated
type NoteChangePayload struct {
	Note models.NoteDTO `json:"note"`
}

// NoteDeletePayload is sent when a note is deleted
type NoteDeletePayload struct {
	NoteID string `json:"noteId"`
}

// SyncRequestPayload is sent by clients to request a sync
type SyncRequestPayload struct {
	Since string `json:"since,omitempty"`
}
