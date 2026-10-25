package service_test

import (
	"context"
	"errors"
	"math"
	"testing"
	"time"

	"ads-api/internal/model"
	"ads-api/internal/service"
	"ads-api/internal/store"

	"github.com/jmoiron/sqlx"
	_ "github.com/mattn/go-sqlite3"
)

func setupDB(t *testing.T) *sqlx.DB {
	t.Helper()
	db, err := sqlx.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatalf("open db: %v", err)
	}

	_, err = db.Exec(`CREATE TABLE campaigns(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        name TEXT NOT NULL,
        status TEXT NOT NULL,
        budget_total REAL NOT NULL DEFAULT 0,
        daily_limit REAL NOT NULL DEFAULT 0,
        spent_total REAL NOT NULL DEFAULT 0,
        spent_today REAL NOT NULL DEFAULT 0,
        spent_date DATE,
        starts_at DATETIME,
        ends_at DATETIME,
        schedule_days TEXT NOT NULL DEFAULT '',
        schedule_start_hour INTEGER NOT NULL DEFAULT 0,
        schedule_end_hour INTEGER NOT NULL DEFAULT 24
    );`)
	if err != nil {
		t.Fatalf("create campaigns: %v", err)
	}

	_, err = db.Exec(`CREATE TABLE ad_formats(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        width INTEGER NOT NULL,
        height INTEGER NOT NULL,
        status TEXT NOT NULL
    );
    CREATE TABLE sites(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        domain TEXT NOT NULL,
        status TEXT NOT NULL
    );
    CREATE TABLE placements(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        site_id INTEGER NOT NULL,
        format_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        status TEXT NOT NULL
    );`)
	if err != nil {
		t.Fatalf("create inventory: %v", err)
	}

	_, err = db.Exec(`CREATE TABLE ads(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        campaign_id INTEGER NOT NULL,
        placement_id INTEGER,
        title TEXT NOT NULL,
        status TEXT NOT NULL,
        placement TEXT NOT NULL DEFAULT 'feed',
        destination_url TEXT NOT NULL DEFAULT '',
        weight INTEGER NOT NULL DEFAULT 1,
        bid_cpm REAL NOT NULL DEFAULT 1,
        target_min_age INTEGER NOT NULL DEFAULT 0,
        target_max_age INTEGER NOT NULL DEFAULT 0,
        target_genders TEXT NOT NULL DEFAULT '',
        target_interests TEXT NOT NULL DEFAULT '',
        target_countries TEXT NOT NULL DEFAULT '',
        target_regions TEXT NOT NULL DEFAULT '',
        target_cities TEXT NOT NULL DEFAULT '',
        target_device_types TEXT NOT NULL DEFAULT '',
        target_operating_systems TEXT NOT NULL DEFAULT ''
    );`)
	if err != nil {
		t.Fatalf("create ads: %v", err)
	}

	_, err = db.Exec(`CREATE TABLE creatives(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ad_id INTEGER NOT NULL,
        content TEXT NOT NULL,
        media_type TEXT NOT NULL DEFAULT 'text',
        media_url TEXT NOT NULL DEFAULT '',
        media_path TEXT NOT NULL DEFAULT '',
        mime_type TEXT NOT NULL DEFAULT '',
        file_name TEXT NOT NULL DEFAULT '',
        file_size INTEGER NOT NULL DEFAULT 0,
        moderation_status TEXT NOT NULL DEFAULT 'approved',
        moderation_reason TEXT NOT NULL DEFAULT '',
        submitted_at DATETIME,
        reviewed_at DATETIME,
        reviewed_by INTEGER
    );`)
	if err != nil {
		t.Fatalf("create creatives: %v", err)
	}

	_, err = db.Exec(`CREATE TABLE ad_deliveries(
        id TEXT PRIMARY KEY,
        campaign_id INTEGER NOT NULL,
        ad_id INTEGER NOT NULL,
        creative_id INTEGER NOT NULL,
        ad_title TEXT NOT NULL,
        creative_content TEXT NOT NULL,
        creative_media_type TEXT NOT NULL DEFAULT 'text',
        creative_media_url TEXT NOT NULL DEFAULT '',
        creative_mime_type TEXT NOT NULL DEFAULT '',
        creative_file_name TEXT NOT NULL DEFAULT '',
        creative_file_size INTEGER NOT NULL DEFAULT 0,
        placement TEXT NOT NULL,
        visitor_id TEXT,
        destination_url TEXT NOT NULL,
        created_at DATETIME NOT NULL,
        clicked_at DATETIME
        ,site_id INTEGER NOT NULL DEFAULT 0
        ,placement_id INTEGER NOT NULL DEFAULT 0
        ,format_id INTEGER NOT NULL DEFAULT 0
        ,placement_code TEXT NOT NULL DEFAULT ''
        ,format_code TEXT NOT NULL DEFAULT ''
        ,format_width INTEGER NOT NULL DEFAULT 0
        ,format_height INTEGER NOT NULL DEFAULT 0
        ,audience_age INTEGER NOT NULL DEFAULT 0
        ,audience_gender TEXT NOT NULL DEFAULT ''
        ,audience_interests TEXT NOT NULL DEFAULT ''
        ,country TEXT NOT NULL DEFAULT ''
        ,region TEXT NOT NULL DEFAULT ''
        ,city TEXT NOT NULL DEFAULT ''
        ,device_type TEXT NOT NULL DEFAULT ''
        ,operating_system TEXT NOT NULL DEFAULT ''
        ,bid_cpm REAL NOT NULL DEFAULT 0
        ,cost REAL NOT NULL DEFAULT 0
    );`)
	if err != nil {
		t.Fatalf("create ad_deliveries: %v", err)
	}

	_, err = db.Exec(`CREATE TABLE delivery_outbox(
        id TEXT PRIMARY KEY,
        delivery_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        campaign_id INTEGER NOT NULL,
        ad_id INTEGER NOT NULL,
        creative_id INTEGER NOT NULL,
        placement TEXT NOT NULL,
        occurred_at DATETIME NOT NULL,
        published_at DATETIME
        ,site_id INTEGER NOT NULL DEFAULT 0
        ,placement_id INTEGER NOT NULL DEFAULT 0
        ,format_id INTEGER NOT NULL DEFAULT 0
        ,placement_code TEXT NOT NULL DEFAULT ''
        ,format_code TEXT NOT NULL DEFAULT ''
        ,audience_age INTEGER NOT NULL DEFAULT 0
        ,audience_gender TEXT NOT NULL DEFAULT ''
        ,audience_interests TEXT NOT NULL DEFAULT ''
        ,country TEXT NOT NULL DEFAULT ''
        ,region TEXT NOT NULL DEFAULT ''
        ,city TEXT NOT NULL DEFAULT ''
        ,device_type TEXT NOT NULL DEFAULT ''
        ,operating_system TEXT NOT NULL DEFAULT ''
        ,bid_cpm REAL NOT NULL DEFAULT 0
        ,cost REAL NOT NULL DEFAULT 0
    );`)
	if err != nil {
		t.Fatalf("create delivery_outbox: %v", err)
	}

	return db
}

func TestDeliveryServiceSelectAndClickAreIdempotent(t *testing.T) {
	db := setupDB(t)
	defer db.Close()

	campaign, err := db.Exec(`
		INSERT INTO campaigns(user_id, name, status, budget_total, daily_limit)
		VALUES (?, ?, ?, ?, ?)
	`, 1, "camp", "active", 0.025, 0.0125)
	if err != nil {
		t.Fatalf("insert campaign: %v", err)
	}
	campaignID, _ := campaign.LastInsertId()
	format, err := db.Exec(`
		INSERT INTO ad_formats(code, name, kind, width, height, status)
		VALUES (?, ?, ?, ?, ?, ?)
	`, "native_feed", "Native", "native", 0, 0, "active")
	if err != nil {
		t.Fatalf("insert format: %v", err)
	}
	formatID, _ := format.LastInsertId()
	site, err := db.Exec(`
		INSERT INTO sites(user_id, name, domain, status) VALUES (?, ?, ?, ?)
	`, 1, "site", "example.com", "active")
	if err != nil {
		t.Fatalf("insert site: %v", err)
	}
	siteID, _ := site.LastInsertId()
	placementCode := "2fa238ac-57d5-4520-b4fb-a384f5f1de03"
	placement, err := db.Exec(`
		INSERT INTO placements(site_id, format_id, name, code, status)
		VALUES (?, ?, ?, ?, ?)
	`, siteID, formatID, "feed", placementCode, "active")
	if err != nil {
		t.Fatalf("insert placement: %v", err)
	}
	placementID, _ := placement.LastInsertId()
	ad, err := db.Exec(`
		INSERT INTO ads(
			campaign_id, placement_id, title, status, placement, destination_url, weight, bid_cpm,
			target_min_age, target_max_age, target_genders, target_interests,
			target_countries, target_regions, target_cities, target_device_types,
			target_operating_systems)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, campaignID, placementID, "delivery ad", "active", "feed", "https://example.com/offer", 10,
		12.5, 18, 35, "female", "travel,sports", "RU", "moscow", "moscow", "mobile", "android")
	if err != nil {
		t.Fatalf("insert ad: %v", err)
	}
	adID, _ := ad.LastInsertId()
	creative, err := db.Exec(`
		INSERT INTO creatives(ad_id, content, media_type, media_url, mime_type, file_name, file_size)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	`, adID, "Buy now", "image", "/media/banner.png", "image/png", "banner.png", 128)
	if err != nil {
		t.Fatalf("insert creative: %v", err)
	}
	creativeID, _ := creative.LastInsertId()

	svc := service.NewDeliveryService(store.NewDeliveryStore(db))
	_, err = svc.Select(context.Background(), model.DeliveryRequest{
		RequestID:     "aa29d315-f954-4f01-aecf-052e8ece5fca",
		PlacementCode: placementCode,
		Audience:      model.AudienceContext{Age: 44, Gender: "male", Interests: []string{"finance"}},
		Geography:     model.GeographyContext{Country: "US", Region: "california", City: "san francisco"},
		Device:        model.DeviceContext{Type: "desktop", OperatingSystem: "macos"},
	})
	if !errors.Is(err, service.ErrNoDelivery) {
		t.Fatalf("mismatched targeting must not deliver an ad: %v", err)
	}
	request := model.DeliveryRequest{
		RequestID:     "010c236c-20c1-48f9-ac13-d9b9db620845",
		PlacementCode: placementCode,
		VisitorID:     "visitor-1",
		Audience:      model.AudienceContext{Age: 27, Gender: "female", Interests: []string{"travel"}},
		Geography:     model.GeographyContext{Country: "ru", Region: "Moscow", City: "Moscow"},
		Device:        model.DeviceContext{Type: "mobile", OperatingSystem: "android"},
	}
	first, err := svc.Select(context.Background(), request)
	if err != nil {
		t.Fatalf("select delivery: %v", err)
	}
	if first.AdID != adID || first.CreativeID != creativeID || first.ClickURL == "" {
		t.Fatalf("unexpected delivery: %#v", first)
	}
	if first.Media.Type != "image" || first.Media.URL != "/media/banner.png" || first.Media.FileSize != 128 {
		t.Fatalf("delivery media is missing: %#v", first.Media)
	}
	if first.SiteID != siteID || first.PlacementID != placementID || first.FormatID != formatID || first.FormatCode != "native_feed" {
		t.Fatalf("delivery inventory context is missing: %#v", first)
	}
	if first.Audience.Age != 27 || first.Geography.Country != "RU" || first.Device.Type != "mobile" {
		t.Fatalf("delivery request context is missing: %#v", first)
	}
	if first.BidCPM != 12.5 || math.Abs(first.Cost-0.0125) > 1e-9 {
		t.Fatalf("delivery price is missing: %#v", first)
	}
	second, err := svc.Select(context.Background(), request)
	if err != nil {
		t.Fatalf("repeat select: %v", err)
	}
	if second.ID != first.ID {
		t.Fatalf("repeat select returned a different delivery")
	}
	var spentTotal, spentToday float64
	if err := db.QueryRow(`SELECT spent_total, spent_today FROM campaigns WHERE id = ?`, campaignID).Scan(&spentTotal, &spentToday); err != nil {
		t.Fatalf("read campaign spend: %v", err)
	}
	if math.Abs(spentTotal-0.0125) > 1e-9 || math.Abs(spentToday-0.0125) > 1e-9 {
		t.Fatalf("unexpected campaign spend: total=%f today=%f", spentTotal, spentToday)
	}

	request.RequestID = "716289c7-09ea-4ec6-9cc5-6c3bb7df9393"
	if _, err := svc.Select(context.Background(), request); !errors.Is(err, service.ErrNoDelivery) {
		t.Fatalf("daily limit must stop delivery: %v", err)
	}
	if _, err := db.Exec(`UPDATE campaigns SET daily_limit = 0, budget_total = ? WHERE id = ?`, 0.0125, campaignID); err != nil {
		t.Fatalf("configure total budget: %v", err)
	}
	request.RequestID = "fb7661e4-56cc-4c85-af67-fd6588aaf88f"
	if _, err := svc.Select(context.Background(), request); !errors.Is(err, service.ErrNoDelivery) {
		t.Fatalf("total budget must stop delivery: %v", err)
	}
	if _, err := db.Exec(`
		UPDATE campaigns SET budget_total = 0, starts_at = ? WHERE id = ?
	`, time.Now().UTC().Add(time.Hour), campaignID); err != nil {
		t.Fatalf("configure future schedule: %v", err)
	}
	request.RequestID = "389c718a-f8a7-4680-a646-f0caf5ff53c5"
	if _, err := svc.Select(context.Background(), request); !errors.Is(err, service.ErrNoDelivery) {
		t.Fatalf("future schedule must stop delivery: %v", err)
	}

	clicked, err := svc.TrackClick(context.Background(), first.ID)
	if err != nil || clicked.ClickedAt == nil {
		t.Fatalf("track click: item=%#v err=%v", clicked, err)
	}
	if _, err := svc.TrackClick(context.Background(), first.ID); err != nil {
		t.Fatalf("repeat click: %v", err)
	}

	var impressions, clicks int
	if err := db.Get(&impressions, `SELECT count(*) FROM delivery_outbox WHERE event_type = 'ad_impression'`); err != nil {
		t.Fatalf("count impressions: %v", err)
	}
	if err := db.Get(&clicks, `SELECT count(*) FROM delivery_outbox WHERE event_type = 'ad_click'`); err != nil {
		t.Fatalf("count clicks: %v", err)
	}
	if impressions != 1 || clicks != 1 {
		t.Fatalf("idempotency failed: impressions=%d clicks=%d", impressions, clicks)
	}
}

func TestCreativeModerationLifecycle(t *testing.T) {
	db := setupDB(t)
	defer db.Close()

	campaign, err := db.Exec(`
		INSERT INTO campaigns(user_id, name, status) VALUES (?, ?, ?)
	`, 41, "moderation campaign", "active")
	if err != nil {
		t.Fatalf("insert campaign: %v", err)
	}
	campaignID, _ := campaign.LastInsertId()
	ad, err := db.Exec(`
		INSERT INTO ads(campaign_id, title, status, placement) VALUES (?, ?, ?, ?)
	`, campaignID, "moderation ad", "active", "feed")
	if err != nil {
		t.Fatalf("insert ad: %v", err)
	}
	adID, _ := ad.LastInsertId()

	svc := service.NewCreativeServiceWithStorage(
		store.NewCreativeStore(db),
		service.NewMediaStorage(t.TempDir()),
	)
	creative := &model.Creative{AdID: adID, Content: "Review me"}
	if err := svc.Create(context.Background(), creative); err != nil {
		t.Fatalf("create creative: %v", err)
	}
	if creative.ModerationStatus != "draft" {
		t.Fatalf("new creative must be a draft: %#v", creative)
	}
	if _, err := svc.SubmitForModeration(context.Background(), creative.ID, 99, false); !errors.Is(err, service.ErrForbidden) {
		t.Fatalf("another user must not submit creative: %v", err)
	}
	pending, err := svc.SubmitForModeration(context.Background(), creative.ID, 41, false)
	if err != nil || pending.ModerationStatus != "pending" || pending.SubmittedAt == nil {
		t.Fatalf("submit creative: item=%#v err=%v", pending, err)
	}
	queue, err := svc.ListForModeration(context.Background(), "pending")
	if err != nil || len(queue) != 1 || queue[0].CampaignName != "moderation campaign" {
		t.Fatalf("moderation queue: items=%#v err=%v", queue, err)
	}
	rejected, err := svc.ReviewModeration(
		context.Background(),
		creative.ID,
		7,
		model.ModerationDecision{Decision: "rejected", Reason: "Missing disclaimer"},
	)
	if err != nil || rejected.ModerationStatus != "rejected" || rejected.ModerationReason == "" {
		t.Fatalf("reject creative: item=%#v err=%v", rejected, err)
	}
	if _, err := svc.SubmitForModeration(context.Background(), creative.ID, 41, false); err != nil {
		t.Fatalf("resubmit creative: %v", err)
	}
	approved, err := svc.ReviewModeration(
		context.Background(),
		creative.ID,
		7,
		model.ModerationDecision{Decision: "approved"},
	)
	if err != nil || approved.ModerationStatus != "approved" || approved.ReviewedBy == nil {
		t.Fatalf("approve creative: item=%#v err=%v", approved, err)
	}
	approved.Content = "Edited after approval"
	if err := svc.Update(context.Background(), approved); err != nil {
		t.Fatalf("edit creative: %v", err)
	}
	if approved.ModerationStatus != "draft" || approved.ReviewedAt != nil {
		t.Fatalf("editing must reset moderation: %#v", approved)
	}
}

func TestAdServiceCRUD(t *testing.T) {
	db := setupDB(t)
	defer db.Close()

	res, err := db.Exec(`INSERT INTO campaigns(user_id, name, status) VALUES (?, ?, ?)`, 1, "camp", "active")
	if err != nil {
		t.Fatalf("insert campaign: %v", err)
	}
	cid, _ := res.LastInsertId()

	s := store.NewAdStore(db)
	svc := service.NewAdService(s, nil)

	ctx := context.Background()

	bad := &model.Ad{CampaignID: cid, Title: "", Status: "active"}
	if err := svc.Create(ctx, bad); err == nil {
		t.Fatalf("expected error for empty title")
	}

	a := &model.Ad{CampaignID: cid, Title: "first", Status: "active"}
	if err := svc.Create(ctx, a); err != nil {
		t.Fatalf("create failed: %v", err)
	}
	if a.ID == 0 {
		t.Fatalf("expected id set after create")
	}

	got, err := svc.GetByID(ctx, a.ID)
	if err != nil {
		t.Fatalf("get by id: %v", err)
	}
	if got.Title != a.Title {
		t.Fatalf("unexpected title: %s", got.Title)
	}

	aInvalid := &model.Ad{ID: 0, Title: "x", Status: "active"}
	if err := svc.Update(ctx, aInvalid); err == nil {
		t.Fatalf("expected ErrNotFound for id 0")
	}

	a.Title = "updated"
	if err := svc.Update(ctx, a); err != nil {
		t.Fatalf("update failed: %v", err)
	}
	got2, _ := svc.GetByID(ctx, a.ID)
	if got2.Title != "updated" {
		t.Fatalf("update not applied")
	}

	if err := svc.Delete(ctx, 0); err == nil {
		t.Fatalf("expected ErrNotFound for delete 0")
	}

	if err := svc.Delete(ctx, a.ID); err != nil {
		t.Fatalf("delete failed: %v", err)
	}

	if _, err := svc.GetByID(ctx, a.ID); err == nil {
		t.Fatalf("expected not found after delete")
	}
}

func TestCampaignBudgetsAndSchedule(t *testing.T) {
	db := setupDB(t)
	defer db.Close()

	svc := service.NewCampaignService(store.NewCampaignStore(db))
	start := time.Now().UTC().Add(-time.Hour)
	end := time.Now().UTC().Add(24 * time.Hour)
	campaign := &model.Campaign{
		UserID: 1,
		Name:   " scheduled campaign ",
		Status: "ACTIVE",
		Budget: model.CampaignBudget{Total: 100, DailyLimit: 10},
		Schedule: model.CampaignSchedule{
			StartsAt:  &start,
			EndsAt:    &end,
			Days:      []int{5, 1, 5},
			StartHour: 8,
			EndHour:   20,
		},
	}
	if err := svc.Create(context.Background(), campaign); err != nil {
		t.Fatalf("create campaign: %v", err)
	}
	if campaign.Name != "scheduled campaign" || campaign.Status != "active" {
		t.Fatalf("campaign was not normalized: %#v", campaign)
	}
	if len(campaign.Schedule.Days) != 2 || campaign.Schedule.Days[0] != 1 || campaign.Schedule.Timezone != "UTC" {
		t.Fatalf("campaign schedule was not normalized: %#v", campaign.Schedule)
	}

	if _, err := db.Exec(`
		UPDATE campaigns SET spent_total = 25, spent_today = 4, spent_date = ? WHERE id = ?
	`, time.Now().UTC().Format("2006-01-02"), campaign.ID); err != nil {
		t.Fatalf("set campaign spend: %v", err)
	}
	campaign.Budget.Total = 20
	if err := svc.Update(context.Background(), campaign); !errors.Is(err, service.ErrInvalidInput) {
		t.Fatalf("budget below spent amount must be rejected: %v", err)
	}
	campaign.Budget.Total = 100
	campaign.Budget.DailyLimit = 3
	if err := svc.Update(context.Background(), campaign); !errors.Is(err, service.ErrInvalidInput) {
		t.Fatalf("daily limit below today's spend must be rejected: %v", err)
	}

	stored, err := svc.GetByID(context.Background(), campaign.ID)
	if err != nil {
		t.Fatalf("get campaign: %v", err)
	}
	if math.Abs(stored.Budget.SpentTotal-25) > 1e-9 || math.Abs(stored.Budget.SpentToday-4) > 1e-9 {
		t.Fatalf("campaign spend is missing: %#v", stored.Budget)
	}
}
