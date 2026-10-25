package service

import (
	"ads-api/internal/model"
	"ads-api/internal/store"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"hash/fnv"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
)

var placementPattern = regexp.MustCompile(`^[a-z0-9_-]{1,64}$`)

type DeliveryService struct {
	store *store.DeliveryStore
}

func NewDeliveryService(s *store.DeliveryStore) *DeliveryService {
	return &DeliveryService{store: s}
}

func (s *DeliveryService) Select(ctx context.Context, req model.DeliveryRequest) (*model.Delivery, error) {
	req.Placement = strings.TrimSpace(strings.ToLower(req.Placement))
	req.PlacementCode = strings.TrimSpace(strings.ToLower(req.PlacementCode))
	if req.Placement == "" {
		req.Placement = "feed"
	}
	if !placementPattern.MatchString(req.Placement) || len(req.VisitorID) > 128 {
		return nil, ErrInvalidInput
	}
	if err := normalizeDeliveryContext(&req); err != nil {
		return nil, err
	}
	if req.PlacementCode != "" {
		parsed, err := uuid.Parse(req.PlacementCode)
		if err != nil {
			return nil, ErrInvalidInput
		}
		req.PlacementCode = parsed.String()
	}

	if req.RequestID == "" {
		req.RequestID = uuid.NewString()
	} else {
		parsed, err := uuid.Parse(req.RequestID)
		if err != nil {
			return nil, ErrInvalidInput
		}
		req.RequestID = parsed.String()
	}

	if existing, err := s.store.GetByID(ctx, req.RequestID); err == nil {
		setClickURL(existing)
		return existing, nil
	} else if !errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("get existing delivery: %w", err)
	}

	var candidates []model.DeliveryCandidate
	var err error
	if req.PlacementCode != "" {
		candidates, err = s.store.ListCandidatesByCode(ctx, req.PlacementCode)
	} else {
		candidates, err = s.store.ListCandidates(ctx, req.Placement)
	}
	if err != nil {
		return nil, fmt.Errorf("list delivery candidates: %w", err)
	}
	if len(candidates) == 0 {
		return nil, ErrNoDelivery
	}
	now := time.Now().UTC()
	eligible := candidates[:0]
	for _, candidate := range candidates {
		if matchesTargeting(candidate, req) && campaignRunsAt(candidate, now) && candidateHasBudget(candidate, now) {
			eligible = append(eligible, candidate)
		}
	}
	candidates = eligible
	if len(candidates) == 0 {
		return nil, ErrNoDelivery
	}

	groups := groupCandidates(candidates)
	target := req.Placement
	if req.PlacementCode != "" {
		target = req.PlacementCode
	}
	seed := deliveryHash(req.RequestID + "|" + req.VisitorID + "|" + target)
	var totalWeight uint64
	for _, group := range groups {
		totalWeight += candidateSelectionWeight(group[0])
	}
	ticket := seed % totalWeight
	selected := groups[len(groups)-1]
	for _, group := range groups {
		weight := candidateSelectionWeight(group[0])
		if ticket < weight {
			selected = group
			break
		}
		ticket -= weight
	}
	candidate := selected[int((seed/(totalWeight+1))%uint64(len(selected)))]

	var visitorID *string
	if req.VisitorID != "" {
		visitorID = &req.VisitorID
	}
	item := &model.Delivery{
		ID:                req.RequestID,
		CampaignID:        candidate.CampaignID,
		AdID:              candidate.AdID,
		CreativeID:        candidate.CreativeID,
		Title:             candidate.Title,
		Content:           candidate.Content,
		CreativeMediaType: candidate.CreativeMediaType,
		CreativeMediaURL:  candidate.CreativeMediaURL,
		CreativeMIMEType:  candidate.CreativeMIMEType,
		CreativeFileName:  candidate.CreativeFileName,
		CreativeFileSize:  candidate.CreativeFileSize,
		Placement:         candidate.Placement,
		VisitorID:         visitorID,
		DestinationURL:    candidate.DestinationURL,
		CreatedAt:         now,
		SiteID:            candidate.SiteID,
		PlacementID:       candidate.PlacementID,
		FormatID:          candidate.FormatID,
		PlacementCode:     candidate.PlacementCode,
		FormatCode:        candidate.FormatCode,
		FormatWidth:       candidate.FormatWidth,
		FormatHeight:      candidate.FormatHeight,
		BidCPM:            candidate.BidCPM,
		Cost:              impressionCost(candidate.BidCPM),
		Audience:          req.Audience,
		Geography:         req.Geography,
		Device:            req.Device,
		AudienceAge:       req.Audience.Age,
		AudienceGender:    req.Audience.Gender,
		AudienceInterests: strings.Join(req.Audience.Interests, ","),
		Country:           req.Geography.Country,
		Region:            req.Geography.Region,
		City:              req.Geography.City,
		DeviceType:        req.Device.Type,
		OperatingSystem:   req.Device.OperatingSystem,
	}
	if err := s.store.Create(ctx, item); err != nil {
		// A concurrent retry with the same request ID may have won the insert.
		if existing, getErr := s.store.GetByID(ctx, req.RequestID); getErr == nil {
			setClickURL(existing)
			return existing, nil
		}
		if errors.Is(err, store.ErrBudgetExhausted) {
			return nil, ErrNoDelivery
		}
		return nil, fmt.Errorf("create delivery: %w", err)
	}
	setClickURL(item)
	return item, nil
}

func (s *DeliveryService) TrackClick(ctx context.Context, id string) (*model.Delivery, error) {
	if _, err := uuid.Parse(id); err != nil {
		return nil, ErrNotFound
	}
	item, err := s.store.TrackClick(ctx, id, time.Now().UTC())
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("track click: %w", err)
	}
	setClickURL(item)
	return item, nil
}

func groupCandidates(items []model.DeliveryCandidate) [][]model.DeliveryCandidate {
	groups := make([][]model.DeliveryCandidate, 0)
	for _, item := range items {
		if len(groups) == 0 || groups[len(groups)-1][0].AdID != item.AdID {
			groups = append(groups, []model.DeliveryCandidate{item})
		} else {
			groups[len(groups)-1] = append(groups[len(groups)-1], item)
		}
	}
	return groups
}

func deliveryHash(value string) uint64 {
	h := fnv.New64a()
	_, _ = h.Write([]byte(value))
	return h.Sum64()
}

func setClickURL(item *model.Delivery) {
	item.ClickURL = "/delivery/" + item.ID + "/click"
	item.Media = model.CreativeMedia{
		Type:     item.CreativeMediaType,
		URL:      item.CreativeMediaURL,
		MIMEType: item.CreativeMIMEType,
		FileName: item.CreativeFileName,
		FileSize: item.CreativeFileSize,
	}
	item.Audience = model.AudienceContext{Age: item.AudienceAge, Gender: item.AudienceGender, Interests: splitList(item.AudienceInterests)}
	item.Geography = model.GeographyContext{Country: item.Country, Region: item.Region, City: item.City}
	item.Device = model.DeviceContext{Type: item.DeviceType, OperatingSystem: item.OperatingSystem}
}

func normalizeAd(ad *model.Ad) error {
	ad.Title = strings.TrimSpace(ad.Title)
	ad.Status = strings.TrimSpace(strings.ToLower(ad.Status))
	ad.Placement = strings.TrimSpace(strings.ToLower(ad.Placement))
	ad.DestinationURL = strings.TrimSpace(ad.DestinationURL)
	if ad.Placement == "" {
		ad.Placement = "feed"
	}
	if ad.Weight == 0 {
		ad.Weight = 1
	}
	if ad.BidCPM == 0 {
		ad.BidCPM = 1
	}
	ad.BidCPM = roundMoney(ad.BidCPM)
	if ad.Title == "" || len(ad.Title) > 255 || !placementPattern.MatchString(ad.Placement) ||
		len(ad.DestinationURL) > 2048 || ad.Weight < 1 || ad.Weight > 1000 ||
		ad.BidCPM < 0.01 || ad.BidCPM > 1_000_000 {
		return ErrInvalidInput
	}
	if ad.Status != "draft" && ad.Status != "active" && ad.Status != "paused" {
		return ErrInvalidInput
	}
	if ad.DestinationURL != "" {
		parsed, err := url.ParseRequestURI(ad.DestinationURL)
		if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
			return ErrInvalidInput
		}
	}
	return normalizeAdTargeting(ad)
}
