package model

type Campaign struct {
	ID     int64  `db:"id" json:"id"`
	UserID int64  `db:"user_id" json:"user_id"`
	Name   string `db:"name" json:"name"`
	Status string `db:"status" json:"status"`
}
