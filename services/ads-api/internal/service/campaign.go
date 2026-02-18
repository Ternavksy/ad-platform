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

func (s *CampaignService) Update(ctx context.Context, c *model.Campaign) error {
	if c.ID <= 0 {
		return ErrNotFound
	}
	if c.Name == "" {
		return errors.New("campaign name required")
	}
	return s.store.Update(ctx, c)
}

func (s *CampaignService) Delete(ctx context.Context, id int64) error {
	if id <= 0 {
		return ErrNotFound
	}
	return s.store.Delete(ctx, id)
}
