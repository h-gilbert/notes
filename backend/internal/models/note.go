package models

import (
	"time"

	"github.com/google/uuid"
)

type NoteType string

const (
	NoteTypeNote      NoteType = "note"
	NoteTypeChecklist NoteType = "checklist"
)

type Note struct {
	ID             uuid.UUID       `json:"id"`
	UserID         uuid.UUID       `json:"userId"`
	Title          string          `json:"title"`
	Content        string          `json:"content"`
	NoteType       NoteType        `json:"noteType"`
	IsPinned       bool            `json:"isPinned"`
	IsArchived     bool            `json:"isArchived"`
	SortOrder      int             `json:"sortOrder"`
	CreatedAt      time.Time       `json:"createdAt"`
	UpdatedAt      time.Time       `json:"updatedAt"`
	DeletedAt      *time.Time      `json:"deletedAt,omitempty"`
	ChecklistItems []ChecklistItem `json:"checklistItems,omitempty"`
}
