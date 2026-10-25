package model

import "time"

type CreativeMedia struct {
	Type     string `json:"type"`
	URL      string `json:"url,omitempty"`
	MIMEType string `json:"mime_type,omitempty"`
	FileName string `json:"file_name,omitempty"`
	FileSize int64  `json:"file_size,omitempty"`
}

type Creative struct {
	ID               int64         `db:"id" json:"id"`
	AdID             int64         `db:"ad_id" json:"ad_id"`
	Content          string        `db:"content" json:"content"`
	Media            CreativeMedia `db:"-" json:"media"`
	MediaType        string        `db:"media_type" json:"-"`
	MediaURL         string        `db:"media_url" json:"-"`
	MediaPath        string        `db:"media_path" json:"-"`
	MIMEType         string        `db:"mime_type" json:"-"`
	FileName         string        `db:"file_name" json:"-"`
	FileSize         int64         `db:"file_size" json:"-"`
	ModerationStatus string        `db:"moderation_status" json:"moderation_status"`
	ModerationReason string        `db:"moderation_reason" json:"moderation_reason,omitempty"`
	SubmittedAt      *time.Time    `db:"submitted_at" json:"submitted_at,omitempty"`
	ReviewedAt       *time.Time    `db:"reviewed_at" json:"reviewed_at,omitempty"`
	ReviewedBy       *int64        `db:"reviewed_by" json:"reviewed_by,omitempty"`
	AdTitle          string        `db:"ad_title" json:"ad_title,omitempty"`
	CampaignName     string        `db:"campaign_name" json:"campaign_name,omitempty"`
	OwnerUserID      int64         `db:"owner_user_id" json:"owner_user_id,omitempty"`
}

type ModerationDecision struct {
	Decision string `json:"decision"`
	Reason   string `json:"reason"`
}
