package service

import (
	"ads-api/internal/model"
	"ads-api/internal/store"
	"context"
	"errors"
	"fmt"
	"log"
	"mime/multipart"
	"strings"
	"time"
)

type CreativeService struct {
	store   *store.CreativeStore
	storage *MediaStorage
}

func NewCreativeService(s *store.CreativeStore) *CreativeService {
	return NewCreativeServiceWithStorage(s, NewMediaStorage("/data/media"))
}

func NewCreativeServiceWithStorage(s *store.CreativeStore, storage *MediaStorage) *CreativeService {
	return &CreativeService{store: s, storage: storage}
}

func (s *CreativeService) Create(ctx context.Context, c *model.Creative) error {
	c.MediaType = "text"
	resetModeration(c)
	if err := normalizeCreative(c); err != nil {
		return err
	}
	return s.store.Create(ctx, c)
}

func (s *CreativeService) CreateWithMedia(ctx context.Context, c *model.Creative, file *multipart.FileHeader) error {
	media, storedPath, err := s.storage.Save(file)
	if err != nil {
		return err
	}
	setCreativeMedia(c, media, storedPath)
	resetModeration(c)
	if err := normalizeCreative(c); err != nil {
		_ = s.storage.Remove(storedPath)
		return err
	}
	if err := s.store.Create(ctx, c); err != nil {
		_ = s.storage.Remove(storedPath)
		return err
	}
	return nil
}

func (s *CreativeService) GetByID(ctx context.Context, id int64) (*model.Creative, error) {
	creative, err := s.store.GetByID(ctx, id)
	if err != nil {
		return nil, ErrNotFound
	}
	hydrateCreative(creative)
	return creative, nil
}

func (s *CreativeService) ListByAd(ctx context.Context, adID int64) ([]model.Creative, error) {
	if adID <= 0 {
		return nil, ErrInvalidInput
	}
	items, err := s.store.ListByAd(ctx, adID)
	if err != nil {
		return nil, err
	}
	for index := range items {
		hydrateCreative(&items[index])
	}
	return items, nil
}

func (s *CreativeService) Update(ctx context.Context, creative *model.Creative) error {
	if creative.ID <= 0 {
		return ErrNotFound
	}
	current, err := s.store.GetByID(ctx, creative.ID)
	if err != nil {
		return ErrNotFound
	}
	creative.AdID = current.AdID
	creative.MediaType = current.MediaType
	creative.MediaURL = current.MediaURL
	creative.MediaPath = current.MediaPath
	creative.MIMEType = current.MIMEType
	creative.FileName = current.FileName
	creative.FileSize = current.FileSize
	resetModeration(creative)
	if err := normalizeCreative(creative); err != nil {
		return err
	}
	return s.store.Update(ctx, creative)
}

func (s *CreativeService) UpdateWithMedia(ctx context.Context, creative *model.Creative, file *multipart.FileHeader) error {
	if creative.ID <= 0 {
		return ErrNotFound
	}
	current, err := s.store.GetByID(ctx, creative.ID)
	if err != nil {
		return ErrNotFound
	}
	media, storedPath, err := s.storage.Save(file)
	if err != nil {
		return err
	}
	creative.AdID = current.AdID
	setCreativeMedia(creative, media, storedPath)
	resetModeration(creative)
	if err := normalizeCreative(creative); err != nil {
		_ = s.storage.Remove(storedPath)
		return err
	}
	if err := s.store.Update(ctx, creative); err != nil {
		_ = s.storage.Remove(storedPath)
		return err
	}
	if err := s.storage.Remove(current.MediaPath); err != nil {
		log.Printf("remove replaced media %q: %v", current.MediaPath, err)
	}
	return nil
}

func (s *CreativeService) Delete(ctx context.Context, id int64) error {
	if id <= 0 {
		return ErrNotFound
	}
	creative, err := s.store.GetByID(ctx, id)
	if err != nil {
		return ErrNotFound
	}
	if err := s.store.Delete(ctx, id); err != nil {
		return err
	}
	if err := s.storage.Remove(creative.MediaPath); err != nil {
		log.Printf("remove creative media %q: %v", creative.MediaPath, err)
	}
	return nil
}

func (s *CreativeService) SubmitForModeration(
	ctx context.Context,
	id, userID int64,
	isAdmin bool,
) (*model.Creative, error) {
	if id <= 0 || userID <= 0 {
		return nil, ErrNotFound
	}
	if !isAdmin {
		owned, err := s.store.IsOwnedByUser(ctx, id, userID)
		if err != nil {
			return nil, err
		}
		if !owned {
			return nil, ErrForbidden
		}
	}
	if err := s.store.SubmitForModeration(ctx, id, time.Now().UTC()); err != nil {
		return nil, s.moderationError(ctx, id, err)
	}
	return s.GetByID(ctx, id)
}

func (s *CreativeService) ListForModeration(ctx context.Context, status string) ([]model.Creative, error) {
	status = strings.TrimSpace(strings.ToLower(status))
	if status == "" {
		status = "pending"
	}
	if !isModerationStatus(status) {
		return nil, ErrInvalidInput
	}
	items, err := s.store.ListForModeration(ctx, status)
	if err != nil {
		return nil, err
	}
	for index := range items {
		hydrateCreative(&items[index])
	}
	return items, nil
}

func (s *CreativeService) ReviewModeration(
	ctx context.Context,
	id, reviewerID int64,
	decision model.ModerationDecision,
) (*model.Creative, error) {
	decision.Decision = strings.TrimSpace(strings.ToLower(decision.Decision))
	decision.Reason = strings.TrimSpace(decision.Reason)
	if id <= 0 || reviewerID <= 0 ||
		(decision.Decision != "approved" && decision.Decision != "rejected") ||
		len(decision.Reason) > 500 ||
		(decision.Decision == "rejected" && decision.Reason == "") {
		return nil, ErrInvalidInput
	}
	if decision.Decision == "approved" {
		decision.Reason = ""
	}
	if err := s.store.ReviewModeration(
		ctx,
		id,
		decision.Decision,
		decision.Reason,
		reviewerID,
		time.Now().UTC(),
	); err != nil {
		return nil, s.moderationError(ctx, id, err)
	}
	return s.GetByID(ctx, id)
}

func (s *CreativeService) moderationError(ctx context.Context, id int64, err error) error {
	if !errors.Is(err, store.ErrModerationState) {
		return err
	}
	exists, existsErr := s.store.Exists(ctx, id)
	if existsErr != nil {
		return existsErr
	}
	if !exists {
		return ErrNotFound
	}
	return fmt.Errorf("creative cannot transition from its current moderation status: %w", ErrConflict)
}

func normalizeCreative(creative *model.Creative) error {
	creative.Content = strings.TrimSpace(creative.Content)
	if creative.AdID <= 0 || len(creative.Content) > 1024 {
		return ErrInvalidInput
	}
	if creative.MediaType == "" {
		creative.MediaType = "text"
	}
	if creative.MediaType != "text" && creative.MediaType != "image" && creative.MediaType != "video" {
		return ErrInvalidInput
	}
	if !isModerationStatus(creative.ModerationStatus) || len(creative.ModerationReason) > 500 {
		return ErrInvalidInput
	}
	if creative.Content == "" && creative.MediaURL == "" {
		return ErrInvalidInput
	}
	hydrateCreative(creative)
	return nil
}

func resetModeration(creative *model.Creative) {
	creative.ModerationStatus = "draft"
	creative.ModerationReason = ""
	creative.SubmittedAt = nil
	creative.ReviewedAt = nil
	creative.ReviewedBy = nil
}

func isModerationStatus(status string) bool {
	return status == "draft" || status == "pending" || status == "approved" || status == "rejected"
}

func setCreativeMedia(creative *model.Creative, media model.CreativeMedia, storedPath string) {
	creative.Media = media
	creative.MediaType = media.Type
	creative.MediaURL = media.URL
	creative.MediaPath = storedPath
	creative.MIMEType = media.MIMEType
	creative.FileName = media.FileName
	creative.FileSize = media.FileSize
}

func hydrateCreative(creative *model.Creative) {
	creative.Media = model.CreativeMedia{
		Type:     creative.MediaType,
		URL:      creative.MediaURL,
		MIMEType: creative.MIMEType,
		FileName: creative.FileName,
		FileSize: creative.FileSize,
	}
}
