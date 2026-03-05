#!/bin/bash

# Wait for Clickhouse to be ready
until curl -s http://localhost:8123/ping; do
  echo "Waiting for Clickhouse..."
  sleep 2
done

# Create database and tables
curl -s -X POST 'http://localhost:8123/' -d "
CREATE DATABASE IF NOT EXISTS analytics;

CREATE TABLE IF NOT EXISTS analytics.ads_stats (
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

CREATE TABLE IF NOT EXISTS analytics.campaign_stats (
    date Date,
    campaign_id UInt64,
    impressions UInt64,
    clicks UInt64,
    cost Float64,
    timestamp DateTime
) ENGINE = MergeTree()
ORDER BY (date, campaign_id, timestamp);

CREATE TABLE IF NOT EXISTS analytics.creative_stats (
    date Date,
    creative_id UInt64,
    impressions UInt64,
    clicks UInt64,
    cost Float64,
    timestamp DateTime
) ENGINE = MergeTree()
ORDER BY (date, creative_id, timestamp);
"

echo "Clickhouse database and tables created successfully"