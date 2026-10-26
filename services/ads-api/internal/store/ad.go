package store

import (
	"ads-api/internal/model"
	"context"

	"github.com/jmoiron/sqlx"
)

type AdStore struct {
	db *sqlx.DB
}

func NewAdStore(db *sqlx.DB) *AdStore {
	return &AdStore{db: db}
}

func (s *AdStore) BeginTx(ctx context.Context) (*sqlx.Tx, error) {
	return s.db.BeginTxx(ctx, nil)
}

func (s *AdStore) Create(ctx context.Context, c *model.Ad) error {
	query := `
	INSERT INTO ads (
		campaign_id, placement_id, title, status, placement, destination_url, weight, bid_cpm,
		target_min_age, target_max_age, target_genders, target_interests,
		target_countries, target_regions, target_cities, target_device_types,
		target_operating_systems)
	VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`
	res, err := s.db.ExecContext(ctx, query, adCreateArgs(c)...)
	if err != nil {
		return err
	}
	c.ID, _ = res.LastInsertId()
	return nil
}

func (s *AdStore) CreateTx(ctx context.Context, tx *sqlx.Tx, c *model.Ad) error {
	query := `
	INSERT INTO ads (
		campaign_id, placement_id, title, status, placement, destination_url, weight, bid_cpm,
		target_min_age, target_max_age, target_genders, target_interests,
		target_countries, target_regions, target_cities, target_device_types,
		target_operating_systems)
	VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`
	res, err := tx.ExecContext(ctx, query, adCreateArgs(c)...)
	if err != nil {
		return err
	}
	c.ID, _ = res.LastInsertId()
	return nil
}

func (s *AdStore) GetByID(ctx context.Context, id int64) (*model.Ad, error) {
	var ad model.Ad
	err := s.db.GetContext(ctx, &ad, `
	SELECT id, campaign_id, placement_id, title, status, placement, destination_url, weight, bid_cpm,
	       target_min_age, target_max_age, target_genders, target_interests,
	       target_countries, target_regions, target_cities, target_device_types,
	       target_operating_systems
	FROM ads
	WHERE id = ?
	`, id)
	if err != nil {
		return nil, err
	}
	return &ad, nil
}

func (s *AdStore) ListByCampaign(ctx context.Context, campaignID int64) ([]model.Ad, error) {
	items := make([]model.Ad, 0)
	err := s.db.SelectContext(ctx, &items, `
		SELECT id, campaign_id, placement_id, title, status, placement, destination_url, weight, bid_cpm,
		       target_min_age, target_max_age, target_genders, target_interests,
		       target_countries, target_regions, target_cities, target_device_types,
		       target_operating_systems
		FROM ads
		WHERE campaign_id = ?
		ORDER BY id DESC
	`, campaignID)
	return items, err
}

func (s *AdStore) Update(ctx context.Context, ad *model.Ad) error {
	query := `
		UPDATE ads
		SET placement_id = ?, title = ?, status = ?, placement = ?, destination_url = ?, weight = ?, bid_cpm = ?,
		    target_min_age = ?, target_max_age = ?, target_genders = ?, target_interests = ?,
		    target_countries = ?, target_regions = ?, target_cities = ?, target_device_types = ?,
		    target_operating_systems = ?
		WHERE id = ?
	`
	_, err := s.db.ExecContext(ctx, query, adUpdateArgs(ad)...)
	return err
}

func (s *AdStore) UpdateTx(ctx context.Context, tx *sqlx.Tx, ad *model.Ad) error {
	query := `
		UPDATE ads
		SET placement_id = ?, title = ?, status = ?, placement = ?, destination_url = ?, weight = ?, bid_cpm = ?,
		    target_min_age = ?, target_max_age = ?, target_genders = ?, target_interests = ?,
		    target_countries = ?, target_regions = ?, target_cities = ?, target_device_types = ?,
		    target_operating_systems = ?
		WHERE id = ?
	`
	_, err := tx.ExecContext(ctx, query, adUpdateArgs(ad)...)
	return err
}

func adCreateArgs(ad *model.Ad) []any {
	return []any{
		ad.CampaignID, ad.PlacementID, ad.Title, ad.Status, ad.Placement, ad.DestinationURL, ad.Weight, ad.BidCPM,
		ad.TargetMinAge, ad.TargetMaxAge, ad.TargetGenders, ad.TargetInterests,
		ad.TargetCountries, ad.TargetRegions, ad.TargetCities, ad.TargetDeviceTypes,
		ad.TargetOperatingSystems,
	}
}

func adUpdateArgs(ad *model.Ad) []any {
	return []any{
		ad.PlacementID, ad.Title, ad.Status, ad.Placement, ad.DestinationURL, ad.Weight, ad.BidCPM,
		ad.TargetMinAge, ad.TargetMaxAge, ad.TargetGenders, ad.TargetInterests,
		ad.TargetCountries, ad.TargetRegions, ad.TargetCities, ad.TargetDeviceTypes,
		ad.TargetOperatingSystems, ad.ID,
	}
}

func (s *AdStore) PlacementBelongsToCampaignOwner(ctx context.Context, placementID, campaignID int64) (bool, error) {
	var count int
	err := s.db.GetContext(ctx, &count, `
		SELECT COUNT(*)
		FROM placements p
		JOIN sites s ON s.id = p.site_id
		JOIN campaigns c ON c.user_id = s.user_id
		WHERE p.id = ? AND c.id = ?
	`, placementID, campaignID)
	return count == 1, err
}

func (s *AdStore) CampaignOwnedByUser(ctx context.Context, campaignID, userID int64) (bool, error) {
	var count int
	err := s.db.GetContext(ctx, &count, `
		SELECT COUNT(*) FROM campaigns WHERE id = ? AND user_id = ?
	`, campaignID, userID)
	return count == 1, err
}

func (s *AdStore) OwnedByUser(ctx context.Context, adID, userID int64) (bool, error) {
	var count int
	err := s.db.GetContext(ctx, &count, `
		SELECT COUNT(*)
		FROM ads a JOIN campaigns c ON c.id = a.campaign_id
		WHERE a.id = ? AND c.user_id = ?
	`, adID, userID)
	return count == 1, err
}

func (s *AdStore) Delete(ctx context.Context, id int64) error {
	query := `DELETE FROM ads WHERE id = ?`
	_, err := s.db.ExecContext(ctx, query, id)
	return err
}

func (s *AdStore) DeleteTx(ctx context.Context, tx *sqlx.Tx, id int64) error {
	query := `DELETE FROM ads WHERE id = ?`
	_, err := tx.ExecContext(ctx, query, id)
	return err
}
