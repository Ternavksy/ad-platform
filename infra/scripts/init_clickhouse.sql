CREATE TABLE IF NOT EXISTS ads_stats (
    date Date,
    campaign_id UInt64,
    ad_id UInt64,
    creative_id UInt64,
    impressions UInt64,
    clicks UInt64,
    cost Float64,
    timestamp DateTime
) ENGINE = MergeTree()
ORDER BY (date, campaign_id, ad_id, creative_id, timestamp);

CREATE TABLE IF NOT EXISTS campaign_stats (
    date Date,
    campaign_id UInt64,
    impressions UInt64,
    clicks UInt64,
    cost Float64,
    timestamp DateTime
) ENGINE = MergeTree()
ORDER BY (date, campaign_id, timestamp);

CREATE TABLE IF NOT EXISTS creative_stats (
    date Date,
    creative_id UInt64,
    impressions UInt64,
    clicks UInt64,
    cost Float64,
    timestamp DateTime
) ENGINE = MergeTree()
ORDER BY (date, creative_id, timestamp);

CREATE TABLE IF NOT EXISTS delivery_stats (
    event_id String,
    delivery_id String,
    date Date,
    campaign_id UInt64,
    ad_id UInt64,
    creative_id UInt64,
    placement LowCardinality(String),
    site_id UInt64,
    placement_id UInt64,
    format_id UInt64,
    placement_code String,
    format_code LowCardinality(String),
    audience_age UInt16,
    audience_gender LowCardinality(String),
    audience_interests String,
    country LowCardinality(String),
    region LowCardinality(String),
    city LowCardinality(String),
    device_type LowCardinality(String),
    operating_system LowCardinality(String),
    impressions UInt8,
    clicks UInt8,
    conversions UInt8,
    conversion_value Float64,
    conversion_type LowCardinality(String),
    conversion_currency LowCardinality(String),
    cost Float64,
    timestamp DateTime
) ENGINE = ReplacingMergeTree(timestamp)
ORDER BY event_id;

ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS site_id UInt64 DEFAULT 0 AFTER placement;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS placement_id UInt64 DEFAULT 0 AFTER site_id;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS format_id UInt64 DEFAULT 0 AFTER placement_id;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS placement_code String DEFAULT '' AFTER format_id;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS format_code LowCardinality(String) DEFAULT '' AFTER placement_code;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS audience_age UInt16 DEFAULT 0 AFTER format_code;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS audience_gender LowCardinality(String) DEFAULT '' AFTER audience_age;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS audience_interests String DEFAULT '' AFTER audience_gender;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS country LowCardinality(String) DEFAULT '' AFTER audience_interests;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS region LowCardinality(String) DEFAULT '' AFTER country;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS city LowCardinality(String) DEFAULT '' AFTER region;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS device_type LowCardinality(String) DEFAULT '' AFTER city;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS operating_system LowCardinality(String) DEFAULT '' AFTER device_type;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS conversions UInt8 DEFAULT 0 AFTER clicks;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS conversion_value Float64 DEFAULT 0 AFTER conversions;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS conversion_type LowCardinality(String) DEFAULT '' AFTER conversion_value;
ALTER TABLE delivery_stats ADD COLUMN IF NOT EXISTS conversion_currency LowCardinality(String) DEFAULT '' AFTER conversion_type;
