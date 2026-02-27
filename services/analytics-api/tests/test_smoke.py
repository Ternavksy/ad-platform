from fastapi.testclient import TestClient

from app.main import app


def test_health():
	client = TestClient(app)
	resp = client.get("/health")
	assert resp.status_code == 200
	assert resp.json() == {"status": "ok"}


def test_metrics_endpoint_absent_or_healthy():
	client = TestClient(app)
	r = client.get("/metrics")
	assert r.status_code in (200, 404)

