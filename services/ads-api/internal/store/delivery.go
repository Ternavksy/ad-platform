package store

import (
	"ads-api/internal/model"
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

type DeliveryStore struct {
	db *sqlx.DB
}

var ErrBudgetExhausted = errors.New("campaign budget exhausted")

func NewDeliveryStore(db *sqlx.DB) *DeliveryStore {
	return &DeliveryStore{db: db}
}

func (s *DeliveryStore) ListCandidates(ctx context.Context, placement string) ([]model.DeliveryCandidate, error) {
	items := make([]model.DeliveryCandidate, 0)
	err := s.db.SelectContext(ctx, &items, `
		SELECT a.campaign_id, a.id AS ad_id, cr.id AS creative_id,
		       a.title AS ad_title, cr.content AS creative_content,
		       cr.media_type AS creative_media_type, cr.media_url AS creative_media_url,
		       cr.mime_type AS creative_mime_type, cr.file_name AS creative_file_name,
		       cr.file_size AS creative_file_size,
		       a.placement, a.destination_url, a.weight, a.bid_cpm,
		       c.budget_total AS campaign_budget_total, c.daily_limit AS campaign_daily_limit,
		       c.spent_total AS campaign_spent_total, c.spent_today AS campaign_spent_today,
		       c.spent_date AS campaign_spent_date, c.starts_at AS campaign_starts_at,
		       c.ends_at AS campaign_ends_at, c.schedule_days AS campaign_schedule_days,
		       c.schedule_start_hour AS campaign_schedule_start_hour,
		       c.schedule_end_hour AS campaign_schedule_end_hour,
		       0 AS site_id, 0 AS placement_id, 0 AS format_id,
		       '' AS placement_code, '' AS format_code,
		       0 AS format_width, 0 AS format_height,
		       a.target_min_age, a.target_max_age, a.target_genders,
		       a.target_interests, a.target_countries, a.target_regions,
		       a.target_cities, a.target_device_types, a.target_operating_systems
		FROM ads a
		JOIN campaigns c ON c.id = a.campaign_id
		JOIN creatives cr ON cr.ad_id = a.id
		WHERE c.status = 'active'
		  AND a.status = 'active'
		  AND a.placement_id IS NULL
		  AND a.placement = ?
		  AND a.destination_url <> ''
		  AND a.weight > 0
		  AND cr.moderation_status = 'approved'
		ORDER BY a.id, cr.id
	`, placement)
	return items, err
}

func (s *DeliveryStore) ListCandidatesByCode(ctx context.Context, placementCode string) ([]model.DeliveryCandidate, error) {
	items := make([]model.DeliveryCandidate, 0)
	err := s.db.SelectContext(ctx, &items, `
		SELECT a.campaign_id, a.id AS ad_id, cr.id AS creative_id,
		       a.title AS ad_title, cr.content AS creative_content,
		       cr.media_type AS creative_media_type, cr.media_url AS creative_media_url,
		       cr.mime_type AS creative_mime_type, cr.file_name AS creative_file_name,
		       cr.file_size AS creative_file_size,
		       f.kind AS placement, a.destination_url, a.weight, a.bid_cpm,
		       c.budget_total AS campaign_budget_total, c.daily_limit AS campaign_daily_limit,
		       c.spent_total AS campaign_spent_total, c.spent_today AS campaign_spent_today,
		       c.spent_date AS campaign_spent_date, c.starts_at AS campaign_starts_at,
		       c.ends_at AS campaign_ends_at, c.schedule_days AS campaign_schedule_days,
		       c.schedule_start_hour AS campaign_schedule_start_hour,
		       c.schedule_end_hour AS campaign_schedule_end_hour,
		       s.id AS site_id, p.id AS placement_id, f.id AS format_id,
		       p.code AS placement_code, f.code AS format_code,
		       f.width AS format_width, f.height AS format_height,
		       a.target_min_age, a.target_max_age, a.target_genders,
		       a.target_interests, a.target_countries, a.target_regions,
		       a.target_cities, a.target_device_types, a.target_operating_systems
		FROM placements p
		JOIN sites s ON s.id = p.site_id
		JOIN ad_formats f ON f.id = p.format_id
		JOIN ads a ON a.placement_id = p.id
		JOIN campaigns c ON c.id = a.campaign_id
		JOIN creatives cr ON cr.ad_id = a.id
		WHERE p.code = ?
		  AND p.status = 'active'
		  AND s.status = 'active'
		  AND f.status = 'active'
		  AND c.status = 'active'
		  AND a.status = 'active'
		  AND a.destination_url <> ''
		  AND a.weight > 0
		  AND cr.moderation_status = 'approved'
		ORDER BY a.id, cr.id
	`, placementCode)
	return items, err
}

func (s *DeliveryStore) GetByID(ctx context.Context, id string) (*model.Delivery, error) {
	var item model.Delivery
	err := s.db.GetContext(ctx, &item, `
		SELECT id, campaign_id, ad_id, creative_id, ad_title, creative_content,
		       creative_media_type, creative_media_url, creative_mime_type,
		       creative_file_name, creative_file_size,
		       placement, visitor_id, destination_url, created_at, clicked_at,
		       site_id, placement_id, format_id, placement_code, format_code,
		       format_width, format_height, audience_age, audience_gender,
		       audience_interests, country, region, city, device_type, operating_system,
		       bid_cpm, cost
		FROM ad_deliveries
		WHERE id = ?
	`, id)
	if err != nil {
		return nil, err
	}
	return &item, nil
}

func (s *DeliveryStore) Create(ctx context.Context, item *model.Delivery) error {
	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	date := item.CreatedAt.UTC().Format("2006-01-02")
	budgetResult, err := tx.ExecContext(ctx, `
		UPDATE campaigns
		SET spent_total = spent_total + ?,
		    spent_today = CASE WHEN spent_date = ? THEN spent_today + ? ELSE ? END,
		    spent_date = ?
		WHERE id = ? AND status = 'active'
		  AND (budget_total = 0 OR spent_total + ? <= budget_total)
		  AND (daily_limit = 0 OR
		       (CASE WHEN spent_date = ? THEN spent_today ELSE 0 END) + ? <= daily_limit)
	`, item.Cost, date, item.Cost, item.Cost, date, item.CampaignID,
		item.Cost, date, item.Cost)
	if err != nil {
		return err
	}
	budgetRows, err := budgetResult.RowsAffected()
	if err != nil {
		return err
	}
	if budgetRows != 1 {
		return ErrBudgetExhausted
	}

	_, err = tx.ExecContext(ctx, `
		INSERT INTO ad_deliveries
			(id, campaign_id, ad_id, creative_id, ad_title, creative_content,
			 creative_media_type, creative_media_url, creative_mime_type,
			 creative_file_name, creative_file_size,
			 placement, visitor_id, destination_url, created_at, clicked_at,
			 site_id, placement_id, format_id, placement_code, format_code,
			 format_width, format_height, audience_age, audience_gender,
			 audience_interests, country, region, city, device_type, operating_system,
			 bid_cpm, cost)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, item.ID, item.CampaignID, item.AdID, item.CreativeID, item.Title,
		item.Content, item.CreativeMediaType, item.CreativeMediaURL, item.CreativeMIMEType,
		item.CreativeFileName, item.CreativeFileSize, item.Placement, item.VisitorID,
		item.DestinationURL, item.CreatedAt,
		item.SiteID, item.PlacementID, item.FormatID, item.PlacementCode, item.FormatCode,
		item.FormatWidth, item.FormatHeight, item.AudienceAge, item.AudienceGender,
		item.AudienceInterests, item.Country, item.Region, item.City, item.DeviceType,
		item.OperatingSystem, item.BidCPM, item.Cost)
	if err != nil {
		return err
	}

	event := model.DeliveryEvent{
		ID:                uuid.NewString(),
		DeliveryID:        item.ID,
		EventType:         "ad_impression",
		CampaignID:        item.CampaignID,
		AdID:              item.AdID,
		CreativeID:        item.CreativeID,
		Placement:         item.Placement,
		OccurredAt:        item.CreatedAt,
		SiteID:            item.SiteID,
		PlacementID:       item.PlacementID,
		FormatID:          item.FormatID,
		PlacementCode:     item.PlacementCode,
		FormatCode:        item.FormatCode,
		AudienceAge:       item.AudienceAge,
		AudienceGender:    item.AudienceGender,
		AudienceInterests: item.AudienceInterests,
		Country:           item.Country,
		Region:            item.Region,
		City:              item.City,
		DeviceType:        item.DeviceType,
		OperatingSystem:   item.OperatingSystem,
		BidCPM:            item.BidCPM,
		Cost:              item.Cost,
	}
	if err := insertEvent(ctx, tx, &event); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *DeliveryStore) TrackClick(ctx context.Context, id string, now time.Time) (*model.Delivery, error) {
	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	result, err := tx.ExecContext(ctx, `
		UPDATE ad_deliveries SET clicked_at = ?
		WHERE id = ? AND clicked_at IS NULL
	`, now, id)
	if err != nil {
		return nil, err
	}

	var item model.Delivery
	err = tx.GetContext(ctx, &item, `
		SELECT id, campaign_id, ad_id, creative_id, ad_title, creative_content,
		       creative_media_type, creative_media_url, creative_mime_type,
		       creative_file_name, creative_file_size,
		       placement, visitor_id, destination_url, created_at, clicked_at,
		       site_id, placement_id, format_id, placement_code, format_code,
		       format_width, format_height, audience_age, audience_gender,
		       audience_interests, country, region, city, device_type, operating_system,
		       bid_cpm, cost
		FROM ad_deliveries WHERE id = ?
	`, id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, sql.ErrNoRows
		}
		return nil, err
	}

	rows, err := result.RowsAffected()
	if err != nil {
		return nil, err
	}
	if rows == 1 {
		event := model.DeliveryEvent{
			ID:                uuid.NewString(),
			DeliveryID:        item.ID,
			EventType:         "ad_click",
			CampaignID:        item.CampaignID,
			AdID:              item.AdID,
			CreativeID:        item.CreativeID,
			Placement:         item.Placement,
			OccurredAt:        now,
			SiteID:            item.SiteID,
			PlacementID:       item.PlacementID,
			FormatID:          item.FormatID,
			PlacementCode:     item.PlacementCode,
			FormatCode:        item.FormatCode,
			AudienceAge:       item.AudienceAge,
			AudienceGender:    item.AudienceGender,
			AudienceInterests: item.AudienceInterests,
			Country:           item.Country,
			Region:            item.Region,
			City:              item.City,
			DeviceType:        item.DeviceType,
			OperatingSystem:   item.OperatingSystem,
			BidCPM:            item.BidCPM,
			Cost:              0,
		}
		if err := insertEvent(ctx, tx, &event); err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return &item, nil
}

func insertEvent(ctx context.Context, tx *sqlx.Tx, event *model.DeliveryEvent) error {
	_, err := tx.ExecContext(ctx, `
		INSERT INTO delivery_outbox
			(id, delivery_id, event_type, campaign_id, ad_id, creative_id,
			 placement, occurred_at, published_at, site_id, placement_id, format_id,
			 placement_code, format_code, audience_age, audience_gender,
			 audience_interests, country, region, city, device_type, operating_system,
			 bid_cpm, cost)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, event.ID, event.DeliveryID, event.EventType, event.CampaignID,
		event.AdID, event.CreativeID, event.Placement, event.OccurredAt,
		event.SiteID, event.PlacementID, event.FormatID, event.PlacementCode, event.FormatCode,
		event.AudienceAge, event.AudienceGender, event.AudienceInterests, event.Country,
		event.Region, event.City, event.DeviceType, event.OperatingSystem,
		event.BidCPM, event.Cost)
	return err
}

func (s *DeliveryStore) ListPendingEvents(ctx context.Context, limit int) ([]model.DeliveryEvent, error) {
	items := make([]model.DeliveryEvent, 0)
	err := s.db.SelectContext(ctx, &items, `
		SELECT id, delivery_id, event_type, campaign_id, ad_id, creative_id,
		       placement, occurred_at, site_id, placement_id, format_id,
		       placement_code, format_code, audience_age, audience_gender,
		       audience_interests, country, region, city, device_type, operating_system,
		       bid_cpm, cost
		FROM delivery_outbox
		WHERE published_at IS NULL
		ORDER BY occurred_at, id
		LIMIT ?
	`, limit)
	return items, err
}

func (s *DeliveryStore) MarkPublished(ctx context.Context, id string, now time.Time) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE delivery_outbox SET published_at = ?
		WHERE id = ? AND published_at IS NULL
	`, now, id)
	return err
}
