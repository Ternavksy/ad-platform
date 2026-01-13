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
