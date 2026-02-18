package service

import (
	"ads-api/internal/model"
	"ads-api/internal/store"
	"context"
)

type CreativeService struct {
	store *store.CreativeStore
}

func NewCreativeService(s *store.CreativeStore) *CreativeService {
	return &CreativeService{store: s}
}

func (s *CreativeService) Create(ctx context.Context, c *model.Creative) error {
	if c.AdID == 0 || c.Content == "" {
		return ErrInvalidInput
	}
	return s.store.Create(ctx, c)
}

func (s *CreativeService) GetByID(ctx context.Context, id int64) (*model.Creative, error) {
	creative, err := s.store.GetByID(ctx, id)
	if err != nil {
		return nil, ErrNotFound
	}
	return creative, nil
}

func (s *CreativeService) Update(ctx context.Context, creative *model.Creative) error {
	if creative.ID <= 0 {
		return ErrNotFound
	}
	if creative.Content == "" {
		return ErrInvalidInput
	}
	return s.store.Update(ctx, creative)
}

func (s *CreativeService) Delete(ctx context.Context, id int64) error {
	if id <= 0 {
		return ErrNotFound
	}
	return s.store.Delete(ctx, id)
}
