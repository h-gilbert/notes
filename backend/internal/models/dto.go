package models

// NoteDTO matches the iOS DTOModels.swift structure
type NoteDTO struct {
	ID             string             `json:"id"`
	Title          string             `json:"title"`
	Content        string             `json:"content"`
	NoteType       string             `json:"noteType"`
	IsPinned       bool               `json:"isPinned"`
	IsArchived     bool               `json:"isArchived"`
	SortOrder      int                `json:"sortOrder"`
	CreatedAt      string             `json:"createdAt"`
	UpdatedAt      string             `json:"updatedAt"`
	ChecklistItems []ChecklistItemDTO `json:"checklistItems,omitempty"`
}

type ChecklistItemDTO struct {
	ID          string `json:"id"`
	Text        string `json:"text"`
	IsCompleted bool   `json:"isCompleted"`
	SortOrder   int    `json:"sortOrder"`
	CreatedAt   string `json:"createdAt"`
	UpdatedAt   string `json:"updatedAt"`
}

type SyncRequest struct {
	Changes    []NoteDTO `json:"changes"`
	DeletedIDs []string  `json:"deletedIDs"`
	LastSync   *string   `json:"lastSync,omitempty"`
}

type SyncResponse struct {
	Notes           []NoteDTO `json:"notes"`
	DeletedNoteIDs  []string  `json:"deletedNoteIDs"`
	ServerTimestamp string    `json:"serverTimestamp"`
}

type AuthRequest struct {
	Username string `json:"username" binding:"required,min=3,max=50,alphanum"`
	Password string `json:"password" binding:"required,min=12,max=128"`
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

type LogoutRequest struct {
	RefreshToken string `json:"refresh_token,omitempty"`
}

type AuthResponse struct {
	AccessToken  string  `json:"access_token"`
	RefreshToken string  `json:"refresh_token"`
	ExpiresIn    int     `json:"expires_in"` // seconds until access token expires
	TokenType    string  `json:"token_type"` // always "Bearer"
	User         UserDTO `json:"user"`
}

type UserDTO struct {
	ID       string `json:"id"`
	Username string `json:"username"`
}

// NoteType enum values
const (
	NoteTypeText      = "text"
	NoteTypeChecklist = "checklist"
)

// ValidNoteTypes contains all valid note types
var ValidNoteTypes = map[string]bool{
	NoteTypeText:      true,
	NoteTypeChecklist: true,
}

// IsValidNoteType checks if the note type is valid
func IsValidNoteType(noteType string) bool {
	return ValidNoteTypes[noteType]
}

// MaxFieldLengths defines maximum lengths for various fields
const (
	MaxTitleLength   = 500
	MaxContentLength = 100000 // 100KB
	MaxItemTextLength = 1000
)
