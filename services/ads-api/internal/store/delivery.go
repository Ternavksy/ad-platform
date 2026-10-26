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

var (
	ErrBudgetExhausted = errors.New("campaign budget exhausted")
	ErrEventConflict   = errors.New("tracking event payload conflicts with an existing event")
)

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
		       placement, visitor_id, destination_url, created_at, impressed_at, clicked_at,
		       site_id, placement_id, format_id, placement_code, format_code,
		       format_width, format_height, audience_age, audience_gender,
		       audience_interests, country, region, city, device_type, operating_system,
		       source_ip_hash, user_agent_hash, click_is_fraud, click_fraud_reason,
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
			 placement, visitor_id, destination_url, created_at, impressed_at, clicked_at,
			 site_id, placement_id, format_id, placement_code, format_code,
			 format_width, format_height, audience_age, audience_gender,
			 audience_interests, country, region, city, device_type, operating_system,
			 source_ip_hash, user_agent_hash, bid_cpm, cost)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, item.ID, item.CampaignID, item.AdID, item.CreativeID, item.Title,
		item.Content, item.CreativeMediaType, item.CreativeMediaURL, item.CreativeMIMEType,
		item.CreativeFileName, item.CreativeFileSize, item.Placement, item.VisitorID,
		item.DestinationURL, item.CreatedAt,
		item.SiteID, item.PlacementID, item.FormatID, item.PlacementCode, item.FormatCode,
		item.FormatWidth, item.FormatHeight, item.AudienceAge, item.AudienceGender,
		item.AudienceInterests, item.Country, item.Region, item.City, item.DeviceType,
		item.OperatingSystem, item.SourceIPHash, item.UserAgentHash, item.BidCPM, item.Cost)
	if err != nil {
		return err
	}

	return tx.Commit()
}

func (s *DeliveryStore) TrackImpression(ctx context.Context, id string, now time.Time) (*model.Delivery, *model.TrackingResult, error) {
	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return nil, nil, err
	}
	defer tx.Rollback()
	item, result, err := ensureImpression(ctx, tx, id, now)
	if err != nil {
		return nil, nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, nil, err
	}
	return item, result, nil
}

func (s *DeliveryStore) TrackClick(ctx context.Context, id string, now time.Time) (*model.Delivery, *model.TrackingResult, error) {
	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return nil, nil, err
	}
	defer tx.Rollback()

	item, _, err := ensureImpression(ctx, tx, id, now)
	if err != nil {
		return nil, nil, err
	}
	fraudReason, err := clickFraudReason(ctx, tx, item, now)
	if err != nil {
		return nil, nil, err
	}
	isFraud := fraudReason != ""

	result, err := tx.ExecContext(ctx, `
		UPDATE ad_deliveries
		SET clicked_at = ?, click_is_fraud = ?, click_fraud_reason = ?
		WHERE id = ? AND clicked_at IS NULL
	`, now, isFraud, fraudReason, id)
	if err != nil {
		return nil, nil, err
	}
	item, err = getDeliveryTx(ctx, tx, id)
	if err != nil {
		return nil, nil, err
	}

	rows, err := result.RowsAffected()
	if err != nil {
		return nil, nil, err
	}
	var tracked *model.TrackingResult
	if rows == 1 {
		event := deliveryEvent(item, "ad_click", now)
		event.IsFraud = isFraud
		event.FraudReason = fraudReason
		if err := insertEvent(ctx, tx, &event); err != nil {
			return nil, nil, err
		}
		tracked = trackingResult(event, true)
	} else {
		tracked, err = getTrackingResultTx(ctx, tx, id, "ad_click")
		if err != nil {
			return nil, nil, err
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, nil, err
	}
	return item, tracked, nil
}

func (s *DeliveryStore) TrackConversion(
	ctx context.Context,
	id string,
	req model.ConversionRequest,
	now time.Time,
	attributionModel string,
	attributionWindow int,
) (*model.Delivery, *model.TrackingResult, error) {
	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return nil, nil, err
	}
	defer tx.Rollback()

	item, _, err := ensureImpression(ctx, tx, id, now)
	if err != nil {
		return nil, nil, err
	}

	var existing model.TrackingResult
	err = tx.GetContext(ctx, &existing, `
		SELECT delivery_id, event_id, 'ad_conversion' AS event_type,
		       0 AS recorded, occurred_at, conversion_type,
		       value AS conversion_value, currency AS conversion_currency,
		       attribution_model, attribution_window_hours,
		       is_fraud, fraud_reason
		FROM delivery_conversions
		WHERE delivery_id = ? AND event_id = ?
	`, id, req.EventID)
	if err == nil {
		if existing.ConversionType != req.ConversionType ||
			existing.ConversionValue != req.Value ||
			existing.ConversionCurrency != req.Currency ||
			existing.AttributionModel != attributionModel {
			return nil, nil, ErrEventConflict
		}
		return item, &existing, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, nil, err
	}

	fraudReason, err := conversionFraudReason(ctx, tx, item, req, now)
	if err != nil {
		return nil, nil, err
	}
	isFraud := fraudReason != ""

	_, err = tx.ExecContext(ctx, `
		INSERT INTO delivery_conversions
			(delivery_id, event_id, conversion_type, value, currency, occurred_at,
			 attribution_model, attribution_window_hours, is_fraud, fraud_reason)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, id, req.EventID, req.ConversionType, req.Value, req.Currency, now,
		attributionModel, attributionWindow, isFraud, fraudReason)
	if err != nil {
		return nil, nil, err
	}
	event := deliveryEvent(item, "ad_conversion", now)
	event.ConversionID = req.EventID
	event.ConversionType = req.ConversionType
	event.ConversionValue = req.Value
	event.ConversionCurrency = req.Currency
	event.AttributionModel = attributionModel
	event.AttributionWindow = attributionWindow
	event.IsFraud = isFraud
	event.FraudReason = fraudReason
	if err := insertEvent(ctx, tx, &event); err != nil {
		return nil, nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, nil, err
	}
	return item, trackingResult(event, true), nil
}

func (s *DeliveryStore) FindAttributedDelivery(
	ctx context.Context,
	visitorID string,
	now time.Time,
	clickWindow time.Duration,
	viewWindow time.Duration,
) (*model.Delivery, string, int, error) {
	var id string
	err := s.db.GetContext(ctx, &id, `
		SELECT id
		FROM ad_deliveries
		WHERE visitor_id = ?
		  AND clicked_at IS NOT NULL
		  AND click_is_fraud = 0
		  AND clicked_at BETWEEN ? AND ?
		ORDER BY clicked_at DESC, id DESC
		LIMIT 1
	`, visitorID, now.Add(-clickWindow), now)
	if err == nil {
		item, getErr := s.GetByID(ctx, id)
		return item, "last_click", int(clickWindow / time.Hour), getErr
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, "", 0, err
	}
	err = s.db.GetContext(ctx, &id, `
		SELECT id
		FROM ad_deliveries
		WHERE visitor_id = ?
		  AND impressed_at IS NOT NULL
		  AND impressed_at BETWEEN ? AND ?
		ORDER BY impressed_at DESC, id DESC
		LIMIT 1
	`, visitorID, now.Add(-viewWindow), now)
	if err != nil {
		return nil, "", 0, err
	}
	item, err := s.GetByID(ctx, id)
	return item, "view_through", int(viewWindow / time.Hour), err
}

func clickFraudReason(
	ctx context.Context,
	tx *sqlx.Tx,
	item *model.Delivery,
	now time.Time,
) (string, error) {
	if item.VisitorID != nil && *item.VisitorID != "" {
		var count int
		if err := tx.GetContext(ctx, &count, `
			SELECT COUNT(*) FROM ad_deliveries
			WHERE visitor_id = ? AND clicked_at >= ?
		`, *item.VisitorID, now.Add(-time.Minute)); err != nil {
			return "", err
		}
		if count >= 20 {
			return "click_velocity", nil
		}
	}
	if item.SourceIPHash != "" {
		var count int
		if err := tx.GetContext(ctx, &count, `
			SELECT COUNT(*) FROM ad_deliveries
			WHERE source_ip_hash = ? AND clicked_at >= ?
		`, item.SourceIPHash, now.Add(-time.Minute)); err != nil {
			return "", err
		}
		if count >= 100 {
			return "ip_click_velocity", nil
		}
	}
	return "", nil
}

func conversionFraudReason(
	ctx context.Context,
	tx *sqlx.Tx,
	item *model.Delivery,
	req model.ConversionRequest,
	now time.Time,
) (string, error) {
	if req.Value > 10_000_000 {
		return "extreme_conversion_value", nil
	}
	if item.VisitorID == nil || *item.VisitorID == "" {
		return "", nil
	}
	var count int
	if err := tx.GetContext(ctx, &count, `
		SELECT COUNT(*)
		FROM delivery_conversions dc
		JOIN ad_deliveries d ON d.id = dc.delivery_id
		WHERE d.visitor_id = ? AND dc.occurred_at >= ?
	`, *item.VisitorID, now.Add(-time.Hour)); err != nil {
		return "", err
	}
	if count >= 10 {
		return "conversion_velocity", nil
	}
	return "", nil
}

func ensureImpression(
	ctx context.Context,
	tx *sqlx.Tx,
	id string,
	now time.Time,
) (*model.Delivery, *model.TrackingResult, error) {
	result, err := tx.ExecContext(ctx, `
		UPDATE ad_deliveries SET impressed_at = ?
		WHERE id = ? AND impressed_at IS NULL
	`, now, id)
	if err != nil {
		return nil, nil, err
	}
	item, err := getDeliveryTx(ctx, tx, id)
	if err != nil {
		return nil, nil, err
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return nil, nil, err
	}
	if rows == 1 {
		event := deliveryEvent(item, "ad_impression", now)
		event.Cost = item.Cost
		if err := insertEvent(ctx, tx, &event); err != nil {
			return nil, nil, err
		}
		return item, trackingResult(event, true), nil
	}
	tracked, err := getTrackingResultTx(ctx, tx, id, "ad_impression")
	if err != nil {
		return nil, nil, err
	}
	return item, tracked, nil
}

func getDeliveryTx(ctx context.Context, tx *sqlx.Tx, id string) (*model.Delivery, error) {
	var item model.Delivery
	err := tx.GetContext(ctx, &item, `
		SELECT id, campaign_id, ad_id, creative_id, ad_title, creative_content,
		       creative_media_type, creative_media_url, creative_mime_type,
		       creative_file_name, creative_file_size,
		       placement, visitor_id, destination_url, created_at, impressed_at, clicked_at,
		       site_id, placement_id, format_id, placement_code, format_code,
		       format_width, format_height, audience_age, audience_gender,
		       audience_interests, country, region, city, device_type, operating_system,
		       source_ip_hash, user_agent_hash, click_is_fraud, click_fraud_reason,
		       bid_cpm, cost
		FROM ad_deliveries WHERE id = ?
	`, id)
	return &item, err
}

func getTrackingResultTx(
	ctx context.Context,
	tx *sqlx.Tx,
	deliveryID string,
	eventType string,
) (*model.TrackingResult, error) {
	var result model.TrackingResult
	err := tx.GetContext(ctx, &result, `
		SELECT delivery_id, id AS event_id, event_type, 0 AS recorded, occurred_at,
		       conversion_type, conversion_value, conversion_currency,
		       attribution_model, attribution_window_hours, is_fraud, fraud_reason
		FROM delivery_outbox
		WHERE delivery_id = ? AND event_type = ?
		ORDER BY occurred_at, id
		LIMIT 1
	`, deliveryID, eventType)
	return &result, err
}

func deliveryEvent(item *model.Delivery, eventType string, now time.Time) model.DeliveryEvent {
	return model.DeliveryEvent{
		ID:                uuid.NewString(),
		DeliveryID:        item.ID,
		EventType:         eventType,
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
	}
}

func trackingResult(event model.DeliveryEvent, recorded bool) *model.TrackingResult {
	eventID := event.ID
	if event.EventType == "ad_conversion" && event.ConversionID != "" {
		eventID = event.ConversionID
	}
	return &model.TrackingResult{
		DeliveryID:         event.DeliveryID,
		EventID:            eventID,
		EventType:          event.EventType,
		Recorded:           recorded,
		OccurredAt:         event.OccurredAt,
		ConversionType:     event.ConversionType,
		ConversionValue:    event.ConversionValue,
		ConversionCurrency: event.ConversionCurrency,
		AttributionModel:   event.AttributionModel,
		AttributionWindow:  event.AttributionWindow,
		IsFraud:            event.IsFraud,
		FraudReason:        event.FraudReason,
	}
}

func insertEvent(ctx context.Context, tx *sqlx.Tx, event *model.DeliveryEvent) error {
	_, err := tx.ExecContext(ctx, `
		INSERT INTO delivery_outbox
			(id, delivery_id, event_type, campaign_id, ad_id, creative_id,
			 placement, occurred_at, published_at, site_id, placement_id, format_id,
			 placement_code, format_code, audience_age, audience_gender,
			 audience_interests, country, region, city, device_type, operating_system,
			 bid_cpm, cost, conversion_id, conversion_type, conversion_value,
			 conversion_currency, attribution_model, attribution_window_hours,
			 is_fraud, fraud_reason)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, event.ID, event.DeliveryID, event.EventType, event.CampaignID,
		event.AdID, event.CreativeID, event.Placement, event.OccurredAt,
		event.SiteID, event.PlacementID, event.FormatID, event.PlacementCode, event.FormatCode,
		event.AudienceAge, event.AudienceGender, event.AudienceInterests, event.Country,
		event.Region, event.City, event.DeviceType, event.OperatingSystem,
		event.BidCPM, event.Cost, event.ConversionID, event.ConversionType,
		event.ConversionValue, event.ConversionCurrency, event.AttributionModel,
		event.AttributionWindow, event.IsFraud, event.FraudReason)
	return err
}

func (s *DeliveryStore) ListPendingEvents(ctx context.Context, limit int) ([]model.DeliveryEvent, error) {
	items := make([]model.DeliveryEvent, 0)
	err := s.db.SelectContext(ctx, &items, `
		SELECT id, delivery_id, event_type, campaign_id, ad_id, creative_id,
		       placement, occurred_at, site_id, placement_id, format_id,
		       placement_code, format_code, audience_age, audience_gender,
		       audience_interests, country, region, city, device_type, operating_system,
		       bid_cpm, cost, conversion_id, conversion_type, conversion_value,
		       conversion_currency, attribution_model, attribution_window_hours,
		       is_fraud, fraud_reason
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
