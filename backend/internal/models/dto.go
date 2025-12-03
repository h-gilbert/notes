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
	Username string `json:"username" binding:"required,min=3,max=50"`
	Password string `json:"password" binding:"required,min=6"`
}

type AuthResponse struct {
	Token string  `json:"token"`
	User  UserDTO `json:"user"`
}

type UserDTO struct {
	ID       string `json:"id"`
	Username string `json:"username"`
}
