package store

import (
	"ads-api/internal/model"
	"context"

	"github.com/jmoiron/sqlx"
)

type CampaignStore struct {
	db *sqlx.DB
}

func NewCampaignStore(db *sqlx.DB) *CampaignStore {
	return &CampaignStore{db: db}
}

func (s *CampaignStore) Create(ctx context.Context, c *model.Campaign) error {
	query := `
		INSERT INTO campaigns (user_id, name, status)
		VALUES (?, ?, ?)
	`
	res, err := s.db.ExecContext(ctx, query, c.UserID, c.Name, c.Status)
	if err != nil {
		return err
	}
	c.ID, _ = res.LastInsertId()
	return nil
}

func (s *CampaignStore) GetBYID(ctx context.Context, id int64) (*model.Campaign, error) {
	var c model.Campaign
	err := s.db.GetContext(ctx, &c, `
	SELECT id, user_id, name, status
	FROM campaigns
	WHERE id = ?
	`, id)
	if err != nil {
		return nil, err
	}
	return &c, nil
}
