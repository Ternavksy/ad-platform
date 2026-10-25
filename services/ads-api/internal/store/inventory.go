package store

import (
	"ads-api/internal/model"
	"context"

	"github.com/jmoiron/sqlx"
)

type InventoryStore struct {
	db *sqlx.DB
}

func NewInventoryStore(db *sqlx.DB) *InventoryStore {
	return &InventoryStore{db: db}
}

func (s *InventoryStore) CreateSite(ctx context.Context, item *model.Site) error {
	result, err := s.db.ExecContext(ctx, `
		INSERT INTO sites (user_id, name, domain, status) VALUES (?, ?, ?, ?)
	`, item.UserID, item.Name, item.Domain, item.Status)
	if err != nil {
		return err
	}
	item.ID, _ = result.LastInsertId()
	return nil
}

func (s *InventoryStore) GetSite(ctx context.Context, id int64) (*model.Site, error) {
	var item model.Site
	err := s.db.GetContext(ctx, &item, `
		SELECT id, user_id, name, domain, status FROM sites WHERE id = ?
	`, id)
	return &item, err
}

func (s *InventoryStore) ListSites(ctx context.Context, userID int64) ([]model.Site, error) {
	items := make([]model.Site, 0)
	err := s.db.SelectContext(ctx, &items, `
		SELECT id, user_id, name, domain, status
		FROM sites WHERE user_id = ? ORDER BY id DESC
	`, userID)
	return items, err
}

func (s *InventoryStore) UpdateSite(ctx context.Context, item *model.Site) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE sites SET name = ?, domain = ?, status = ? WHERE id = ?
	`, item.Name, item.Domain, item.Status, item.ID)
	return err
}

func (s *InventoryStore) DeleteSite(ctx context.Context, id int64) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM sites WHERE id = ?`, id)
	return err
}

func (s *InventoryStore) CreateFormat(ctx context.Context, item *model.AdFormat) error {
	result, err := s.db.ExecContext(ctx, `
		INSERT INTO ad_formats (code, name, kind, width, height, status)
		VALUES (?, ?, ?, ?, ?, ?)
	`, item.Code, item.Name, item.Kind, item.Width, item.Height, item.Status)
	if err != nil {
		return err
	}
	item.ID, _ = result.LastInsertId()
	return nil
}

func (s *InventoryStore) GetFormat(ctx context.Context, id int64) (*model.AdFormat, error) {
	var item model.AdFormat
	err := s.db.GetContext(ctx, &item, `
		SELECT id, code, name, kind, width, height, status FROM ad_formats WHERE id = ?
	`, id)
	return &item, err
}

func (s *InventoryStore) ListFormats(ctx context.Context) ([]model.AdFormat, error) {
	items := make([]model.AdFormat, 0)
	err := s.db.SelectContext(ctx, &items, `
		SELECT id, code, name, kind, width, height, status
		FROM ad_formats ORDER BY kind, width, height, id
	`)
	return items, err
}

func (s *InventoryStore) UpdateFormat(ctx context.Context, item *model.AdFormat) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE ad_formats SET code = ?, name = ?, kind = ?, width = ?, height = ?, status = ?
		WHERE id = ?
	`, item.Code, item.Name, item.Kind, item.Width, item.Height, item.Status, item.ID)
	return err
}

func (s *InventoryStore) DeleteFormat(ctx context.Context, id int64) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM ad_formats WHERE id = ?`, id)
	return err
}

func (s *InventoryStore) CreatePlacement(ctx context.Context, item *model.Placement) error {
	result, err := s.db.ExecContext(ctx, `
		INSERT INTO placements (site_id, format_id, name, code, status)
		VALUES (?, ?, ?, ?, ?)
	`, item.SiteID, item.FormatID, item.Name, item.Code, item.Status)
	if err != nil {
		return err
	}
	item.ID, _ = result.LastInsertId()
	return nil
}

func (s *InventoryStore) GetPlacement(ctx context.Context, id int64) (*model.Placement, error) {
	var item model.Placement
	err := s.db.GetContext(ctx, &item, `
		SELECT id, site_id, format_id, name, code, status FROM placements WHERE id = ?
	`, id)
	return &item, err
}

func (s *InventoryStore) ListPlacements(ctx context.Context, siteID int64) ([]model.Placement, error) {
	items := make([]model.Placement, 0)
	err := s.db.SelectContext(ctx, &items, `
		SELECT id, site_id, format_id, name, code, status
		FROM placements WHERE site_id = ? ORDER BY id DESC
	`, siteID)
	return items, err
}

func (s *InventoryStore) UpdatePlacement(ctx context.Context, item *model.Placement) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE placements SET site_id = ?, format_id = ?, name = ?, status = ? WHERE id = ?
	`, item.SiteID, item.FormatID, item.Name, item.Status, item.ID)
	return err
}

func (s *InventoryStore) DeletePlacement(ctx context.Context, id int64) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM placements WHERE id = ?`, id)
	return err
}

func (s *InventoryStore) SiteAndFormatExist(ctx context.Context, siteID, formatID int64) (bool, error) {
	var count int
	err := s.db.GetContext(ctx, &count, `
		SELECT COUNT(*) FROM sites s CROSS JOIN ad_formats f
		WHERE s.id = ? AND f.id = ?
	`, siteID, formatID)
	return count == 1, err
}
