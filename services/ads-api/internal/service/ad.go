package service

import (
	"ads-api/internal/model"
	"ads-api/internal/store"
	"context"
	"fmt"
	"log"
)

type AdService struct {
	store    *store.AdStore
	rabbitmq *RabbitMQService
}

func NewAdService(s *store.AdStore, rmq *RabbitMQService) *AdService {
	return &AdService{store: s, rabbitmq: rmq}
}

func (s *AdService) Create(ctx context.Context, ad *model.Ad) error {
	if err := normalizeAd(ad); err != nil {
		return err
	}
	if err := s.validatePlacement(ctx, ad); err != nil {
		return err
	}

	tx, err := s.store.BeginTx(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	if err := s.store.CreateTx(ctx, tx, ad); err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to create ad: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit ad: %w", err)
	}

	if s.rabbitmq != nil {
		if err := s.rabbitmq.PublishAdCreated(ctx, fmt.Sprintf("%d", ad.ID), ad.CampaignID); err != nil {
			log.Printf("Failed to publish ad_created event: %v", err)
		}
	}

	return nil
}

func (s *AdService) GetByID(ctx context.Context, id int64) (*model.Ad, error) {
	ad, err := s.store.GetByID(ctx, id)
	if err != nil {
		return nil, ErrNotFound
	}
	hydrateAdTargeting(ad)
	return ad, nil
}

func (s *AdService) ListByCampaign(ctx context.Context, campaignID int64) ([]model.Ad, error) {
	if campaignID <= 0 {
		return nil, ErrInvalidInput
	}
	items, err := s.store.ListByCampaign(ctx, campaignID)
	if err != nil {
		return nil, err
	}
	for index := range items {
		hydrateAdTargeting(&items[index])
	}
	return items, nil
}

func (s *AdService) Update(ctx context.Context, ad *model.Ad) error {
	if ad.ID <= 0 {
		return ErrNotFound
	}
	if err := normalizeAd(ad); err != nil {
		return err
	}
	if err := s.validatePlacement(ctx, ad); err != nil {
		return err
	}

	tx, err := s.store.BeginTx(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	if err := s.store.UpdateTx(ctx, tx, ad); err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to update ad: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit ad update: %w", err)
	}

	if s.rabbitmq != nil {
		if err := s.rabbitmq.PublishAdUpdated(ctx, fmt.Sprintf("%d", ad.ID), ad.CampaignID); err != nil {
			log.Printf("Failed to publish ad_updated event: %v", err)
		}
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
	if err := s.store.DeleteTx(ctx, tx, id); err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to delete ad: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit ad deletion: %w", err)
	}
	return nil
}

func (s *AdService) CreateWithBilling(ctx context.Context, ad *model.Ad, userID int64, amount float64) error {
	if err := normalizeAd(ad); err != nil {
		return err
	}
	if err := s.validatePlacement(ctx, ad); err != nil {
		return err
	}

	tx, err := s.store.BeginTx(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	if err := s.store.CreateTx(ctx, tx, ad); err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to create ad: %w", err)
	}

	log.Printf("Charging user %d for ad creation: %f", userID, amount)
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit billed ad: %w", err)
	}
	return nil
}

func (s *AdService) validatePlacement(ctx context.Context, ad *model.Ad) error {
	if ad.PlacementID == nil {
		return nil
	}
	if *ad.PlacementID <= 0 {
		return ErrInvalidInput
	}
	exists, err := s.store.PlacementBelongsToCampaignOwner(ctx, *ad.PlacementID, ad.CampaignID)
	if err != nil {
		return fmt.Errorf("validate placement: %w", err)
	}
	if !exists {
		return ErrInvalidInput
	}
	return nil
}
