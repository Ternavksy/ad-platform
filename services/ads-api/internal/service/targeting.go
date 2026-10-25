package service

import (
	"ads-api/internal/model"
	"regexp"
	"strings"
)

var countryPattern = regexp.MustCompile(`^[A-Z]{2}$`)

var allowedGenders = map[string]bool{
	"male": true, "female": true, "non_binary": true,
}

var allowedContextGenders = map[string]bool{
	"male": true, "female": true, "non_binary": true, "unknown": true,
}

var allowedDeviceTypes = map[string]bool{
	"mobile": true, "tablet": true, "desktop": true, "tv": true, "other": true,
}

var allowedOperatingSystems = map[string]bool{
	"android": true, "ios": true, "windows": true, "macos": true, "linux": true, "other": true,
}

func normalizeAdTargeting(ad *model.Ad) error {
	targeting := &ad.Targeting
	if (targeting.Audience.MinAge != 0 && (targeting.Audience.MinAge < 1 || targeting.Audience.MinAge > 120)) ||
		(targeting.Audience.MaxAge != 0 && (targeting.Audience.MaxAge < 1 || targeting.Audience.MaxAge > 120)) ||
		(targeting.Audience.MinAge != 0 && targeting.Audience.MaxAge != 0 && targeting.Audience.MinAge > targeting.Audience.MaxAge) {
		return ErrInvalidInput
	}

	var err error
	targeting.Audience.Genders, err = normalizeList(targeting.Audience.Genders, 3, 32, false, allowedGenders)
	if err != nil {
		return err
	}
	targeting.Audience.Interests, err = normalizeList(targeting.Audience.Interests, 50, 64, false, nil)
	if err != nil {
		return err
	}
	targeting.Geography.Countries, err = normalizeCountries(targeting.Geography.Countries)
	if err != nil {
		return err
	}
	targeting.Geography.Regions, err = normalizeList(targeting.Geography.Regions, 50, 128, false, nil)
	if err != nil {
		return err
	}
	targeting.Geography.Cities, err = normalizeList(targeting.Geography.Cities, 50, 128, false, nil)
	if err != nil {
		return err
	}
	targeting.Device.Types, err = normalizeList(targeting.Device.Types, 5, 32, false, allowedDeviceTypes)
	if err != nil {
		return err
	}
	targeting.Device.OperatingSystems, err = normalizeList(targeting.Device.OperatingSystems, 6, 32, false, allowedOperatingSystems)
	if err != nil {
		return err
	}

	ad.TargetMinAge = targeting.Audience.MinAge
	ad.TargetMaxAge = targeting.Audience.MaxAge
	ad.TargetGenders = strings.Join(targeting.Audience.Genders, ",")
	ad.TargetInterests = strings.Join(targeting.Audience.Interests, ",")
	ad.TargetCountries = strings.Join(targeting.Geography.Countries, ",")
	ad.TargetRegions = strings.Join(targeting.Geography.Regions, ",")
	ad.TargetCities = strings.Join(targeting.Geography.Cities, ",")
	ad.TargetDeviceTypes = strings.Join(targeting.Device.Types, ",")
	ad.TargetOperatingSystems = strings.Join(targeting.Device.OperatingSystems, ",")
	return nil
}

func hydrateAdTargeting(ad *model.Ad) {
	ad.Targeting = model.AdTargeting{
		Audience: model.AudienceTargeting{
			MinAge: ad.TargetMinAge, MaxAge: ad.TargetMaxAge,
			Genders: splitList(ad.TargetGenders), Interests: splitList(ad.TargetInterests),
		},
		Geography: model.GeographyTargeting{
			Countries: splitList(ad.TargetCountries), Regions: splitList(ad.TargetRegions), Cities: splitList(ad.TargetCities),
		},
		Device: model.DeviceTargeting{
			Types: splitList(ad.TargetDeviceTypes), OperatingSystems: splitList(ad.TargetOperatingSystems),
		},
	}
}

func normalizeDeliveryContext(req *model.DeliveryRequest) error {
	if req.Audience.Age < 0 || req.Audience.Age > 120 {
		return ErrInvalidInput
	}
	req.Audience.Gender = strings.ToLower(strings.TrimSpace(req.Audience.Gender))
	if req.Audience.Gender != "" && !allowedContextGenders[req.Audience.Gender] {
		return ErrInvalidInput
	}
	interests, err := normalizeList(req.Audience.Interests, 50, 64, false, nil)
	if err != nil {
		return err
	}
	req.Audience.Interests = interests

	req.Geography.Country = strings.ToUpper(strings.TrimSpace(req.Geography.Country))
	if req.Geography.Country != "" && !countryPattern.MatchString(req.Geography.Country) {
		return ErrInvalidInput
	}
	region, err := normalizeContextValue(req.Geography.Region, 128)
	if err != nil {
		return err
	}
	city, err := normalizeContextValue(req.Geography.City, 128)
	if err != nil {
		return err
	}
	req.Geography.Region = region
	req.Geography.City = city

	req.Device.Type = strings.ToLower(strings.TrimSpace(req.Device.Type))
	if req.Device.Type != "" && !allowedDeviceTypes[req.Device.Type] {
		return ErrInvalidInput
	}
	req.Device.OperatingSystem = strings.ToLower(strings.TrimSpace(req.Device.OperatingSystem))
	if req.Device.OperatingSystem != "" && !allowedOperatingSystems[req.Device.OperatingSystem] {
		return ErrInvalidInput
	}
	return nil
}

func matchesTargeting(item model.DeliveryCandidate, req model.DeliveryRequest) bool {
	if item.TargetMinAge > 0 && (req.Audience.Age == 0 || req.Audience.Age < item.TargetMinAge) {
		return false
	}
	if item.TargetMaxAge > 0 && (req.Audience.Age == 0 || req.Audience.Age > item.TargetMaxAge) {
		return false
	}
	if !matchesValue(item.TargetGenders, req.Audience.Gender) ||
		!matchesAny(item.TargetInterests, req.Audience.Interests) ||
		!matchesValue(item.TargetCountries, req.Geography.Country) ||
		!matchesValue(item.TargetRegions, req.Geography.Region) ||
		!matchesValue(item.TargetCities, req.Geography.City) ||
		!matchesValue(item.TargetDeviceTypes, req.Device.Type) ||
		!matchesValue(item.TargetOperatingSystems, req.Device.OperatingSystem) {
		return false
	}
	return true
}

func normalizeList(values []string, maxCount, maxLength int, upper bool, allowed map[string]bool) ([]string, error) {
	if len(values) > maxCount {
		return nil, ErrInvalidInput
	}
	result := make([]string, 0, len(values))
	seen := make(map[string]bool, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if upper {
			value = strings.ToUpper(value)
		} else {
			value = strings.ToLower(value)
		}
		if value == "" {
			continue
		}
		if len(value) > maxLength || strings.Contains(value, ",") || (allowed != nil && !allowed[value]) {
			return nil, ErrInvalidInput
		}
		if !seen[value] {
			result = append(result, value)
			seen[value] = true
		}
	}
	return result, nil
}

func normalizeCountries(values []string) ([]string, error) {
	result, err := normalizeList(values, 50, 2, true, nil)
	if err != nil {
		return nil, err
	}
	for _, value := range result {
		if !countryPattern.MatchString(value) {
			return nil, ErrInvalidInput
		}
	}
	return result, nil
}

func normalizeContextValue(value string, maxLength int) (string, error) {
	value = strings.ToLower(strings.TrimSpace(value))
	if len(value) > maxLength || strings.Contains(value, ",") {
		return "", ErrInvalidInput
	}
	return value, nil
}

func splitList(value string) []string {
	if value == "" {
		return []string{}
	}
	return strings.Split(value, ",")
}

func matchesValue(configured, actual string) bool {
	if configured == "" {
		return true
	}
	if actual == "" {
		return false
	}
	for _, item := range strings.Split(configured, ",") {
		if item == actual {
			return true
		}
	}
	return false
}

func matchesAny(configured string, actual []string) bool {
	if configured == "" {
		return true
	}
	if len(actual) == 0 {
		return false
	}
	values := make(map[string]bool, len(actual))
	for _, item := range actual {
		values[item] = true
	}
	for _, item := range strings.Split(configured, ",") {
		if values[item] {
			return true
		}
	}
	return false
}
