package models

import (
	"time"

	"github.com/google/uuid"
)

type ChecklistItem struct {
	ID          uuid.UUID `json:"id"`
	NoteID      uuid.UUID `json:"noteId"`
	Text        string    `json:"text"`
	IsCompleted bool      `json:"isCompleted"`
	SortOrder   int       `json:"sortOrder"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}
