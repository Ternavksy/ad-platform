from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.db.base import Base
from app.api.auth import get_db
from app.models import user, balance, transaction, ad, creative, campaign


TEST_DATABASE_URL = "sqlite:///:memory:"

engine = create_engine(
    TEST_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)

TestingSessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db


def setup_module(module):
    Base.metadata.create_all(bind=engine)


def test_health():
    client = TestClient(app)
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_metrics():
    client = TestClient(app)
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert "auth_requests_total" in resp.text


def test_register_and_login_flow():
    client = TestClient(app)
    payload = {"email": "alice@example.com", "password": "secret123"}

    r = client.post("/auth/register", json=payload)
    assert r.status_code == 201
    data = r.json()
    assert data["email"] == payload["email"]
    assert "id" in data

    r2 = client.post("/auth/register", json=payload)
    assert r2.status_code == 400

    r3 = client.post("/auth/login", json=payload)
    assert r3.status_code == 200
    token_data = r3.json()
    assert "access_token" in token_data

    me = client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {token_data['access_token']}"},
    )
    assert me.status_code == 200
    assert me.json() == {
        "id": data["id"],
        "email": payload["email"],
        "role": "user",
    }

    invalid_me = client.get(
        "/auth/me",
        headers={"Authorization": "Bearer invalid-token"},
    )
    assert invalid_me.status_code == 401

    r4 = client.post(
        "/auth/login",
        json={"email": payload["email"], "password": "bad"},
    )
    assert r4.status_code == 401


def test_configured_admin_registration(monkeypatch):
    monkeypatch.setenv("ADMIN_EMAILS", "admin@example.com, second@example.com")
    client = TestClient(app)
    payload = {"email": "Admin@example.com", "password": "secret123"}

    registered = client.post("/auth/register", json=payload)
    assert registered.status_code == 201
    token = client.post("/auth/login", json=payload).json()["access_token"]
    current = client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert current.status_code == 200
    assert current.json()["role"] == "admin"


def test_billing_flow():
    client = TestClient(app)
    payload = {"email": "billing@example.com", "password": "secret123"}
    registered = client.post("/auth/register", json=payload)
    assert registered.status_code == 201
    user_id = registered.json()["id"]

    deposited = client.post(
        "/billing/deposit",
        json={"user_id": user_id, "amount": 100, "description": "initial"},
    )
    assert deposited.status_code == 200
    assert deposited.json()["balance"] == 100.0

    withdrawn = client.post(
        "/billing/withdraw",
        json={"user_id": user_id, "amount": 25, "description": "spend"},
    )
    assert withdrawn.status_code == 200
    assert withdrawn.json()["balance"] == 75.0

    insufficient = client.post(
        "/billing/withdraw",
        json={"user_id": user_id, "amount": 100, "description": "too much"},
    )
    assert insufficient.status_code == 422

    balance_response = client.get(f"/billing/balance/{user_id}")
    assert balance_response.status_code == 200
    assert balance_response.json()["balance"] == 75.0

    transactions = client.get(f"/billing/transactions/{user_id}")
    assert transactions.status_code == 200
    assert [item["description"] for item in transactions.json()] == ["initial", "spend"]
