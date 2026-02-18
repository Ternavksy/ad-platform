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

func (s *CampaignStore) GetByID(ctx context.Context, id int64) (*model.Campaign, error) {
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

func (s *CampaignStore) Update(ctx context.Context, c *model.Campaign) error {
	query := `
		UPDATE campaigns
		SET name = ?, status = ?
		WHERE id = ?
	`
	_, err := s.db.ExecContext(ctx, query, c.Name, c.Status, c.ID)
	return err
}

func (s *CampaignStore) Delete(ctx context.Context, id int64) error {
	query := `DELETE FROM campaigns WHERE id = ?`
	_, err := s.db.ExecContext(ctx, query, id)
	return err
}
