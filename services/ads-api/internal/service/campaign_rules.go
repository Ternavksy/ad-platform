package service

import (
	"ads-api/internal/model"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"
)

const maxCampaignMoney = 1_000_000_000

func normalizeCampaign(campaign *model.Campaign, current *model.Campaign) error {
	campaign.Name = strings.TrimSpace(campaign.Name)
	campaign.Status = strings.ToLower(strings.TrimSpace(campaign.Status))
	if campaign.Name == "" || len(campaign.Name) > 255 {
		return ErrInvalidInput
	}
	if campaign.Status != "draft" && campaign.Status != "active" && campaign.Status != "paused" {
		return ErrInvalidInput
	}

	total := roundMoney(campaign.Budget.Total)
	daily := roundMoney(campaign.Budget.DailyLimit)
	if total < 0 || daily < 0 || total > maxCampaignMoney || daily > maxCampaignMoney {
		return ErrInvalidInput
	}
	if total > 0 && daily > total {
		return ErrInvalidInput
	}

	schedule := &campaign.Schedule
	if schedule.StartHour == 0 && schedule.EndHour == 0 {
		schedule.EndHour = 24
	}
	if schedule.StartHour < 0 || schedule.StartHour > 23 || schedule.EndHour < 1 || schedule.EndHour > 24 || schedule.StartHour == schedule.EndHour {
		return ErrInvalidInput
	}
	if schedule.StartsAt != nil {
		value := schedule.StartsAt.UTC()
		schedule.StartsAt = &value
	}
	if schedule.EndsAt != nil {
		value := schedule.EndsAt.UTC()
		schedule.EndsAt = &value
	}
	if schedule.StartsAt != nil && schedule.EndsAt != nil && !schedule.EndsAt.After(*schedule.StartsAt) {
		return ErrInvalidInput
	}
	days, err := normalizeScheduleDays(schedule.Days)
	if err != nil {
		return err
	}
	schedule.Days = days
	schedule.Timezone = "UTC"

	campaign.BudgetTotal = total
	campaign.DailyLimit = daily
	campaign.StartsAt = schedule.StartsAt
	campaign.EndsAt = schedule.EndsAt
	campaign.ScheduleDays = joinScheduleDays(days)
	campaign.ScheduleStartHour = schedule.StartHour
	campaign.ScheduleEndHour = schedule.EndHour
	if current == nil {
		campaign.SpentTotal = 0
		campaign.SpentToday = 0
		campaign.SpentDate = nil
	} else {
		campaign.SpentTotal = current.SpentTotal
		campaign.SpentToday = current.SpentToday
		campaign.SpentDate = current.SpentDate
		if total > 0 && total+1e-9 < campaign.SpentTotal {
			return ErrInvalidInput
		}
		currentToday := spentToday(current, time.Now().UTC())
		if daily > 0 && daily+1e-9 < currentToday {
			return ErrInvalidInput
		}
	}
	hydrateCampaign(campaign, time.Now().UTC())
	return nil
}

func hydrateCampaign(campaign *model.Campaign, now time.Time) {
	campaign.Budget = model.CampaignBudget{
		Total:      campaign.BudgetTotal,
		DailyLimit: campaign.DailyLimit,
		SpentTotal: campaign.SpentTotal,
		SpentToday: spentToday(campaign, now),
	}
	campaign.Schedule = model.CampaignSchedule{
		StartsAt:  campaign.StartsAt,
		EndsAt:    campaign.EndsAt,
		Days:      parseScheduleDays(campaign.ScheduleDays),
		StartHour: campaign.ScheduleStartHour,
		EndHour:   campaign.ScheduleEndHour,
		Timezone:  "UTC",
	}
}

func spentToday(campaign *model.Campaign, now time.Time) float64 {
	if campaign.SpentDate == nil || !sameUTCDate(*campaign.SpentDate, now) {
		return 0
	}
	return campaign.SpentToday
}

func sameUTCDate(left, right time.Time) bool {
	left, right = left.UTC(), right.UTC()
	return left.Year() == right.Year() && left.YearDay() == right.YearDay()
}

func campaignRunsAt(candidate model.DeliveryCandidate, now time.Time) bool {
	now = now.UTC()
	if candidate.CampaignStartsAt != nil && now.Before(candidate.CampaignStartsAt.UTC()) {
		return false
	}
	if candidate.CampaignEndsAt != nil && now.After(candidate.CampaignEndsAt.UTC()) {
		return false
	}
	days := parseScheduleDays(candidate.CampaignScheduleDays)
	if len(days) > 0 {
		weekday := int(now.Weekday())
		if weekday == 0 {
			weekday = 7
		}
		found := false
		for _, day := range days {
			if day == weekday {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	if candidate.CampaignScheduleStartHour < candidate.CampaignScheduleEndHour {
		return now.Hour() >= candidate.CampaignScheduleStartHour && now.Hour() < candidate.CampaignScheduleEndHour
	}
	return now.Hour() >= candidate.CampaignScheduleStartHour || now.Hour() < candidate.CampaignScheduleEndHour
}

func candidateHasBudget(candidate model.DeliveryCandidate, now time.Time) bool {
	cost := impressionCost(candidate.BidCPM)
	if candidate.CampaignBudgetTotal > 0 && candidate.CampaignSpentTotal+cost > candidate.CampaignBudgetTotal+1e-9 {
		return false
	}
	today := candidate.CampaignSpentToday
	if candidate.CampaignSpentDate == nil || !sameUTCDate(*candidate.CampaignSpentDate, now) {
		today = 0
	}
	return candidate.CampaignDailyLimit <= 0 || today+cost <= candidate.CampaignDailyLimit+1e-9
}

func impressionCost(bidCPM float64) float64 {
	return roundMoney(bidCPM / 1000)
}

func candidateSelectionWeight(candidate model.DeliveryCandidate) uint64 {
	bidUnits := uint64(math.Round(candidate.BidCPM * 100))
	if bidUnits == 0 {
		bidUnits = 1
	}
	return uint64(candidate.Weight) * bidUnits
}

func roundMoney(value float64) float64 {
	return math.Round(value*1_000_000) / 1_000_000
}

func normalizeScheduleDays(values []int) ([]int, error) {
	seen := map[int]struct{}{}
	for _, value := range values {
		if value < 1 || value > 7 {
			return nil, ErrInvalidInput
		}
		seen[value] = struct{}{}
	}
	result := make([]int, 0, len(seen))
	for value := range seen {
		result = append(result, value)
	}
	sort.Ints(result)
	return result, nil
}

func joinScheduleDays(days []int) string {
	parts := make([]string, len(days))
	for index, day := range days {
		parts[index] = strconv.Itoa(day)
	}
	return strings.Join(parts, ",")
}

func parseScheduleDays(value string) []int {
	if value == "" {
		return []int{}
	}
	result := make([]int, 0, 7)
	for _, item := range strings.Split(value, ",") {
		day, err := strconv.Atoi(item)
		if err == nil && day >= 1 && day <= 7 {
			result = append(result, day)
		}
	}
	return result
}
