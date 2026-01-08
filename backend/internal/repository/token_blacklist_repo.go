package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type TokenBlacklistRepository struct {
	pool *pgxpool.Pool
}

func NewTokenBlacklistRepository(pool *pgxpool.Pool) *TokenBlacklistRepository {
	return &TokenBlacklistRepository{pool: pool}
}

// RevokeToken adds a token ID to the blacklist
func (r *TokenBlacklistRepository) RevokeToken(ctx context.Context, tokenID string, userID uuid.UUID, expiresAt time.Time) error {
	query := `
		INSERT INTO token_blacklist (token_id, user_id, expires_at)
		VALUES ($1, $2, $3)
		ON CONFLICT (token_id) DO NOTHING
	`
	_, err := r.pool.Exec(ctx, query, tokenID, userID, expiresAt)
	return err
}

// IsTokenRevoked checks if a token ID is in the blacklist
func (r *TokenBlacklistRepository) IsTokenRevoked(ctx context.Context, tokenID string) (bool, error) {
	query := `SELECT EXISTS(SELECT 1 FROM token_blacklist WHERE token_id = $1)`
	var exists bool
	err := r.pool.QueryRow(ctx, query, tokenID).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}

// RevokeAllUserTokens revokes all tokens for a specific user by inserting a marker
// This is useful for "logout everywhere" or password change scenarios
func (r *TokenBlacklistRepository) RevokeAllUserTokens(ctx context.Context, userID uuid.UUID, beforeTime time.Time) error {
	// We store a special marker that indicates all tokens issued before this time are revoked
	// The token_id is a special format: "all:<user_id>:<timestamp>"
	markerID := "all:" + userID.String() + ":" + beforeTime.Format(time.RFC3339)
	query := `
		INSERT INTO token_blacklist (token_id, user_id, expires_at)
		VALUES ($1, $2, $3)
		ON CONFLICT (token_id) DO NOTHING
	`
	// Set expires_at far in the future for the marker (e.g., 30 days)
	expiresAt := time.Now().Add(30 * 24 * time.Hour)
	_, err := r.pool.Exec(ctx, query, markerID, userID, expiresAt)
	return err
}

// GetUserRevokeAllTime gets the latest "revoke all" timestamp for a user
// Returns zero time if no revoke-all marker exists
func (r *TokenBlacklistRepository) GetUserRevokeAllTime(ctx context.Context, userID uuid.UUID) (time.Time, error) {
	query := `
		SELECT MAX(revoked_at) FROM token_blacklist
		WHERE user_id = $1 AND token_id LIKE 'all:%'
	`
	var revokedAt *time.Time
	err := r.pool.QueryRow(ctx, query, userID).Scan(&revokedAt)
	if err != nil {
		return time.Time{}, err
	}
	if revokedAt == nil {
		return time.Time{}, nil
	}
	return *revokedAt, nil
}

// CleanupExpired removes expired tokens from the blacklist
// Should be called periodically (e.g., daily) to prevent table bloat
func (r *TokenBlacklistRepository) CleanupExpired(ctx context.Context) (int64, error) {
	result, err := r.pool.Exec(ctx, `DELETE FROM token_blacklist WHERE expires_at < NOW()`)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}
