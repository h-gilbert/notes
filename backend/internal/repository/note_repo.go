package repository

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/hamishgilbert/notes-app/backend/internal/models"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNoteNotFound = errors.New("note not found")

type NoteRepository struct {
	pool *pgxpool.Pool
}

func NewNoteRepository(pool *pgxpool.Pool) *NoteRepository {
	return &NoteRepository{pool: pool}
}

func (r *NoteRepository) Create(ctx context.Context, note *models.Note) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	query := `
		INSERT INTO notes (id, user_id, title, content, note_type, is_pinned, is_archived, sort_order, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
	`

	_, err = tx.Exec(ctx, query,
		note.ID,
		note.UserID,
		note.Title,
		note.Content,
		note.NoteType,
		note.IsPinned,
		note.IsArchived,
		note.SortOrder,
		note.CreatedAt,
		note.UpdatedAt,
	)
	if err != nil {
		return err
	}

	// Insert checklist items if any
	for _, item := range note.ChecklistItems {
		itemQuery := `
			INSERT INTO checklist_items (id, note_id, text, is_completed, sort_order, created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
		`
		_, err = tx.Exec(ctx, itemQuery,
			item.ID,
			note.ID,
			item.Text,
			item.IsCompleted,
			item.SortOrder,
			item.CreatedAt,
			item.UpdatedAt,
		)
		if err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

func (r *NoteRepository) GetByID(ctx context.Context, id uuid.UUID, userID uuid.UUID) (*models.Note, error) {
	query := `
		SELECT id, user_id, title, content, note_type, is_pinned, is_archived, sort_order, created_at, updated_at, deleted_at
		FROM notes WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
	`

	note := &models.Note{}
	err := r.pool.QueryRow(ctx, query, id, userID).Scan(
		&note.ID,
		&note.UserID,
		&note.Title,
		&note.Content,
		&note.NoteType,
		&note.IsPinned,
		&note.IsArchived,
		&note.SortOrder,
		&note.CreatedAt,
		&note.UpdatedAt,
		&note.DeletedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNoteNotFound
		}
		return nil, err
	}

	// Fetch checklist items
	items, err := r.getChecklistItems(ctx, note.ID)
	if err != nil {
		return nil, err
	}
	note.ChecklistItems = items

	return note, nil
}

func (r *NoteRepository) GetAllByUserID(ctx context.Context, userID uuid.UUID, since *time.Time) ([]models.Note, error) {
	var query string
	var args []interface{}

	if since != nil {
		query = `
			SELECT id, user_id, title, content, note_type, is_pinned, is_archived, sort_order, created_at, updated_at, deleted_at
			FROM notes WHERE user_id = $1 AND deleted_at IS NULL AND updated_at > $2
			ORDER BY sort_order ASC
		`
		args = []interface{}{userID, since}
	} else {
		query = `
			SELECT id, user_id, title, content, note_type, is_pinned, is_archived, sort_order, created_at, updated_at, deleted_at
			FROM notes WHERE user_id = $1 AND deleted_at IS NULL
			ORDER BY sort_order ASC
		`
		args = []interface{}{userID}
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var notes []models.Note
	for rows.Next() {
		var note models.Note
		err := rows.Scan(
			&note.ID,
			&note.UserID,
			&note.Title,
			&note.Content,
			&note.NoteType,
			&note.IsPinned,
			&note.IsArchived,
			&note.SortOrder,
			&note.CreatedAt,
			&note.UpdatedAt,
			&note.DeletedAt,
		)
		if err != nil {
			return nil, err
		}
		notes = append(notes, note)
	}

	// Fetch checklist items for all notes
	for i := range notes {
		items, err := r.getChecklistItems(ctx, notes[i].ID)
		if err != nil {
			return nil, err
		}
		notes[i].ChecklistItems = items
	}

	return notes, nil
}

func (r *NoteRepository) Update(ctx context.Context, note *models.Note) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	query := `
		UPDATE notes SET
			title = $1,
			content = $2,
			note_type = $3,
			is_pinned = $4,
			is_archived = $5,
			sort_order = $6,
			updated_at = $7
		WHERE id = $8 AND user_id = $9 AND deleted_at IS NULL
	`

	result, err := tx.Exec(ctx, query,
		note.Title,
		note.Content,
		note.NoteType,
		note.IsPinned,
		note.IsArchived,
		note.SortOrder,
		note.UpdatedAt,
		note.ID,
		note.UserID,
	)
	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		return ErrNoteNotFound
	}

	// Delete existing checklist items and re-insert
	_, err = tx.Exec(ctx, `DELETE FROM checklist_items WHERE note_id = $1`, note.ID)
	if err != nil {
		return err
	}

	for _, item := range note.ChecklistItems {
		itemQuery := `
			INSERT INTO checklist_items (id, note_id, text, is_completed, sort_order, created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
		`
		_, err = tx.Exec(ctx, itemQuery,
			item.ID,
			note.ID,
			item.Text,
			item.IsCompleted,
			item.SortOrder,
			item.CreatedAt,
			item.UpdatedAt,
		)
		if err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

func (r *NoteRepository) SoftDelete(ctx context.Context, id uuid.UUID, userID uuid.UUID) error {
	query := `
		UPDATE notes SET deleted_at = NOW(), updated_at = NOW()
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
	`

	result, err := r.pool.Exec(ctx, query, id, userID)
	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		return ErrNoteNotFound
	}

	return nil
}

func (r *NoteRepository) GetDeletedSince(ctx context.Context, userID uuid.UUID, since *time.Time) ([]uuid.UUID, error) {
	var query string
	var args []interface{}

	if since != nil {
		query = `
			SELECT id FROM notes
			WHERE user_id = $1 AND deleted_at IS NOT NULL AND deleted_at > $2
		`
		args = []interface{}{userID, since}
	} else {
		query = `
			SELECT id FROM notes
			WHERE user_id = $1 AND deleted_at IS NOT NULL
		`
		args = []interface{}{userID}
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}

	return ids, nil
}

func (r *NoteRepository) Upsert(ctx context.Context, note *models.Note) error {
	// Check if note exists
	existing, err := r.GetByID(ctx, note.ID, note.UserID)
	if err != nil && !errors.Is(err, ErrNoteNotFound) {
		return err
	}

	if existing != nil {
		// Only update if incoming is newer
		if note.UpdatedAt.After(existing.UpdatedAt) {
			return r.Update(ctx, note)
		}
		return nil
	}

	return r.Create(ctx, note)
}

func (r *NoteRepository) getChecklistItems(ctx context.Context, noteID uuid.UUID) ([]models.ChecklistItem, error) {
	query := `
		SELECT id, note_id, text, is_completed, sort_order, created_at, updated_at
		FROM checklist_items WHERE note_id = $1
		ORDER BY sort_order ASC
	`

	rows, err := r.pool.Query(ctx, query, noteID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []models.ChecklistItem
	for rows.Next() {
		var item models.ChecklistItem
		err := rows.Scan(
			&item.ID,
			&item.NoteID,
			&item.Text,
			&item.IsCompleted,
			&item.SortOrder,
			&item.CreatedAt,
			&item.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}

	return items, nil
}

// HardDeleteAllByUserID permanently deletes all notes for a user (used for demo account reset)
func (r *NoteRepository) HardDeleteAllByUserID(ctx context.Context, userID uuid.UUID) error {
	// Delete checklist items first (foreign key constraint)
	_, err := r.pool.Exec(ctx, `
		DELETE FROM checklist_items
		WHERE note_id IN (SELECT id FROM notes WHERE user_id = $1)
	`, userID)
	if err != nil {
		return err
	}

	// Delete notes
	_, err = r.pool.Exec(ctx, `DELETE FROM notes WHERE user_id = $1`, userID)
	return err
}
