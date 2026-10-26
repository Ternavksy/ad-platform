package service

import (
	"ads-api/internal/model"
	"ads-api/internal/store"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
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
var trackingEventIDPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)
var conversionTypePattern = regexp.MustCompile(`^[a-z][a-z0-9_-]{0,63}$`)
var currencyPattern = regexp.MustCompile(`^[A-Z]{3}$`)

const (
	lastClickWindow   = 7 * 24 * time.Hour
	viewThroughWindow = 24 * time.Hour
)

type DeliveryService struct {
	store *store.DeliveryStore
}

func NewDeliveryService(s *store.DeliveryStore) *DeliveryService {
	return &DeliveryService{store: s}
}

func (s *DeliveryService) Select(ctx context.Context, req model.DeliveryRequest) (*model.Delivery, error) {
	if suspiciousUserAgent(req.UserAgent) {
		return nil, ErrNoDelivery
	}
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
		setTrackingURLs(existing)
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
		SourceIPHash:      privacyHash(req.SourceIP),
		UserAgentHash:     privacyHash(req.UserAgent),
	}
	if err := s.store.Create(ctx, item); err != nil {
		// A concurrent retry with the same request ID may have won the insert.
		if existing, getErr := s.store.GetByID(ctx, req.RequestID); getErr == nil {
			setTrackingURLs(existing)
			return existing, nil
		}
		if errors.Is(err, store.ErrBudgetExhausted) {
			return nil, ErrNoDelivery
		}
		return nil, fmt.Errorf("create delivery: %w", err)
	}
	setTrackingURLs(item)
	return item, nil
}

func (s *DeliveryService) TrackImpression(ctx context.Context, id string) (*model.TrackingResult, error) {
	if _, err := uuid.Parse(id); err != nil {
		return nil, ErrNotFound
	}
	_, result, err := s.store.TrackImpression(ctx, id, time.Now().UTC())
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("track impression: %w", err)
	}
	return result, nil
}

func (s *DeliveryService) TrackClick(ctx context.Context, id string) (*model.Delivery, *model.TrackingResult, error) {
	if _, err := uuid.Parse(id); err != nil {
		return nil, nil, ErrNotFound
	}
	item, result, err := s.store.TrackClick(ctx, id, time.Now().UTC())
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil, ErrNotFound
	}
	if err != nil {
		return nil, nil, fmt.Errorf("track click: %w", err)
	}
	setTrackingURLs(item)
	return item, result, nil
}

func (s *DeliveryService) TrackConversion(
	ctx context.Context,
	id string,
	req model.ConversionRequest,
) (*model.TrackingResult, error) {
	if _, err := uuid.Parse(id); err != nil {
		return nil, ErrNotFound
	}
	if err := normalizeConversionRequest(&req); err != nil {
		return nil, ErrInvalidInput
	}
	now := time.Now().UTC()
	item, err := s.store.GetByID(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get delivery for conversion: %w", err)
	}
	attributionModel, attributionWindow := deliveryAttribution(item, now)
	_, result, err := s.store.TrackConversion(
		ctx, id, req, now, attributionModel, attributionWindow,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if errors.Is(err, store.ErrEventConflict) {
		return nil, ErrConflict
	}
	if err != nil {
		return nil, fmt.Errorf("track conversion: %w", err)
	}
	return result, nil
}

func (s *DeliveryService) TrackAttributedConversion(
	ctx context.Context,
	req model.AttributionConversionRequest,
) (*model.TrackingResult, error) {
	req.VisitorID = strings.TrimSpace(req.VisitorID)
	if req.VisitorID == "" || len(req.VisitorID) > 128 {
		return nil, ErrInvalidInput
	}
	if err := normalizeConversionRequest(&req.ConversionRequest); err != nil {
		return nil, ErrInvalidInput
	}
	now := time.Now().UTC()
	item, attributionModel, attributionWindow, err := s.store.FindAttributedDelivery(
		ctx, req.VisitorID, now, lastClickWindow, viewThroughWindow,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("find attribution: %w", err)
	}
	_, result, err := s.store.TrackConversion(
		ctx,
		item.ID,
		req.ConversionRequest,
		now,
		attributionModel,
		attributionWindow,
	)
	if errors.Is(err, store.ErrEventConflict) {
		return nil, ErrConflict
	}
	if err != nil {
		return nil, fmt.Errorf("track attributed conversion: %w", err)
	}
	return result, nil
}

func normalizeConversionRequest(req *model.ConversionRequest) error {
	req.EventID = strings.TrimSpace(req.EventID)
	if req.EventID == "" {
		req.EventID = uuid.NewString()
	}
	req.ConversionType = strings.TrimSpace(strings.ToLower(req.ConversionType))
	if req.ConversionType == "" {
		req.ConversionType = "purchase"
	}
	req.Currency = strings.TrimSpace(strings.ToUpper(req.Currency))
	req.Value = roundMoney(req.Value)
	if !trackingEventIDPattern.MatchString(req.EventID) ||
		!conversionTypePattern.MatchString(req.ConversionType) ||
		req.Value < 0 || req.Value > 99_999_999 ||
		(req.Currency != "" && !currencyPattern.MatchString(req.Currency)) ||
		(req.Value > 0 && req.Currency == "") {
		return ErrInvalidInput
	}
	return nil
}

func deliveryAttribution(item *model.Delivery, now time.Time) (string, int) {
	if item.ClickedAt != nil && !item.ClickIsFraud && now.Sub(*item.ClickedAt) <= lastClickWindow {
		return "last_click", int(lastClickWindow / time.Hour)
	}
	return "view_through", int(viewThroughWindow / time.Hour)
}

func suspiciousUserAgent(value string) bool {
	value = strings.ToLower(value)
	for _, marker := range []string{"bot", "spider", "crawler", "headless", "phantomjs"} {
		if strings.Contains(value, marker) {
			return true
		}
	}
	return false
}

func privacyHash(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
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

func setTrackingURLs(item *model.Delivery) {
	item.ImpressionURL = "/delivery/" + item.ID + "/impression"
	item.ClickURL = "/delivery/" + item.ID + "/click"
	item.ConversionURL = "/delivery/" + item.ID + "/conversion"
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
