import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Callable

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.access import user_permissions, user_roles
from app.core.security import (
    ACCESS_TOKEN_EXPIRE_MINUTES,
    REFRESH_TOKEN_EXPIRE_DAYS,
    create_access_token,
    create_refresh_token,
    decode_access_token,
    hash_signal,
    hash_token,
    utcnow,
)
from app.core.security_state import SecurityStateUnavailable, security_state_cache
from app.db.session import get_db
from app.models.admin import UserSession
from app.models.user import User


bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class Principal:
    user: User
    roles: list[str]
    permissions: list[str]
    session_id: str | None
    mfa: bool

    @property
    def user_id(self) -> int:
        return int(self.user.id)

    def has(self, permission: str) -> bool:
        return permission in self.permissions


def _aware(value: datetime | None) -> datetime | None:
    if value is None or value.tzinfo is not None:
        return value
    return value.replace(tzinfo=timezone.utc)


def user_is_available(user: User, now: datetime | None = None) -> bool:
    now = now or utcnow()
    if user.status in {"blocked", "deleted"}:
        return False
    if user.status == "suspended":
        until = _aware(user.suspended_until)
        if until is None or until > now:
            return False
        user.status = "active"
        user.suspended_until = None
    return True


def issue_token_pair(db: Session, user: User, request: Request, *, mfa: bool) -> dict:
    now = utcnow()
    session_id = str(uuid.uuid4())
    roles = user_roles(user)
    permissions = user_permissions(user)
    access_token = create_access_token(
        str(user.id),
        roles=roles,
        permissions=permissions,
        token_version=user.token_version,
        session_id=session_id,
        mfa=mfa,
    )
    access_payload = decode_access_token(access_token, "access")
    refresh_token = create_refresh_token()
    db.add(
        UserSession(
            id=session_id,
            user_id=user.id,
            refresh_token_hash=hash_token(refresh_token),
            access_jti=access_payload["jti"],
            user_agent_hash=hash_signal(request.headers.get("user-agent")),
            ip_hash=hash_signal(request.client.host if request.client else ""),
            created_at=now,
            last_used_at=now,
            expires_at=now + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
        )
    )
    security_state_cache.set_user(user)
    security_state_cache.set_session(
        session_id,
        active=True,
        ttl_seconds=REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60,
    )
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    }


def rotate_refresh_token(db: Session, value: str, request: Request) -> dict:
    now = utcnow()
    session = (
        db.query(UserSession)
        .filter(UserSession.refresh_token_hash == hash_token(value))
        .with_for_update()
        .first()
    )
    if (
        session is None
        or session.revoked_at is not None
        or (_aware(session.expires_at) or now) <= now
    ):
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    user = db.query(User).filter(User.id == session.user_id).with_for_update().first()
    if user is None or not user_is_available(user, now):
        session.revoked_at = now
        raise HTTPException(status_code=401, detail="Account is not active")
    security_state_cache.set_user(user)
    replacement = issue_token_pair(
        db,
        user,
        request,
        mfa=bool(user.mfa_confirmed_at) if set(user_roles(user)) & {"admin", "superadmin"} else False,
    )
    replacement_session = (
        db.query(UserSession)
        .filter(UserSession.refresh_token_hash == hash_token(replacement["refresh_token"]))
        .first()
    )
    session.revoked_at = now
    session.replaced_by = replacement_session.id if replacement_session else None
    session.last_used_at = now
    try:
        security_state_cache.set_session(session.id, active=False, strict=True)
    except SecurityStateUnavailable as exc:
        raise HTTPException(status_code=503, detail="Security state service is unavailable") from exc
    return replacement


def revoke_user_sessions(db: Session, user_id: int) -> int:
    now = utcnow()
    return (
        db.query(UserSession)
        .filter(UserSession.user_id == user_id, UserSession.revoked_at.is_(None))
        .update({UserSession.revoked_at: now}, synchronize_session=False)
    )


def get_current_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> Principal:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Authentication required")
    try:
        payload = decode_access_token(credentials.credentials, "access")
        user_id = int(payload["sub"])
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=401, detail="Invalid access token")
    user = db.query(User).filter(User.id == user_id).first()
    if user is None or not user_is_available(user):
        raise HTTPException(status_code=401, detail="Account is not active")
    if int(payload.get("token_version", 0)) != user.token_version:
        raise HTTPException(status_code=401, detail="Session has been revoked")
    session_id = payload.get("sid")
    if session_id:
        session = db.query(UserSession).filter(UserSession.id == session_id).first()
        if (
            session is None
            or session.user_id != user.id
            or session.revoked_at is not None
            or (_aware(session.expires_at) or utcnow()) <= utcnow()
        ):
            raise HTTPException(status_code=401, detail="Session has been revoked")
    roles = user_roles(user)
    permissions = user_permissions(user)
    security_state_cache.set_user(user)
    return Principal(
        user=user,
        roles=roles,
        permissions=permissions,
        session_id=session_id,
        mfa=bool(payload.get("mfa")),
    )


def require_permission(permission: str, *, require_mfa: bool = False) -> Callable:
    def dependency(principal: Principal = Depends(get_current_principal)) -> Principal:
        if permission not in principal.permissions:
            raise HTTPException(status_code=403, detail="Permission denied")
        if require_mfa and not principal.mfa:
            raise HTTPException(status_code=403, detail="MFA confirmation required")
        return principal

    return dependency
