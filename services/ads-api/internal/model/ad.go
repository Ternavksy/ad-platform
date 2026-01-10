package model

type Ad struct {
	ID         int64  `db:"id" json:"id"`
	CampaignID int64  `db:"campaign_id" json:"campaign_id"`
	Title      string `db:"title" json:"title"`
	Status     string `db:"status" json:"status"`
}
