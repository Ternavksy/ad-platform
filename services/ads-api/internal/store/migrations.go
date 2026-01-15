package store

import (
	"os"

	"github.com/jmoiron/sqlx"
)

func RunMigrations(db *sqlx.DB) error {
	files := []string{
		"migrations/001_create_campaigns.sql",
		"migrations/002_create_ads.sql",
	}
	for _, file := range files {
		sql, err := os.ReadFile(file)
		if err != nil {
			return err
		}
		if _, err := db.Exec(string(sql)); err != nil {
			return err
		}
	}
	return nil
}
