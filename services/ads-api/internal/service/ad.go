package service

import (
	"ads-api/internal/model"
	"ads-api/internal/store"
	"context"
	"fmt"
	"log"
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

	tx, err := s.store.BeginTx(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer func() {
		if p := recover(); p != nil {
			tx.Rollback()
			panic(p)
		} else if err != nil {
			tx.Rollback()
		} else {
			err = tx.Commit()
		}
	}()

	if err = s.store.CreateTx(ctx, tx, ad); err != nil {
		return fmt.Errorf("failed to create ad: %w", err)
	}

	return nil
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

	tx, err := s.store.BeginTx(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer func() {
		if p := recover(); p != nil {
			tx.Rollback()
			panic(p)
		} else if err != nil {
			tx.Rollback()
		} else {
			err = tx.Commit()
		}
	}()

	if err = s.store.UpdateTx(ctx, tx, ad); err != nil {
		return fmt.Errorf("failed to update ad: %w", err)
	}

	return nil
}

func (s *AdService) Delete(ctx context.Context, id int64) error {
	if id <= 0 {
		return ErrNotFound
	}

	tx, err := s.store.BeginTx(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer func() {
		if p := recover(); p != nil {
			tx.Rollback()
			panic(p)
		} else if err != nil {
			tx.Rollback()
		} else {
			err = tx.Commit()
		}
	}()

	if err = s.store.DeleteTx(ctx, tx, id); err != nil {
		return fmt.Errorf("failed to delete ad: %w", err)
	}

	return nil
}

func (s *AdService) CreateWithBilling(ctx context.Context, ad *model.Ad, userID int64, amount float64) error {
	if ad.Title == "" {
		return ErrInvalidInput
	}

	tx, err := s.store.BeginTx(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer func() {
		if p := recover(); p != nil {
			tx.Rollback()
			panic(p)
		} else if err != nil {
			tx.Rollback()
		} else {
			err = tx.Commit()
		}
	}()

	if err = s.store.CreateTx(ctx, tx, ad); err != nil {
		return fmt.Errorf("failed to create ad: %w", err)
	}

	log.Printf("Charging user %d for ad creation: %f", userID, amount)

	return nil
}
