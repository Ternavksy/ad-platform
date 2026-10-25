package model

type Site struct {
	ID     int64  `db:"id" json:"id"`
	UserID int64  `db:"user_id" json:"user_id"`
	Name   string `db:"name" json:"name"`
	Domain string `db:"domain" json:"domain"`
	Status string `db:"status" json:"status"`
}

type AdFormat struct {
	ID     int64  `db:"id" json:"id"`
	Code   string `db:"code" json:"code"`
	Name   string `db:"name" json:"name"`
	Kind   string `db:"kind" json:"kind"`
	Width  int    `db:"width" json:"width"`
	Height int    `db:"height" json:"height"`
	Status string `db:"status" json:"status"`
}

type Placement struct {
	ID       int64  `db:"id" json:"id"`
	SiteID   int64  `db:"site_id" json:"site_id"`
	FormatID int64  `db:"format_id" json:"format_id"`
	Name     string `db:"name" json:"name"`
	Code     string `db:"code" json:"code"`
	Status   string `db:"status" json:"status"`
}
