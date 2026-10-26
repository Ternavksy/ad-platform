import time
from contextlib import contextmanager
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.auth import get_db
from app.cli import create_admin
from app.core.access import ROLE_PERMISSIONS, assign_roles, user_permissions, user_roles
from app.core.security import _totp, create_totp_secret, encrypt_secret, hash_password, utcnow
from app.core.security_state import security_state_cache
from app.db.base import Base
from app.main import app
from app.models import ad, admin, balance, campaign, creative, delivery, transaction, user
from app.models.admin import AdminAuditLog, PasswordResetToken
from app.models.balance import Balance
from app.models.campaign import Campaign
from app.models.user import User


@pytest.fixture()
def isolated_app(monkeypatch):
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    testing_session = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    Base.metadata.create_all(engine)

    def override_get_db():
        db = testing_session()
        try:
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    @contextmanager
    def override_transaction():
        db = testing_session()
        try:
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    previous_override = app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db] = override_get_db
    monkeypatch.setattr("app.cli.transaction", override_transaction)
    monkeypatch.setattr(security_state_cache, "redis", None)
    monkeypatch.setattr(
        "app.api.admin.rabbitmq_service.publish_user_blocked", lambda *_: None
    )
    reset_events = []
    monkeypatch.setattr(
        "app.api.admin.rabbitmq_service.publish_password_reset_requested",
        lambda *args: reset_events.append(args),
    )
    yield TestClient(app), testing_session, reset_events
    if previous_override is None:
        app.dependency_overrides.pop(get_db, None)
    else:
        app.dependency_overrides[get_db] = previous_override
    Base.metadata.drop_all(engine)
    engine.dispose()


def _create_privileged_user(session_factory, email: str, role: str):
    db = session_factory()
    secret = create_totp_secret()
    account = User(
        email=email,
        password_hash=hash_password("strong-admin-password"),
        role=role,
        mfa_secret_encrypted=encrypt_secret(secret),
        mfa_confirmed_at=utcnow(),
    )
    db.add(account)
    db.flush()
    assign_roles(db, account, [role])
    db.add(Balance(user_id=account.id, amount=0))
    db.commit()
    account_id = account.id
    db.close()
    return account_id, secret


def _login_admin(client: TestClient, email: str, secret: str):
    login = client.post(
        "/auth/login",
        json={"email": email, "password": "strong-admin-password"},
    )
    assert login.status_code == 200
    code = _totp(secret, int(time.time()) // 30)
    confirmed = client.post(
        "/auth/mfa/confirm",
        json={"challenge_token": login.json()["mfa_challenge"], "code": code},
    )
    assert confirmed.status_code == 200
    return {"Authorization": f"Bearer {confirmed.json()['access_token']}"}, code


def test_permission_matrix_contains_only_expected_grants(isolated_app):
    _, session_factory, _ = isolated_app
    db = session_factory()
    try:
        for role, expected in ROLE_PERMISSIONS.items():
            account = User(
                email=f"{role}@example.com",
                password_hash=hash_password("secret123"),
                role=role,
            )
            db.add(account)
            db.flush()
            assign_roles(db, account, [role])
            assert set(user_permissions(account)) == expected
    finally:
        db.close()


def test_bootstrap_creates_one_superadmin_without_password_argument(
    isolated_app, monkeypatch
):
    client, session_factory, _ = isolated_app
    answers = iter(["very-strong-password", "very-strong-password"] * 2)
    monkeypatch.setattr("app.cli.getpass.getpass", lambda _: next(answers))

    assert create_admin("bootstrap@example.com") == 0
    assert create_admin("bootstrap@example.com") == 1

    db = session_factory()
    account = db.query(User).filter(User.email == "bootstrap@example.com").one()
    assert user_roles(account) == ["superadmin"]
    assert db.query(AdminAuditLog).filter_by(action="superadmin.bootstrapped").count() == 1
    db.close()

    login = client.post(
        "/auth/login",
        json={"email": "bootstrap@example.com", "password": "very-strong-password"},
    )
    assert login.status_code == 200
    code = _totp(login.json()["mfa_secret"], int(time.time()) // 30)
    confirmed = client.post(
        "/auth/mfa/confirm",
        json={"challenge_token": login.json()["mfa_challenge"], "code": code},
    )
    assert confirmed.status_code == 200
    immediate_me = client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {confirmed.json()['access_token']}"},
    )
    assert immediate_me.status_code == 200
    assert immediate_me.json()["roles"] == ["superadmin"]


def test_admin_safety_concurrency_suspension_and_campaign_pause(isolated_app):
    client, session_factory, _ = isolated_app
    admin_id, secret = _create_privileged_user(
        session_factory, "admin@example.com", "superadmin"
    )
    headers, code = _login_admin(client, "admin@example.com", secret)
    target_payload = {"email": "target@example.com", "password": "secret123"}
    target = client.post("/auth/register", json=target_payload).json()
    target_tokens = client.post("/auth/login", json=target_payload).json()

    db = session_factory()
    db.add(Campaign(user_id=target["id"], name="live", status="active"))
    db.commit()
    db.close()

    self_user = client.get(f"/admin/users/{admin_id}", headers=headers).json()
    self_block = client.post(
        f"/admin/users/{admin_id}/block",
        headers=headers,
        json={
            "reason": "must be rejected",
            "row_version": self_user["row_version"],
            "mfa_code": code,
        },
    )
    assert self_block.status_code == 409

    managed = client.get(f"/admin/users/{target['id']}", headers=headers).json()
    conflict = client.post(
        f"/admin/users/{target['id']}/block",
        headers=headers,
        json={"reason": "stale", "row_version": 99, "mfa_code": code},
    )
    assert conflict.status_code == 409

    suspended = client.post(
        f"/admin/users/{target['id']}/suspend",
        headers=headers,
        json={
            "reason": "temporary investigation",
            "row_version": managed["row_version"],
            "mfa_code": code,
            "suspended_until": (utcnow() + timedelta(hours=1)).isoformat(),
        },
    )
    assert suspended.status_code == 200
    assert suspended.json()["status"] == "suspended"
    assert client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {target_tokens['access_token']}"},
    ).status_code == 401

    unblocked = client.post(
        f"/admin/users/{target['id']}/unblock",
        headers=headers,
        json={
            "reason": "investigation complete",
            "row_version": suspended.json()["row_version"],
            "mfa_code": code,
        },
    )
    assert unblocked.status_code == 200
    db = session_factory()
    assert db.query(Campaign).filter_by(user_id=target["id"]).one().status == "paused"
    assert (
        db.query(AdminAuditLog)
        .filter(AdminAuditLog.target_id == str(target["id"]))
        .count()
        == 2
    )
    db.close()


def test_last_superadmin_and_password_reset_one_time_flow(isolated_app):
    client, session_factory, reset_events = isolated_app
    super_id, _ = _create_privileged_user(
        session_factory, "only-super@example.com", "superadmin"
    )
    _, admin_secret = _create_privileged_user(
        session_factory, "operator@example.com", "admin"
    )
    headers, code = _login_admin(client, "operator@example.com", admin_secret)
    target_payload = {"email": "reset-me@example.com", "password": "old-secret"}
    target = client.post("/auth/register", json=target_payload).json()
    old_token = client.post("/auth/login", json=target_payload).json()["access_token"]

    super_user = client.get(f"/admin/users/{super_id}", headers=headers).json()
    demote = client.put(
        f"/admin/users/{super_id}/roles",
        headers=headers,
        json={
            "roles": ["admin"],
            "reason": "invalid demotion",
            "row_version": super_user["row_version"],
            "mfa_code": code,
        },
    )
    assert demote.status_code == 409

    managed = client.get(f"/admin/users/{target['id']}", headers=headers).json()
    reset = client.post(
        f"/admin/users/{target['id']}/password-reset",
        headers=headers,
        json={
            "reason": "user verified by support",
            "row_version": managed["row_version"],
            "mfa_code": code,
        },
    )
    assert reset.status_code == 202
    assert reset_events and reset_events[0][0] == target["id"]
    reset_token = reset_events[0][2]
    assert reset_token not in reset.text
    assert client.get(
        "/auth/me", headers={"Authorization": f"Bearer {old_token}"}
    ).status_code == 401

    completed = client.post(
        "/auth/password-reset/complete",
        json={"token": reset_token, "password": "new-secret-123"},
    )
    assert completed.status_code == 204
    assert client.post(
        "/auth/password-reset/complete",
        json={"token": reset_token, "password": "another-secret"},
    ).status_code == 400
    assert client.post(
        "/auth/login",
        json={"email": target_payload["email"], "password": "new-secret-123"},
    ).status_code == 200
    db = session_factory()
    assert db.query(PasswordResetToken).filter_by(user_id=target["id"]).one().used_at
    db.close()


def test_financial_idor_is_rejected(isolated_app):
    client, _, _ = isolated_app
    first = {"email": "first@example.com", "password": "secret123"}
    second = {"email": "second@example.com", "password": "secret123"}
    client.post("/auth/register", json=first)
    second_id = client.post("/auth/register", json=second).json()["id"]
    token = client.post("/auth/login", json=first).json()["access_token"]
    forbidden = client.get(
        f"/billing/balance/{second_id}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert forbidden.status_code == 403
