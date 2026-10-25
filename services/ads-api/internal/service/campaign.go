package service

import (
	"ads-api/internal/model"
	"ads-api/internal/store"
	"context"
	"time"
)

type CampaignService struct {
	store *store.CampaignStore
}

func NewCampaignService(s *store.CampaignStore) *CampaignService {
	return &CampaignService{store: s}
}

func (s *CampaignService) Create(ctx context.Context, c *model.Campaign) error {
	if err := normalizeCampaign(c, nil); err != nil {
		return err
	}
	return s.store.Create(ctx, c)
}

func (s *CampaignService) GetByID(ctx context.Context, id int64) (*model.Campaign, error) {
	if id <= 0 {
		return nil, ErrNotFound
	}
	item, err := s.store.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	hydrateCampaign(item, time.Now().UTC())
	return item, nil
}

func (s *CampaignService) ListByUser(ctx context.Context, userID int64) ([]model.Campaign, error) {
	if userID <= 0 {
		return nil, ErrInvalidInput
	}
	items, err := s.store.ListByUser(ctx, userID)
	if err != nil {
		return nil, err
	}
	now := time.Now().UTC()
	for index := range items {
		hydrateCampaign(&items[index], now)
	}
	return items, nil
}

func (s *CampaignService) Update(ctx context.Context, c *model.Campaign) error {
	if c.ID <= 0 {
		return ErrNotFound
	}
	current, err := s.store.GetByID(ctx, c.ID)
	if err != nil {
		return ErrNotFound
	}
	if err := normalizeCampaign(c, current); err != nil {
		return err
	}
	return s.store.Update(ctx, c)
}

func (s *CampaignService) Delete(ctx context.Context, id int64) error {
	if id <= 0 {
		return ErrNotFound
	}
	return s.store.Delete(ctx, id)
}
