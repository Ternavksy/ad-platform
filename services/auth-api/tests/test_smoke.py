from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.db.base import Base
from app.api.auth import get_db
from app.models import admin, user, balance, transaction, ad, creative, campaign


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
    assert me.json()["id"] == data["id"]
    assert me.json()["email"] == payload["email"]
    assert me.json()["role"] == "user"
    assert me.json()["roles"] == ["user"]
    assert me.json()["permissions"] == []

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


def test_public_registration_never_creates_admin(monkeypatch):
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
    assert current.json()["role"] == "user"
    assert current.json()["roles"] == ["user"]


def test_billing_flow():
    client = TestClient(app)
    payload = {"email": "billing@example.com", "password": "secret123"}
    registered = client.post("/auth/register", json=payload)
    assert registered.status_code == 201
    user_id = registered.json()["id"]
    token = client.post("/auth/login", json=payload).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    deposited = client.post(
        "/billing/deposit",
        json={"user_id": user_id, "amount": 100, "description": "initial"},
        headers=headers,
    )
    assert deposited.status_code == 200
    assert deposited.json()["balance"] == 100.0

    withdrawn = client.post(
        "/billing/withdraw",
        json={"user_id": user_id, "amount": 25, "description": "spend"},
        headers=headers,
    )
    assert withdrawn.status_code == 200
    assert withdrawn.json()["balance"] == 75.0

    insufficient = client.post(
        "/billing/withdraw",
        json={"user_id": user_id, "amount": 100, "description": "too much"},
        headers=headers,
    )
    assert insufficient.status_code == 422

    balance_response = client.get(f"/billing/balance/{user_id}", headers=headers)
    assert balance_response.status_code == 200
    assert balance_response.json()["balance"] == 75.0

    transactions = client.get(f"/billing/transactions/{user_id}", headers=headers)
    assert transactions.status_code == 200
    assert [item["description"] for item in transactions.json()] == ["initial", "spend"]


def test_admin_mfa_user_management_and_immediate_revocation(monkeypatch):
    import time

    from app.core.access import assign_roles
    from app.core.security import _totp, create_totp_secret, encrypt_secret, hash_password, utcnow
    from app.models.balance import Balance
    from app.models.user import User

    db = TestingSessionLocal()
    secret = create_totp_secret()
    administrator = User(
        email="root-admin@example.com",
        password_hash=hash_password("strong-admin-password"),
        role="superadmin",
        mfa_secret_encrypted=encrypt_secret(secret),
        mfa_confirmed_at=utcnow(),
    )
    db.add(administrator)
    db.flush()
    assign_roles(db, administrator, ["superadmin"])
    db.add(Balance(user_id=administrator.id, amount=0))
    db.commit()
    db.close()

    client = TestClient(app)
    target_payload = {"email": "managed-user@example.com", "password": "secret123"}
    target = client.post("/auth/register", json=target_payload).json()
    target_login = client.post("/auth/login", json=target_payload).json()

    login = client.post(
        "/auth/login",
        json={"email": "root-admin@example.com", "password": "strong-admin-password"},
    )
    assert login.status_code == 200
    assert login.json()["mfa_required"] is True
    code = _totp(secret, int(time.time()) // 30)
    confirmed = client.post(
        "/auth/mfa/confirm",
        json={"challenge_token": login.json()["mfa_challenge"], "code": code},
    )
    assert confirmed.status_code == 200
    admin_headers = {"Authorization": f"Bearer {confirmed.json()['access_token']}"}

    users = client.get("/admin/users?query=managed-user", headers=admin_headers)
    assert users.status_code == 200
    managed = users.json()["items"][0]
    assert managed["id"] == target["id"]

    ordinary_admin_request = client.get(
        "/admin/users",
        headers={"Authorization": f"Bearer {target_login['access_token']}"},
    )
    assert ordinary_admin_request.status_code == 403

    monkeypatch.setattr(
        "app.api.admin.rabbitmq_service.publish_user_blocked",
        lambda *_: None,
    )
    block = client.post(
        f"/admin/users/{target['id']}/block",
        headers=admin_headers,
        json={
            "reason": "confirmed abuse",
            "row_version": managed["row_version"],
            "mfa_code": code,
        },
    )
    assert block.status_code == 200
    assert block.json()["status"] == "blocked"

    revoked = client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {target_login['access_token']}"},
    )
    assert revoked.status_code == 401
    audit = client.get(f"/admin/users/{target['id']}/audit", headers=admin_headers)
    assert audit.status_code == 200
    assert audit.json()[0]["action"] == "user.blocked"
    assert "password_hash" not in str(audit.json())
