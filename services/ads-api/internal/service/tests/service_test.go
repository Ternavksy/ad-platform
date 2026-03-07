package service_test

import (
	"context"
	"testing"

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
        status TEXT NOT NULL
    );`)
	if err != nil {
		t.Fatalf("create campaigns: %v", err)
	}

	_, err = db.Exec(`CREATE TABLE ads(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        campaign_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL
    );`)
	if err != nil {
		t.Fatalf("create ads: %v", err)
	}

	return db
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
