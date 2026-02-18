package service

import (
	"ads-api/internal/model"
	"ads-api/internal/store"
	"context"
)

type AdService struct {
	store *store.AdStore
}

func NewAdService(s *store.AdStore) *AdService {
	return &AdService{store: s}
}

func (s *AdService) Create(ctx context.Context, ad *model.Ad) error {
	if ad.Title == "" {
		return ErrInvalidInput
	}
	return s.store.Create(ctx, ad)
}

func (s *AdService) GetByID(ctx context.Context, id int64) (*model.Ad, error) {
	ad, err := s.store.GetByID(ctx, id)
	if err != nil {
		return nil, ErrNotFound
	}
	return ad, nil
}

func (s *AdService) Update(ctx context.Context, ad *model.Ad) error {
	if ad.ID <= 0 {
		return ErrNotFound
	}
	if ad.Title == "" {
		return ErrInvalidInput
	}
	return s.store.Update(ctx, ad)
}

func (s *AdService) Delete(ctx context.Context, id int64) error {
	if id <= 0 {
		return ErrNotFound
	}
	return s.store.Delete(ctx, id)
}
