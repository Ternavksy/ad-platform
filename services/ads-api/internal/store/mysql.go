package store

import (
	"context"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
)

func NewMySQL(dsn string) (*sqlx.DB, error) {
	var err error

	for i := 1; i <= 10; i++ {
		db, err := sqlx.Connect("mysql", dsn)
		if err != nil {
			time.Sleep(2 * time.Second)
			continue
		}

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		err = db.PingContext(ctx)
		cancel()

		if err == nil {
			db.SetConnMaxLifetime(time.Minute * 3)
			db.SetMaxOpenConns(25)
			db.SetMaxIdleConns(25)
			return db, nil
		}

		time.Sleep(2 * time.Second)
	}

	return nil, err
}
