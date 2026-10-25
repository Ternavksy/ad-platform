import asyncio
from unittest.mock import AsyncMock

from fastapi.testclient import TestClient

from app.main import app, connect_rabbitmq
from app.core.rabbitmq import rabbitmq_consumer
from app.core.rabbitmq import create_message_handler
from app.api.analytics import clickhouse_client


def test_health():
	client = TestClient(app)
	resp = client.get("/health")
	assert resp.status_code == 200
	assert resp.json()["status"] == "ok"


def test_metrics_endpoint():
	client = TestClient(app)
	r = client.get("/metrics")
	assert r.status_code == 200
	assert "analytics_http_requests_total" in r.text


def test_rabbitmq_startup_retries(monkeypatch):
	connect = AsyncMock(side_effect=[False, True])
	sleep = AsyncMock()
	monkeypatch.setattr(rabbitmq_consumer, "connect", connect)
	monkeypatch.setattr("app.main.asyncio.sleep", sleep)

	asyncio.run(connect_rabbitmq(retries=2, delay_seconds=0))

	assert connect.await_count == 2
	sleep.assert_awaited_once_with(0)


def test_analytics_endpoints_serialize_all_entity_types(monkeypatch):
	monkeypatch.setattr(
		clickhouse_client,
		"get_ad_stats",
		lambda **_: [("2026-10-24", 7, 11, 13, 100, 8, 12.5)],
	)
	monkeypatch.setattr(
		clickhouse_client,
		"get_campaign_stats",
		lambda **_: [("2026-10-24", 7, 100, 8, 12.5)],
	)
	monkeypatch.setattr(
		clickhouse_client,
		"get_creative_stats",
		lambda **_: [("2026-10-24", 13, 100, 8, 12.5)],
	)

	client = TestClient(app)
	ad = client.get("/ads?ad_id=11")
	campaign = client.get("/campaigns?campaign_id=7")
	creative = client.get("/creatives?creative_id=13")

	assert ad.status_code == 200
	assert ad.json()[0]["campaign_id"] == 7
	assert campaign.status_code == 200
	assert campaign.json()[0]["campaign_id"] == 7
	assert creative.status_code == 200
	assert creative.json()[0]["campaign_id"] is None
	assert creative.json()[0]["creative_id"] == 13


def test_delivery_events_are_the_only_events_that_change_metrics(monkeypatch):
	inserted = []
	monkeypatch.setattr(
		clickhouse_client,
		"insert_delivery_stats",
		lambda rows: inserted.extend(rows),
	)
	handle = create_message_handler()

	handle({"type": "ad_created", "ad_id": "11", "campaign_id": 7})
	assert inserted == []

	handle(
		{
			"type": "ad_impression",
			"event_id": "event-1",
			"delivery_id": "delivery-1",
			"campaign_id": 7,
			"ad_id": 11,
			"creative_id": 13,
			"placement": "feed",
				"bid_cpm": 12.5,
				"cost": 0.0125,
			"occurred_at": "2026-10-24T10:00:00Z",
		}
	)
	assert inserted[0][0:2] == ("event-1", "delivery-1")
	assert inserted[0][20:22] == (1, 0)
	assert inserted[0][22] == 0.0125

