package services

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/hamishgilbert/notes-app/backend/internal/models"
	"github.com/hamishgilbert/notes-app/backend/internal/repository"
)

const ISO8601Format = "2006-01-02T15:04:05.000Z"

type SyncService struct {
	noteRepo *repository.NoteRepository
}

func NewSyncService(noteRepo *repository.NoteRepository) *SyncService {
	return &SyncService{noteRepo: noteRepo}
}

func (s *SyncService) Sync(ctx context.Context, userID uuid.UUID, req *models.SyncRequest) (*models.SyncResponse, error) {
	// Parse lastSync time
	var lastSync *time.Time
	if req.LastSync != nil && *req.LastSync != "" {
		t, err := time.Parse(ISO8601Format, *req.LastSync)
		if err == nil {
			lastSync = &t
		}
	}

	// Process incoming changes (upsert)
	for _, dto := range req.Changes {
		note, err := s.dtoToNote(dto, userID)
		if err != nil {
			continue // Skip invalid notes
		}
		if err := s.noteRepo.Upsert(ctx, note); err != nil {
			return nil, err
		}
	}

	// Process deletions
	for _, idStr := range req.DeletedIDs {
		id, err := uuid.Parse(idStr)
		if err != nil {
			continue
		}
		// Soft delete - ignore errors for non-existent notes
		_ = s.noteRepo.SoftDelete(ctx, id, userID)
	}

	// Fetch notes updated since lastSync
	notes, err := s.noteRepo.GetAllByUserID(ctx, userID, lastSync)
	if err != nil {
		return nil, err
	}

	// Fetch deleted note IDs since lastSync
	deletedIDs, err := s.noteRepo.GetDeletedSince(ctx, userID, lastSync)
	if err != nil {
		return nil, err
	}

	// Convert to DTOs
	noteDTOs := make([]models.NoteDTO, len(notes))
	for i, note := range notes {
		noteDTOs[i] = s.noteToDTO(&note)
	}

	deletedIDStrings := make([]string, len(deletedIDs))
	for i, id := range deletedIDs {
		deletedIDStrings[i] = id.String()
	}

	return &models.SyncResponse{
		Notes:           noteDTOs,
		DeletedNoteIDs:  deletedIDStrings,
		ServerTimestamp: time.Now().UTC().Format(ISO8601Format),
	}, nil
}

func (s *SyncService) noteToDTO(note *models.Note) models.NoteDTO {
	dto := models.NoteDTO{
		ID:         note.ID.String(),
		Title:      note.Title,
		Content:    note.Content,
		NoteType:   string(note.NoteType),
		IsPinned:   note.IsPinned,
		IsArchived: note.IsArchived,
		SortOrder:  note.SortOrder,
		CreatedAt:  note.CreatedAt.UTC().Format(ISO8601Format),
		UpdatedAt:  note.UpdatedAt.UTC().Format(ISO8601Format),
	}

	if len(note.ChecklistItems) > 0 {
		dto.ChecklistItems = make([]models.ChecklistItemDTO, len(note.ChecklistItems))
		for i, item := range note.ChecklistItems {
			dto.ChecklistItems[i] = models.ChecklistItemDTO{
				ID:          item.ID.String(),
				Text:        item.Text,
				IsCompleted: item.IsCompleted,
				SortOrder:   item.SortOrder,
				CreatedAt:   item.CreatedAt.UTC().Format(ISO8601Format),
				UpdatedAt:   item.UpdatedAt.UTC().Format(ISO8601Format),
			}
		}
	}

	return dto
}

func (s *SyncService) dtoToNote(dto models.NoteDTO, userID uuid.UUID) (*models.Note, error) {
	id, err := uuid.Parse(dto.ID)
	if err != nil {
		return nil, err
	}

	createdAt, err := time.Parse(ISO8601Format, dto.CreatedAt)
	if err != nil {
		createdAt = time.Now()
	}

	updatedAt, err := time.Parse(ISO8601Format, dto.UpdatedAt)
	if err != nil {
		updatedAt = time.Now()
	}

	note := &models.Note{
		ID:         id,
		UserID:     userID,
		Title:      dto.Title,
		Content:    dto.Content,
		NoteType:   models.NoteType(dto.NoteType),
		IsPinned:   dto.IsPinned,
		IsArchived: dto.IsArchived,
		SortOrder:  dto.SortOrder,
		CreatedAt:  createdAt,
		UpdatedAt:  updatedAt,
	}

	// Convert checklist items
	if len(dto.ChecklistItems) > 0 {
		note.ChecklistItems = make([]models.ChecklistItem, len(dto.ChecklistItems))
		for i, itemDTO := range dto.ChecklistItems {
			itemID, err := uuid.Parse(itemDTO.ID)
			if err != nil {
				itemID = uuid.New()
			}

			itemCreatedAt, err := time.Parse(ISO8601Format, itemDTO.CreatedAt)
			if err != nil {
				itemCreatedAt = time.Now()
			}

			itemUpdatedAt, err := time.Parse(ISO8601Format, itemDTO.UpdatedAt)
			if err != nil {
				itemUpdatedAt = time.Now()
			}

			note.ChecklistItems[i] = models.ChecklistItem{
				ID:          itemID,
				NoteID:      note.ID,
				Text:        itemDTO.Text,
				IsCompleted: itemDTO.IsCompleted,
				SortOrder:   itemDTO.SortOrder,
				CreatedAt:   itemCreatedAt,
				UpdatedAt:   itemUpdatedAt,
			}
		}
	}

	return note, nil
}

// NoteToDTO is exported for handlers
func (s *SyncService) NoteToDTO(note *models.Note) models.NoteDTO {
	return s.noteToDTO(note)
}

// DTOToNote is exported for handlers
func (s *SyncService) DTOToNote(dto models.NoteDTO, userID uuid.UUID) (*models.Note, error) {
	return s.dtoToNote(dto, userID)
}
