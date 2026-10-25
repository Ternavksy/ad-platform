package model

import "time"

type DeliveryRequest struct {
	RequestID     string           `json:"request_id"`
	Placement     string           `json:"placement"`
	PlacementCode string           `json:"placement_code"`
	VisitorID     string           `json:"visitor_id"`
	Audience      AudienceContext  `json:"audience"`
	Geography     GeographyContext `json:"geography"`
	Device        DeviceContext    `json:"device"`
}

type DeliveryCandidate struct {
	CampaignID                int64      `db:"campaign_id"`
	AdID                      int64      `db:"ad_id"`
	CreativeID                int64      `db:"creative_id"`
	Title                     string     `db:"ad_title"`
	Content                   string     `db:"creative_content"`
	CreativeMediaType         string     `db:"creative_media_type"`
	CreativeMediaURL          string     `db:"creative_media_url"`
	CreativeMIMEType          string     `db:"creative_mime_type"`
	CreativeFileName          string     `db:"creative_file_name"`
	CreativeFileSize          int64      `db:"creative_file_size"`
	Placement                 string     `db:"placement"`
	DestinationURL            string     `db:"destination_url"`
	Weight                    int        `db:"weight"`
	BidCPM                    float64    `db:"bid_cpm"`
	CampaignBudgetTotal       float64    `db:"campaign_budget_total"`
	CampaignDailyLimit        float64    `db:"campaign_daily_limit"`
	CampaignSpentTotal        float64    `db:"campaign_spent_total"`
	CampaignSpentToday        float64    `db:"campaign_spent_today"`
	CampaignSpentDate         *time.Time `db:"campaign_spent_date"`
	CampaignStartsAt          *time.Time `db:"campaign_starts_at"`
	CampaignEndsAt            *time.Time `db:"campaign_ends_at"`
	CampaignScheduleDays      string     `db:"campaign_schedule_days"`
	CampaignScheduleStartHour int        `db:"campaign_schedule_start_hour"`
	CampaignScheduleEndHour   int        `db:"campaign_schedule_end_hour"`
	SiteID                    int64      `db:"site_id"`
	PlacementID               int64      `db:"placement_id"`
	FormatID                  int64      `db:"format_id"`
	PlacementCode             string     `db:"placement_code"`
	FormatCode                string     `db:"format_code"`
	FormatWidth               int        `db:"format_width"`
	FormatHeight              int        `db:"format_height"`
	TargetMinAge              int        `db:"target_min_age"`
	TargetMaxAge              int        `db:"target_max_age"`
	TargetGenders             string     `db:"target_genders"`
	TargetInterests           string     `db:"target_interests"`
	TargetCountries           string     `db:"target_countries"`
	TargetRegions             string     `db:"target_regions"`
	TargetCities              string     `db:"target_cities"`
	TargetDeviceTypes         string     `db:"target_device_types"`
	TargetOperatingSystems    string     `db:"target_operating_systems"`
}

type Delivery struct {
	ID                string           `db:"id" json:"delivery_id"`
	CampaignID        int64            `db:"campaign_id" json:"campaign_id"`
	AdID              int64            `db:"ad_id" json:"ad_id"`
	CreativeID        int64            `db:"creative_id" json:"creative_id"`
	Title             string           `db:"ad_title" json:"title"`
	Content           string           `db:"creative_content" json:"content"`
	Media             CreativeMedia    `db:"-" json:"media"`
	CreativeMediaType string           `db:"creative_media_type" json:"-"`
	CreativeMediaURL  string           `db:"creative_media_url" json:"-"`
	CreativeMIMEType  string           `db:"creative_mime_type" json:"-"`
	CreativeFileName  string           `db:"creative_file_name" json:"-"`
	CreativeFileSize  int64            `db:"creative_file_size" json:"-"`
	Placement         string           `db:"placement" json:"placement"`
	VisitorID         *string          `db:"visitor_id" json:"visitor_id,omitempty"`
	DestinationURL    string           `db:"destination_url" json:"destination_url"`
	CreatedAt         time.Time        `db:"created_at" json:"created_at"`
	ClickedAt         *time.Time       `db:"clicked_at" json:"clicked_at,omitempty"`
	ClickURL          string           `db:"-" json:"click_url"`
	SiteID            int64            `db:"site_id" json:"site_id"`
	PlacementID       int64            `db:"placement_id" json:"placement_id"`
	FormatID          int64            `db:"format_id" json:"format_id"`
	PlacementCode     string           `db:"placement_code" json:"placement_code,omitempty"`
	FormatCode        string           `db:"format_code" json:"format_code,omitempty"`
	FormatWidth       int              `db:"format_width" json:"format_width"`
	FormatHeight      int              `db:"format_height" json:"format_height"`
	BidCPM            float64          `db:"bid_cpm" json:"bid_cpm"`
	Cost              float64          `db:"cost" json:"cost"`
	Audience          AudienceContext  `db:"-" json:"audience"`
	Geography         GeographyContext `db:"-" json:"geography"`
	Device            DeviceContext    `db:"-" json:"device"`
	AudienceAge       int              `db:"audience_age" json:"-"`
	AudienceGender    string           `db:"audience_gender" json:"-"`
	AudienceInterests string           `db:"audience_interests" json:"-"`
	Country           string           `db:"country" json:"-"`
	Region            string           `db:"region" json:"-"`
	City              string           `db:"city" json:"-"`
	DeviceType        string           `db:"device_type" json:"-"`
	OperatingSystem   string           `db:"operating_system" json:"-"`
}

type DeliveryEvent struct {
	ID                string    `db:"id" json:"event_id"`
	DeliveryID        string    `db:"delivery_id" json:"delivery_id"`
	EventType         string    `db:"event_type" json:"type"`
	CampaignID        int64     `db:"campaign_id" json:"campaign_id"`
	AdID              int64     `db:"ad_id" json:"ad_id"`
	CreativeID        int64     `db:"creative_id" json:"creative_id"`
	Placement         string    `db:"placement" json:"placement"`
	OccurredAt        time.Time `db:"occurred_at" json:"occurred_at"`
	SiteID            int64     `db:"site_id" json:"site_id"`
	PlacementID       int64     `db:"placement_id" json:"placement_id"`
	FormatID          int64     `db:"format_id" json:"format_id"`
	PlacementCode     string    `db:"placement_code" json:"placement_code,omitempty"`
	FormatCode        string    `db:"format_code" json:"format_code,omitempty"`
	AudienceAge       int       `db:"audience_age" json:"audience_age"`
	AudienceGender    string    `db:"audience_gender" json:"audience_gender,omitempty"`
	AudienceInterests string    `db:"audience_interests" json:"audience_interests,omitempty"`
	Country           string    `db:"country" json:"country,omitempty"`
	Region            string    `db:"region" json:"region,omitempty"`
	City              string    `db:"city" json:"city,omitempty"`
	DeviceType        string    `db:"device_type" json:"device_type,omitempty"`
	OperatingSystem   string    `db:"operating_system" json:"operating_system,omitempty"`
	BidCPM            float64   `db:"bid_cpm" json:"bid_cpm"`
	Cost              float64   `db:"cost" json:"cost"`
}
