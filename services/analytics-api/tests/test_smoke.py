import asyncio
from unittest.mock import AsyncMock

from fastapi.testclient import TestClient

from app.main import app, connect_rabbitmq
from app.core.rabbitmq import rabbitmq_consumer
from app.core.rabbitmq import create_message_handler
from app.api.analytics import clickhouse_client
from app.core.security import AnalyticsPrincipal, get_current_principal


app.dependency_overrides[get_current_principal] = lambda: AnalyticsPrincipal(
	user_id=1,
	permissions=["fraud.review"],
	token="test-token",
)


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
	monkeypatch.setattr("app.api.analytics.assert_resource_access", lambda *_: None)
	monkeypatch.setattr(
		clickhouse_client,
		"get_ad_stats",
		lambda **_: [("2026-10-24", 7, 11, 13, 100, 8, 3, 1499.9, 2, 1, 4, 12.5)],
	)
	monkeypatch.setattr(
		clickhouse_client,
		"get_campaign_stats",
		lambda **_: [("2026-10-24", 7, 100, 8, 3, 1499.9, 2, 1, 4, 12.5)],
	)
	monkeypatch.setattr(
		clickhouse_client,
		"get_creative_stats",
		lambda **_: [("2026-10-24", 13, 100, 8, 3, 1499.9, 2, 1, 4, 12.5)],
	)

	client = TestClient(app)
	ad = client.get("/ads?ad_id=11")
	campaign = client.get("/campaigns?campaign_id=7")
	creative = client.get("/creatives?creative_id=13")

	assert ad.status_code == 200
	assert ad.json()[0]["campaign_id"] == 7
	assert ad.json()[0]["total_conversions"] == 3
	assert ad.json()[0]["total_conversion_value"] == 1499.9
	assert ad.json()[0]["last_click_conversions"] == 2
	assert ad.json()[0]["view_through_conversions"] == 1
	assert ad.json()[0]["total_fraud_events"] == 4
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
	assert inserted[0][20:23] == (1, 0, 0)
	assert inserted[0][30] == 0.0125

	handle(
		{
			"type": "ad_conversion",
			"event_id": "event-2",
			"delivery_id": "delivery-1",
			"campaign_id": 7,
			"ad_id": 11,
			"creative_id": 13,
			"placement": "feed",
			"conversion_id": "order-42",
			"conversion_type": "purchase",
			"conversion_value": 1499.9,
			"conversion_currency": "RUB",
			"attribution_model": "last_click",
			"attribution_window_hours": 168,
			"occurred_at": "2026-10-24T10:05:00Z",
		}
	)
	assert inserted[1][20:23] == (0, 0, 1)
	assert inserted[1][23:26] == (1499.9, "purchase", "RUB")
	assert inserted[1][26:30] == ("last_click", 168, 0, "")

