package model

import "time"

type CampaignBudget struct {
	Total      float64 `json:"total"`
	DailyLimit float64 `json:"daily_limit"`
	SpentTotal float64 `json:"spent_total"`
	SpentToday float64 `json:"spent_today"`
}

type CampaignSchedule struct {
	StartsAt  *time.Time `json:"starts_at,omitempty"`
	EndsAt    *time.Time `json:"ends_at,omitempty"`
	Days      []int      `json:"days_of_week"`
	StartHour int        `json:"start_hour"`
	EndHour   int        `json:"end_hour"`
	Timezone  string     `json:"timezone"`
}

type Campaign struct {
	ID                int64            `db:"id" json:"id"`
	UserID            int64            `db:"user_id" json:"user_id"`
	Name              string           `db:"name" json:"name"`
	Status            string           `db:"status" json:"status"`
	Budget            CampaignBudget   `db:"-" json:"budget"`
	Schedule          CampaignSchedule `db:"-" json:"schedule"`
	BudgetTotal       float64          `db:"budget_total" json:"-"`
	DailyLimit        float64          `db:"daily_limit" json:"-"`
	SpentTotal        float64          `db:"spent_total" json:"-"`
	SpentToday        float64          `db:"spent_today" json:"-"`
	SpentDate         *time.Time       `db:"spent_date" json:"-"`
	StartsAt          *time.Time       `db:"starts_at" json:"-"`
	EndsAt            *time.Time       `db:"ends_at" json:"-"`
	ScheduleDays      string           `db:"schedule_days" json:"-"`
	ScheduleStartHour int              `db:"schedule_start_hour" json:"-"`
	ScheduleEndHour   int              `db:"schedule_end_hour" json:"-"`
}
