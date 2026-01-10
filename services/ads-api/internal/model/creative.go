package model

type Creative struct {
	ID      int64 `db:"id" json:"id"`
	AdID    int64 `db:"ad_id" json:"ad_id"`
	Content int64 `db:"content" json:"content"`
}
