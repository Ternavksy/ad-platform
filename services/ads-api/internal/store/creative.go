package store

import (
	"ads-api/internal/model"
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/jmoiron/sqlx"
)

type CreativeStore struct {
	db *sqlx.DB
}

var ErrModerationState = errors.New("invalid creative moderation state")

func NewCreativeStore(db *sqlx.DB) *CreativeStore {
	return &CreativeStore{db: db}
}

func (s *CreativeStore) Create(ctx context.Context, c *model.Creative) error {
	query := `
		INSERT INTO creatives (
			ad_id, content, media_type, media_url, media_path, mime_type, file_name, file_size,
			moderation_status, moderation_reason, submitted_at, reviewed_at, reviewed_by)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`
	res, err := s.db.ExecContext(ctx, query, c.AdID, c.Content, c.MediaType,
		c.MediaURL, c.MediaPath, c.MIMEType, c.FileName, c.FileSize,
		c.ModerationStatus, c.ModerationReason, c.SubmittedAt, c.ReviewedAt, c.ReviewedBy)
	if err != nil {
		return err
	}
	c.ID, _ = res.LastInsertId()
	return nil
}

func (s *CreativeStore) GetByID(ctx context.Context, id int64) (*model.Creative, error) {
	var c model.Creative
	err := s.db.GetContext(ctx, &c, `
		SELECT id, ad_id, content, media_type, media_url, media_path,
		       mime_type, file_name, file_size, moderation_status,
		       moderation_reason, submitted_at, reviewed_at, reviewed_by
		FROM creatives
		WHERE id = ?
	`, id)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (s *CreativeStore) ListByAd(ctx context.Context, adID int64) ([]model.Creative, error) {
	items := make([]model.Creative, 0)
	err := s.db.SelectContext(ctx, &items, `
		SELECT id, ad_id, content, media_type, media_url, media_path,
		       mime_type, file_name, file_size, moderation_status,
		       moderation_reason, submitted_at, reviewed_at, reviewed_by
		FROM creatives
		WHERE ad_id = ?
		ORDER BY id DESC
	`, adID)
	return items, err
}

func (s *CreativeStore) Update(ctx context.Context, creative *model.Creative) error {
	query := `
		UPDATE creatives
		SET content = ?, media_type = ?, media_url = ?, media_path = ?,
		    mime_type = ?, file_name = ?, file_size = ?,
		    moderation_status = ?, moderation_reason = ?, submitted_at = ?,
		    reviewed_at = ?, reviewed_by = ?
		WHERE id = ?
	`
	_, err := s.db.ExecContext(ctx, query, creative.Content, creative.MediaType,
		creative.MediaURL, creative.MediaPath, creative.MIMEType,
		creative.FileName, creative.FileSize, creative.ModerationStatus,
		creative.ModerationReason, creative.SubmittedAt, creative.ReviewedAt,
		creative.ReviewedBy, creative.ID)
	return err
}

func (s *CreativeStore) IsOwnedByUser(ctx context.Context, creativeID, userID int64) (bool, error) {
	var exists int
	err := s.db.GetContext(ctx, &exists, `
		SELECT EXISTS(
			SELECT 1
			FROM creatives cr
			JOIN ads a ON a.id = cr.ad_id
			JOIN campaigns c ON c.id = a.campaign_id
			WHERE cr.id = ? AND c.user_id = ?
		)
	`, creativeID, userID)
	return exists == 1, err
}

func (s *CreativeStore) SubmitForModeration(ctx context.Context, id int64, submittedAt time.Time) error {
	result, err := s.db.ExecContext(ctx, `
		UPDATE creatives
		SET moderation_status = 'pending', moderation_reason = '', submitted_at = ?,
		    reviewed_at = NULL, reviewed_by = NULL
		WHERE id = ? AND moderation_status IN ('draft', 'rejected')
	`, submittedAt, id)
	if err != nil {
		return err
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rows != 1 {
		return ErrModerationState
	}
	return nil
}

func (s *CreativeStore) ReviewModeration(
	ctx context.Context,
	id int64,
	status, reason string,
	reviewerID int64,
	reviewedAt time.Time,
) error {
	result, err := s.db.ExecContext(ctx, `
		UPDATE creatives
		SET moderation_status = ?, moderation_reason = ?, reviewed_at = ?, reviewed_by = ?
		WHERE id = ? AND moderation_status = 'pending'
	`, status, reason, reviewedAt, reviewerID, id)
	if err != nil {
		return err
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rows != 1 {
		return ErrModerationState
	}
	return nil
}

func (s *CreativeStore) ListForModeration(ctx context.Context, status string) ([]model.Creative, error) {
	items := make([]model.Creative, 0)
	err := s.db.SelectContext(ctx, &items, `
		SELECT cr.id, cr.ad_id, cr.content, cr.media_type, cr.media_url, cr.media_path,
		       cr.mime_type, cr.file_name, cr.file_size, cr.moderation_status,
		       cr.moderation_reason, cr.submitted_at, cr.reviewed_at, cr.reviewed_by,
		       a.title AS ad_title, c.name AS campaign_name, c.user_id AS owner_user_id
		FROM creatives cr
		JOIN ads a ON a.id = cr.ad_id
		JOIN campaigns c ON c.id = a.campaign_id
		WHERE cr.moderation_status = ?
		ORDER BY COALESCE(cr.submitted_at, cr.reviewed_at) DESC, cr.id DESC
	`, status)
	return items, err
}

func (s *CreativeStore) Exists(ctx context.Context, id int64) (bool, error) {
	var value int64
	err := s.db.GetContext(ctx, &value, `SELECT id FROM creatives WHERE id = ?`, id)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

func (s *CreativeStore) Delete(ctx context.Context, id int64) error {
	query := `DELETE FROM creatives WHERE id = ?`
	_, err := s.db.ExecContext(ctx, query, id)
	return err
}
