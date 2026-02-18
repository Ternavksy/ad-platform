package store

import (
	"ads-api/internal/model"
	"context"

	"github.com/jmoiron/sqlx"
)

type AdStore struct {
	db *sqlx.DB
}

func NewAdStore(db *sqlx.DB) *AdStore {
	return &AdStore{db: db}
}

func (s *AdStore) Create(ctx context.Context, c *model.Ad) error {
	query := `
	INSERT INTO ads (campaign_id, title, status)
	VALUES (?, ?, ?)
	`
	res, err := s.db.ExecContext(ctx, query, c.CampaignID, c.Title, c.Status)
	if err != nil {
		return err
	}
	c.ID, _ = res.LastInsertId()
	return nil
}

func (s *AdStore) GetByID(ctx context.Context, id int64) (*model.Ad, error) {
	var ad model.Ad
	err := s.db.GetContext(ctx, &ad, `
	SELECT id, campaign_id, title, status
	FROM ads
	WHERE id = ?
	`, id)
	if err != nil {
		return nil, err
	}
	return &ad, nil
}

func (s *AdStore) Update(ctx context.Context, ad *model.Ad) error {
	query := `
		UPDATE ads
		SET title = ?, status = ?
		WHERE id = ?
	`
	_, err := s.db.ExecContext(ctx, query, ad.Title, ad.Status, ad.ID)
	return err
}

func (s *AdStore) Delete(ctx context.Context, id int64) error {
	query := `DELETE FROM ads WHERE id = ?`
	_, err := s.db.ExecContext(ctx, query, id)
	return err
}
