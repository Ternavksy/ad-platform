package store

import (
	"ads-api/internal/model"
	"context"

	"github.com/jmoiron/sqlx"
)

type CampaignStore struct {
	db *sqlx.DB
}

func NewCampaignStore(db *sqlx.DB) *CampaignStore {
	return &CampaignStore{db: db}
}

func (s *CampaignStore) Create(ctx context.Context, c *model.Campaign) error {
	query := `
		INSERT INTO campaigns (
			user_id, name, status, budget_total, daily_limit, spent_total,
			spent_today, spent_date, starts_at, ends_at, schedule_days,
			schedule_start_hour, schedule_end_hour)
		VALUES (?, ?, ?, ?, ?, 0, 0, NULL, ?, ?, ?, ?, ?)
	`
	res, err := s.db.ExecContext(ctx, query, c.UserID, c.Name, c.Status,
		c.BudgetTotal, c.DailyLimit, c.StartsAt, c.EndsAt, c.ScheduleDays,
		c.ScheduleStartHour, c.ScheduleEndHour)
	if err != nil {
		return err
	}
	c.ID, _ = res.LastInsertId()
	return nil
}

func (s *CampaignStore) GetByID(ctx context.Context, id int64) (*model.Campaign, error) {
	var c model.Campaign
	err := s.db.GetContext(ctx, &c, `
	SELECT id, user_id, name, status, budget_total, daily_limit, spent_total,
	       spent_today, spent_date, starts_at, ends_at, schedule_days,
	       schedule_start_hour, schedule_end_hour
	FROM campaigns
	WHERE id = ?
	`, id)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (s *CampaignStore) ListByUser(ctx context.Context, userID int64) ([]model.Campaign, error) {
	items := make([]model.Campaign, 0)
	err := s.db.SelectContext(ctx, &items, `
		SELECT id, user_id, name, status, budget_total, daily_limit, spent_total,
		       spent_today, spent_date, starts_at, ends_at, schedule_days,
		       schedule_start_hour, schedule_end_hour
		FROM campaigns
		WHERE user_id = ?
		ORDER BY id DESC
	`, userID)
	return items, err
}

func (s *CampaignStore) Update(ctx context.Context, c *model.Campaign) error {
	query := `
		UPDATE campaigns
		SET name = ?, status = ?, budget_total = ?, daily_limit = ?,
		    starts_at = ?, ends_at = ?, schedule_days = ?,
		    schedule_start_hour = ?, schedule_end_hour = ?
		WHERE id = ?
	`
	_, err := s.db.ExecContext(ctx, query, c.Name, c.Status, c.BudgetTotal,
		c.DailyLimit, c.StartsAt, c.EndsAt, c.ScheduleDays,
		c.ScheduleStartHour, c.ScheduleEndHour, c.ID)
	return err
}

func (s *CampaignStore) Delete(ctx context.Context, id int64) error {
	query := `DELETE FROM campaigns WHERE id = ?`
	_, err := s.db.ExecContext(ctx, query, id)
	return err
}
