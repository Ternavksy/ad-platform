package model

type AudienceTargeting struct {
	MinAge    int      `json:"min_age"`
	MaxAge    int      `json:"max_age"`
	Genders   []string `json:"genders"`
	Interests []string `json:"interests"`
}

type GeographyTargeting struct {
	Countries []string `json:"countries"`
	Regions   []string `json:"regions"`
	Cities    []string `json:"cities"`
}

type DeviceTargeting struct {
	Types            []string `json:"types"`
	OperatingSystems []string `json:"operating_systems"`
}

type AdTargeting struct {
	Audience  AudienceTargeting  `json:"audience"`
	Geography GeographyTargeting `json:"geography"`
	Device    DeviceTargeting    `json:"device"`
}

type AudienceContext struct {
	Age       int      `json:"age"`
	Gender    string   `json:"gender"`
	Interests []string `json:"interests"`
}

type GeographyContext struct {
	Country string `json:"country"`
	Region  string `json:"region"`
	City    string `json:"city"`
}

type DeviceContext struct {
	Type            string `json:"type"`
	OperatingSystem string `json:"operating_system"`
}
