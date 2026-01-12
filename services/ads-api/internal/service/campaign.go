package service

import (
	"ads-api/internal/model"
	"ads-api/internal/store"
	"context"
	"errors"
)

type CampaignService struct {
	store *store.CampaignStore
}

func NewCampaignService(s *store.CampaignStore) *CampaignService {
	return &CampaignService{store: s}
}

func (s *CampaignService) Create(ctx context.Context, c *model.Campaign) error {
	if c.Name == "" {
		return errors.New("campaign name required")
	}
	return s.store.Create(ctx, c)
}

func (s *CampaignService) GetByID(ctx context.Context, id int64) (*model.Campaign, error) {
	if id <= 0 {
		return nil, ErrNotFound
	}
	return s.store.GetByID(ctx, id)
}
