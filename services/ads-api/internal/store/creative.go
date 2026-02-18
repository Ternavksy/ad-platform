package store

import (
	"ads-api/internal/model"
	"context"

	"github.com/jmoiron/sqlx"
)

type CreativeStore struct {
	db *sqlx.DB
}

func NewCreativeStore(db *sqlx.DB) *CreativeStore {
	return &CreativeStore{db: db}
}

func (s *CreativeStore) Create(ctx context.Context, c *model.Creative) error {
	query := `
		INSERT INTO creatives (ad_id, content)
		VALUES (?, ?)
	`
	res, err := s.db.ExecContext(ctx, query, c.AdID, c.Content)
	if err != nil {
		return err
	}
	c.ID, _ = res.LastInsertId()
	return nil
}

func (s *CreativeStore) GetByID(ctx context.Context, id int64) (*model.Creative, error) {
	var c model.Creative
	err := s.db.GetContext(ctx, &c, `
		SELECT id, ad_id, content
		FROM creatives
		WHERE id = ?
	`, id)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (s *CreativeStore) Update(ctx context.Context, creative *model.Creative) error {
	query := `
		UPDATE creatives
		SET content = ?
		WHERE id = ?
	`
	_, err := s.db.ExecContext(ctx, query, creative.Content, creative.ID)
	return err
}

func (s *CreativeStore) Delete(ctx context.Context, id int64) error {
	query := `DELETE FROM creatives WHERE id = ?`
	_, err := s.db.ExecContext(ctx, query, id)
	return err
}
