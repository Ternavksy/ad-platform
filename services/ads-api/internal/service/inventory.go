package service

import (
	"ads-api/internal/model"
	"ads-api/internal/store"
	"context"
	"database/sql"
	"errors"
	"net"
	"net/url"
	"strings"

	"github.com/google/uuid"
)

type InventoryService struct {
	store *store.InventoryStore
}

func NewInventoryService(s *store.InventoryStore) *InventoryService {
	return &InventoryService{store: s}
}

func normalizeStatus(value string) (string, error) {
	value = strings.ToLower(strings.TrimSpace(value))
	if value == "" {
		value = "active"
	}
	if value != "draft" && value != "active" && value != "paused" {
		return "", ErrInvalidInput
	}
	return value, nil
}

func normalizeDomain(value string) (string, error) {
	value = strings.TrimSpace(strings.ToLower(value))
	if value == "" || len(value) > 255 {
		return "", ErrInvalidInput
	}
	if !strings.Contains(value, "://") {
		value = "https://" + value
	}
	parsed, err := url.Parse(value)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Hostname() == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || (parsed.Path != "" && parsed.Path != "/") {
		return "", ErrInvalidInput
	}
	host := parsed.Hostname()
	if net.ParseIP(host) == nil && (!strings.Contains(host, ".") || strings.ContainsAny(host, " _")) {
		return "", ErrInvalidInput
	}
	if port := parsed.Port(); port != "" {
		host = net.JoinHostPort(host, port)
	}
	return host, nil
}

func (s *InventoryService) CreateSite(ctx context.Context, item *model.Site) error {
	item.Name = strings.TrimSpace(item.Name)
	domain, err := normalizeDomain(item.Domain)
	if err != nil || item.UserID <= 0 || item.Name == "" || len(item.Name) > 255 {
		return ErrInvalidInput
	}
	item.Domain = domain
	item.Status, err = normalizeStatus(item.Status)
	if err != nil {
		return err
	}
	return s.store.CreateSite(ctx, item)
}

func (s *InventoryService) GetSite(ctx context.Context, id int64) (*model.Site, error) {
	if id <= 0 {
		return nil, ErrNotFound
	}
	item, err := s.store.GetSite(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return item, err
}

func (s *InventoryService) ListSites(ctx context.Context, userID int64) ([]model.Site, error) {
	if userID <= 0 {
		return nil, ErrInvalidInput
	}
	return s.store.ListSites(ctx, userID)
}

func (s *InventoryService) UpdateSite(ctx context.Context, item *model.Site) error {
	if item.ID <= 0 {
		return ErrNotFound
	}
	current, err := s.GetSite(ctx, item.ID)
	if err != nil {
		return err
	}
	item.UserID = current.UserID
	return s.CreateOrUpdateSite(ctx, item)
}

func (s *InventoryService) CreateOrUpdateSite(ctx context.Context, item *model.Site) error {
	item.Name = strings.TrimSpace(item.Name)
	domain, err := normalizeDomain(item.Domain)
	if err != nil || item.UserID <= 0 || item.Name == "" || len(item.Name) > 255 {
		return ErrInvalidInput
	}
	item.Domain = domain
	item.Status, err = normalizeStatus(item.Status)
	if err != nil {
		return err
	}
	return s.store.UpdateSite(ctx, item)
}

func (s *InventoryService) DeleteSite(ctx context.Context, id int64) error {
	if _, err := s.GetSite(ctx, id); err != nil {
		return err
	}
	return s.store.DeleteSite(ctx, id)
}

func normalizeFormat(item *model.AdFormat) error {
	item.Code = strings.ToLower(strings.TrimSpace(item.Code))
	item.Name = strings.TrimSpace(item.Name)
	item.Kind = strings.ToLower(strings.TrimSpace(item.Kind))
	status, err := normalizeStatus(item.Status)
	if err != nil {
		return err
	}
	item.Status = status
	if !placementPattern.MatchString(item.Code) || item.Name == "" || len(item.Name) > 255 || item.Width < 0 || item.Height < 0 || item.Width > 10000 || item.Height > 10000 {
		return ErrInvalidInput
	}
	if item.Kind != "banner" && item.Kind != "native" && item.Kind != "video" && item.Kind != "story" {
		return ErrInvalidInput
	}
	if item.Kind != "native" && (item.Width == 0 || item.Height == 0) {
		return ErrInvalidInput
	}
	return nil
}

func (s *InventoryService) CreateFormat(ctx context.Context, item *model.AdFormat) error {
	if err := normalizeFormat(item); err != nil {
		return err
	}
	return s.store.CreateFormat(ctx, item)
}

func (s *InventoryService) GetFormat(ctx context.Context, id int64) (*model.AdFormat, error) {
	if id <= 0 {
		return nil, ErrNotFound
	}
	item, err := s.store.GetFormat(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return item, err
}

func (s *InventoryService) ListFormats(ctx context.Context) ([]model.AdFormat, error) {
	return s.store.ListFormats(ctx)
}

func (s *InventoryService) UpdateFormat(ctx context.Context, item *model.AdFormat) error {
	if _, err := s.GetFormat(ctx, item.ID); err != nil {
		return err
	}
	if err := normalizeFormat(item); err != nil {
		return err
	}
	return s.store.UpdateFormat(ctx, item)
}

func (s *InventoryService) DeleteFormat(ctx context.Context, id int64) error {
	if _, err := s.GetFormat(ctx, id); err != nil {
		return err
	}
	return s.store.DeleteFormat(ctx, id)
}

func normalizePlacement(item *model.Placement) error {
	item.Name = strings.TrimSpace(item.Name)
	status, err := normalizeStatus(item.Status)
	if err != nil {
		return err
	}
	item.Status = status
	if item.SiteID <= 0 || item.FormatID <= 0 || item.Name == "" || len(item.Name) > 255 {
		return ErrInvalidInput
	}
	return nil
}

func (s *InventoryService) CreatePlacement(ctx context.Context, item *model.Placement) error {
	if err := normalizePlacement(item); err != nil {
		return err
	}
	exists, err := s.store.SiteAndFormatExist(ctx, item.SiteID, item.FormatID)
	if err != nil {
		return err
	}
	if !exists {
		return ErrInvalidInput
	}
	item.Code = uuid.NewString()
	return s.store.CreatePlacement(ctx, item)
}

func (s *InventoryService) GetPlacement(ctx context.Context, id int64) (*model.Placement, error) {
	if id <= 0 {
		return nil, ErrNotFound
	}
	item, err := s.store.GetPlacement(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return item, err
}

func (s *InventoryService) ListPlacements(ctx context.Context, siteID int64) ([]model.Placement, error) {
	if siteID <= 0 {
		return nil, ErrInvalidInput
	}
	return s.store.ListPlacements(ctx, siteID)
}

func (s *InventoryService) UpdatePlacement(ctx context.Context, item *model.Placement) error {
	current, err := s.GetPlacement(ctx, item.ID)
	if err != nil {
		return err
	}
	if err := normalizePlacement(item); err != nil {
		return err
	}
	exists, err := s.store.SiteAndFormatExist(ctx, item.SiteID, item.FormatID)
	if err != nil {
		return err
	}
	if !exists {
		return ErrInvalidInput
	}
	item.Code = current.Code
	return s.store.UpdatePlacement(ctx, item)
}

func (s *InventoryService) DeletePlacement(ctx context.Context, id int64) error {
	if _, err := s.GetPlacement(ctx, id); err != nil {
		return err
	}
	return s.store.DeletePlacement(ctx, id)
}
