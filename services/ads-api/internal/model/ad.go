package model

type Ad struct {
	ID                     int64       `db:"id" json:"id"`
	CampaignID             int64       `db:"campaign_id" json:"campaign_id"`
	PlacementID            *int64      `db:"placement_id" json:"placement_id,omitempty"`
	Title                  string      `db:"title" json:"title"`
	Status                 string      `db:"status" json:"status"`
	Placement              string      `db:"placement" json:"placement"`
	DestinationURL         string      `db:"destination_url" json:"destination_url"`
	Weight                 int         `db:"weight" json:"weight"`
	BidCPM                 float64     `db:"bid_cpm" json:"bid_cpm"`
	Targeting              AdTargeting `db:"-" json:"targeting"`
	TargetMinAge           int         `db:"target_min_age" json:"-"`
	TargetMaxAge           int         `db:"target_max_age" json:"-"`
	TargetGenders          string      `db:"target_genders" json:"-"`
	TargetInterests        string      `db:"target_interests" json:"-"`
	TargetCountries        string      `db:"target_countries" json:"-"`
	TargetRegions          string      `db:"target_regions" json:"-"`
	TargetCities           string      `db:"target_cities" json:"-"`
	TargetDeviceTypes      string      `db:"target_device_types" json:"-"`
	TargetOperatingSystems string      `db:"target_operating_systems" json:"-"`
}
