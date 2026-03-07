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

    r4 = client.post(
        "/auth/login",
        json={"email": payload["email"], "password": "bad"},
    )
    assert r4.status_code == 401
