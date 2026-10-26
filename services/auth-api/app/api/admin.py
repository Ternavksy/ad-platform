import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.api.auth import serialize_user
from app.core.access import ADMIN_ROLES, ROLE_PERMISSIONS, assign_roles, user_roles
from app.core.authentication import (
    Principal,
    require_permission,
    revoke_user_sessions,
)
from app.core.rabbitmq import rabbitmq_service
from app.core.security import decrypt_secret, hash_signal, hash_token, utcnow, verify_totp
from app.core.security_state import SecurityStateUnavailable, security_state_cache
from app.db.session import get_db
from app.models.admin import (
    AdminAuditLog,
    AdminInvitation,
    PasswordResetToken,
    UserSession,
)
from app.models.balance import Balance
from app.models.campaign import Campaign
from app.models.creative import Creative
from app.models.delivery import DeliveryOutbox
from app.models.transaction import Transaction
from app.models.user import User


router = APIRouter(prefix="/admin", tags=["admin"])


class UserCommand(BaseModel):
    reason: str = Field(min_length=3, max_length=500)
    row_version: int = Field(ge=1)
    mfa_code: str = Field(min_length=6, max_length=32)
    suspended_until: datetime | None = None


class RoleCommand(BaseModel):
    roles: list[str] = Field(min_length=1)
    row_version: int = Field(ge=1)
    reason: str = Field(min_length=3, max_length=500)
    mfa_code: str = Field(min_length=6, max_length=32)


class SecurityCommand(BaseModel):
    reason: str = Field(min_length=3, max_length=500)
    row_version: int = Field(ge=1)
    mfa_code: str = Field(min_length=6, max_length=32)


class InvitationRequest(BaseModel):
    email: EmailStr
    role: str
    expires_in_hours: int = Field(default=72, ge=1, le=168)
    mfa_code: str = Field(min_length=6, max_length=32)


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value else None


def _is_future(value: datetime | None) -> bool:
    if value is None:
        return False
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value > utcnow()


def _user_state(user: User) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "status": user.status,
        "roles": user_roles(user),
        "blocked_at": _iso(user.blocked_at),
        "blocked_by": user.blocked_by,
        "block_reason": user.block_reason,
        "suspended_until": _iso(user.suspended_until),
        "token_version": user.token_version,
        "password_reset_required": user.password_reset_required,
        "row_version": user.row_version,
    }


def _admin_user(user: User, db: Session) -> dict:
    payload = serialize_user(user)
    balance = db.query(Balance).filter(Balance.user_id == user.id).first()
    payload.update(
        {
            "created_at": _iso(user.created_at),
            "updated_at": _iso(user.updated_at),
            "last_login_at": _iso(user.last_login_at),
            "email_verified_at": _iso(user.email_verified_at),
            "blocked_at": _iso(user.blocked_at),
            "blocked_by": user.blocked_by,
            "block_reason": user.block_reason,
            "suspended_until": _iso(user.suspended_until),
            "row_version": user.row_version,
            "balance": float(balance.amount) if balance else 0,
            "active_sessions": db.query(UserSession).filter(
                UserSession.user_id == user.id,
                UserSession.revoked_at.is_(None),
                UserSession.expires_at > utcnow(),
            ).count(),
            "campaigns": db.query(Campaign).filter(Campaign.user_id == user.id).count(),
            "transactions": db.query(Transaction).filter(Transaction.user_id == user.id).count(),
            "fraud_events": db.query(DeliveryOutbox)
            .join(Campaign, Campaign.id == DeliveryOutbox.campaign_id)
            .filter(Campaign.user_id == user.id, DeliveryOutbox.is_fraud.is_(True))
            .count(),
            "recent_audit": [
                _audit_payload(item)
                for item in db.query(AdminAuditLog)
                .filter(
                    AdminAuditLog.target_type == "user",
                    AdminAuditLog.target_id == str(user.id),
                )
                .order_by(AdminAuditLog.id.desc())
                .limit(10)
                .all()
            ],
        }
    )
    return payload


def _request_id(request: Request) -> str:
    return request.headers.get("x-request-id") or str(uuid.uuid4())


def _audit(
    db: Session,
    request: Request,
    actor: Principal,
    action: str,
    target_type: str,
    target_id: str | int,
    *,
    before: dict | None = None,
    after: dict | None = None,
    reason: str = "",
) -> None:
    db.add(
        AdminAuditLog(
            actor_user_id=actor.user_id,
            actor_roles=actor.roles,
            action=action,
            target_type=target_type,
            target_id=str(target_id),
            before_state=before,
            after_state=after,
            reason=reason,
            request_id=_request_id(request),
            ip_hash=hash_signal(request.client.host if request.client else ""),
            user_agent_hash=hash_signal(request.headers.get("user-agent")),
            created_at=utcnow(),
        )
    )


def _verify_mfa(principal: Principal, code: str) -> None:
    if not principal.mfa or principal.user.mfa_confirmed_at is None:
        raise HTTPException(status_code=403, detail="MFA confirmation required")
    if not principal.user.mfa_secret_encrypted:
        raise HTTPException(status_code=403, detail="MFA is not configured")
    if not verify_totp(decrypt_secret(principal.user.mfa_secret_encrypted), code):
        raise HTTPException(status_code=403, detail="Invalid MFA confirmation code")


def _sync_security_state(user: User) -> None:
    try:
        security_state_cache.set_user(user, strict=True)
    except SecurityStateUnavailable:
        raise HTTPException(status_code=503, detail="Security state service is unavailable")


def _locked_user(db: Session, user_id: int, row_version: int) -> User:
    user = db.query(User).filter(User.id == user_id).with_for_update().first()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    if user.row_version != row_version:
        raise HTTPException(status_code=409, detail="User was changed by another administrator")
    return user


@router.get("/dashboard")
def dashboard(
    principal: Principal = Depends(require_permission("users.read")),
    db: Session = Depends(get_db),
):
    now = utcnow()
    return {
        "total_users": db.query(User).count(),
        "active_users": db.query(User).filter(User.status == "active").count(),
        "blocked_users": db.query(User).filter(User.status == "blocked").count(),
        "new_users": db.query(User).filter(User.created_at >= now - timedelta(days=7)).count(),
        "pending_moderation": db.query(Creative)
        .filter(Creative.moderation_status == "pending")
        .count(),
        "fraud_events": db.query(DeliveryOutbox)
        .filter(DeliveryOutbox.is_fraud.is_(True))
        .count(),
        "recent_audit": [
            _audit_payload(item)
            for item in db.query(AdminAuditLog).order_by(AdminAuditLog.id.desc()).limit(5).all()
        ],
    }


@router.get("/users")
def list_users(
    query: str | None = None,
    status: str | None = None,
    role: str | None = None,
    cursor: int | None = None,
    limit: int = Query(default=25, ge=1, le=100),
    sort: str = Query(default="created_at", pattern="^(created_at|last_login_at)$"),
    direction: str = Query(default="desc", pattern="^(asc|desc)$"),
    principal: Principal = Depends(require_permission("users.read")),
    db: Session = Depends(get_db),
):
    request = db.query(User)
    if query:
        expression = f"%{query.strip().lower()}%"
        filters = [func.lower(User.email).like(expression)]
        if query.strip().isdigit():
            filters.append(User.id == int(query.strip()))
        request = request.filter(or_(*filters))
    if status:
        request = request.filter(User.status == status)
    if role:
        request = request.filter(User.roles.any(name=role))
    if cursor:
        request = request.filter(User.id < cursor if direction == "desc" else User.id > cursor)
    column = User.last_login_at if sort == "last_login_at" else User.created_at
    ordering = column.desc() if direction == "desc" else column.asc()
    items = request.order_by(ordering, User.id.desc() if direction == "desc" else User.id.asc()).limit(limit + 1).all()
    has_more = len(items) > limit
    items = items[:limit]
    return {
        "items": [_admin_user(item, db) for item in items],
        "next_cursor": items[-1].id if has_more and items else None,
    }


@router.get("/users/{user_id}")
def get_user(
    user_id: int,
    principal: Principal = Depends(require_permission("users.read")),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    return _admin_user(user, db)


def _set_user_status(
    user_id: int,
    command: UserCommand,
    request: Request,
    principal: Principal,
    db: Session,
    status: str,
) -> dict:
    _verify_mfa(principal, command.mfa_code)
    if user_id == principal.user_id:
        raise HTTPException(status_code=409, detail="You cannot change your own account status")
    user = _locked_user(db, user_id, command.row_version)
    before = _user_state(user)
    now = utcnow()
    if status == "suspended":
        if command.suspended_until is None:
            raise HTTPException(status_code=422, detail="suspended_until is required")
        until = command.suspended_until
        if until.tzinfo is None:
            until = until.replace(tzinfo=timezone.utc)
        if until <= now:
            raise HTTPException(status_code=422, detail="Suspension must end in the future")
        user.suspended_until = until
    else:
        user.suspended_until = None
    user.status = status
    user.block_reason = command.reason if status in {"blocked", "suspended"} else ""
    user.blocked_at = now if status == "blocked" else None
    user.blocked_by = principal.user_id if status in {"blocked", "suspended"} else None
    if status in {"blocked", "suspended"}:
        revoke_user_sessions(db, user.id)
        user.token_version += 1
        db.query(Campaign).filter(
            Campaign.user_id == user.id,
            Campaign.status == "active",
        ).update({Campaign.status: "paused"}, synchronize_session=False)
    user.row_version += 1
    user.updated_at = now
    _sync_security_state(user)
    after = _user_state(user)
    _audit(
        db, request, principal, f"user.{status}", "user", user.id,
        before=before, after=after, reason=command.reason,
    )
    db.commit()
    if status == "blocked":
        rabbitmq_service.publish_user_blocked(
            user.id,
            principal.user_id,
            command.reason,
            user.token_version,
        )
    return _admin_user(user, db)


@router.post("/users/{user_id}/block")
def block_user(
    user_id: int,
    command: UserCommand,
    request: Request,
    principal: Principal = Depends(require_permission("users.block", require_mfa=True)),
    db: Session = Depends(get_db),
):
    return _set_user_status(user_id, command, request, principal, db, "blocked")


@router.post("/users/{user_id}/suspend")
def suspend_user(
    user_id: int,
    command: UserCommand,
    request: Request,
    principal: Principal = Depends(require_permission("users.block", require_mfa=True)),
    db: Session = Depends(get_db),
):
    return _set_user_status(user_id, command, request, principal, db, "suspended")


@router.post("/users/{user_id}/unblock")
def unblock_user(
    user_id: int,
    command: UserCommand,
    request: Request,
    principal: Principal = Depends(require_permission("users.block", require_mfa=True)),
    db: Session = Depends(get_db),
):
    return _set_user_status(user_id, command, request, principal, db, "active")


@router.put("/users/{user_id}/roles")
def update_roles(
    user_id: int,
    command: RoleCommand,
    request: Request,
    principal: Principal = Depends(require_permission("users.roles.manage", require_mfa=True)),
    db: Session = Depends(get_db),
):
    _verify_mfa(principal, command.mfa_code)
    user = _locked_user(db, user_id, command.row_version)
    normalized = sorted(set(command.roles))
    if any(role not in ROLE_PERMISSIONS for role in normalized):
        raise HTTPException(status_code=422, detail="Unknown role")
    if "superadmin" in normalized and "superadmin" not in principal.roles:
        raise HTTPException(status_code=403, detail="Only superadmin can grant superadmin")
    before_roles = user_roles(user)
    if user_id == principal.user_id and normalized != before_roles:
        raise HTTPException(status_code=409, detail="You cannot change your own roles")
    if "superadmin" in before_roles and "superadmin" not in normalized:
        count = db.query(User).filter(User.roles.any(name="superadmin"), User.status != "deleted").count()
        if count <= 1:
            raise HTTPException(status_code=409, detail="The last superadmin cannot be demoted")
    before = _user_state(user)
    assign_roles(db, user, normalized)
    revoke_user_sessions(db, user.id)
    user.token_version += 1
    user.row_version += 1
    user.updated_at = utcnow()
    _sync_security_state(user)
    after = _user_state(user)
    _audit(
        db, request, principal, "user.roles.updated", "user", user.id,
        before=before, after=after, reason=command.reason,
    )
    db.commit()
    return _admin_user(user, db)


@router.post("/users/{user_id}/revoke-sessions")
def revoke_sessions(
    user_id: int,
    command: SecurityCommand,
    request: Request,
    principal: Principal = Depends(require_permission("users.sessions.revoke", require_mfa=True)),
    db: Session = Depends(get_db),
):
    _verify_mfa(principal, command.mfa_code)
    user = _locked_user(db, user_id, command.row_version)
    before = _user_state(user)
    revoked = revoke_user_sessions(db, user.id)
    user.token_version += 1
    user.row_version += 1
    _sync_security_state(user)
    _audit(
        db, request, principal, "user.sessions.revoked", "user", user.id,
        before=before, after=_user_state(user), reason=command.reason,
    )
    db.commit()
    return {"revoked_sessions": revoked, "user": _admin_user(user, db)}


@router.post("/users/{user_id}/password-reset", status_code=202)
def request_password_reset(
    user_id: int,
    command: SecurityCommand,
    request: Request,
    principal: Principal = Depends(require_permission("users.sessions.revoke", require_mfa=True)),
    db: Session = Depends(get_db),
):
    _verify_mfa(principal, command.mfa_code)
    user = _locked_user(db, user_id, command.row_version)
    before = _user_state(user)
    user.password_reset_required = True
    user.token_version += 1
    user.row_version += 1
    revoke_user_sessions(db, user.id)
    db.query(PasswordResetToken).filter(
        PasswordResetToken.user_id == user.id,
        PasswordResetToken.used_at.is_(None),
    ).update({PasswordResetToken.used_at: utcnow()}, synchronize_session=False)
    token = secrets.token_urlsafe(48)
    reset = PasswordResetToken(
        id=str(uuid.uuid4()),
        user_id=user.id,
        token_hash=hash_token(token),
        created_at=utcnow(),
        expires_at=utcnow() + timedelta(minutes=30),
    )
    db.add(reset)
    _sync_security_state(user)
    _audit(
        db, request, principal, "user.password_reset.requested", "user", user.id,
        before=before, after=_user_state(user), reason=command.reason,
    )
    db.commit()
    rabbitmq_service.publish_password_reset_requested(
        user.id,
        user.email,
        token,
        _iso(reset.expires_at),
    )
    return {"accepted": True, "user": _admin_user(user, db)}


@router.get("/users/{user_id}/sessions")
def list_sessions(
    user_id: int,
    principal: Principal = Depends(require_permission("users.sessions.revoke")),
    db: Session = Depends(get_db),
):
    return [
        {
            "id": item.id,
            "created_at": _iso(item.created_at),
            "last_used_at": _iso(item.last_used_at),
            "expires_at": _iso(item.expires_at),
            "revoked_at": _iso(item.revoked_at),
            "active": item.revoked_at is None and _is_future(item.expires_at),
        }
        for item in db.query(UserSession)
        .filter(UserSession.user_id == user_id)
        .order_by(UserSession.created_at.desc())
        .all()
    ]


def _audit_payload(item: AdminAuditLog) -> dict:
    return {
        "id": item.id,
        "actor_user_id": item.actor_user_id,
        "actor_roles": item.actor_roles,
        "action": item.action,
        "target_type": item.target_type,
        "target_id": item.target_id,
        "before": item.before_state,
        "after": item.after_state,
        "reason": item.reason,
        "request_id": item.request_id,
        "created_at": _iso(item.created_at),
    }


@router.get("/audit")
def list_audit(
    target_id: str | None = None,
    cursor: int | None = None,
    limit: int = Query(default=50, ge=1, le=100),
    principal: Principal = Depends(require_permission("audit.read")),
    db: Session = Depends(get_db),
):
    query = db.query(AdminAuditLog)
    if target_id:
        query = query.filter(AdminAuditLog.target_id == target_id)
    if cursor:
        query = query.filter(AdminAuditLog.id < cursor)
    items = query.order_by(AdminAuditLog.id.desc()).limit(limit + 1).all()
    has_more = len(items) > limit
    items = items[:limit]
    return {
        "items": [_audit_payload(item) for item in items],
        "next_cursor": items[-1].id if has_more and items else None,
    }


@router.get("/users/{user_id}/audit")
def user_audit(
    user_id: int,
    principal: Principal = Depends(require_permission("audit.read")),
    db: Session = Depends(get_db),
):
    return [
        _audit_payload(item)
        for item in db.query(AdminAuditLog)
        .filter(AdminAuditLog.target_type == "user", AdminAuditLog.target_id == str(user_id))
        .order_by(AdminAuditLog.id.desc())
        .limit(100)
        .all()
    ]


@router.post("/invitations", status_code=201)
def create_invitation(
    data: InvitationRequest,
    request: Request,
    principal: Principal = Depends(require_permission("admins.invite", require_mfa=True)),
    db: Session = Depends(get_db),
):
    _verify_mfa(principal, data.mfa_code)
    if data.role not in ADMIN_ROLES:
        raise HTTPException(status_code=422, detail="Invitation role must be administrative")
    email = str(data.email).strip().lower()
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(status_code=409, detail="User already exists")
    token = secrets.token_urlsafe(48)
    invitation = AdminInvitation(
        id=str(uuid.uuid4()),
        email=email,
        role_name=data.role,
        token_hash=hash_token(token),
        created_by=principal.user_id,
        expires_at=utcnow() + timedelta(hours=data.expires_in_hours),
        created_at=utcnow(),
    )
    db.add(invitation)
    _audit(
        db, request, principal, "admin.invitation.created", "invitation", invitation.id,
        after={"email": email, "role": data.role, "expires_at": _iso(invitation.expires_at)},
        reason="administrator invitation",
    )
    db.commit()
    return {
        "id": invitation.id,
        "email": invitation.email,
        "role": invitation.role_name,
        "expires_at": _iso(invitation.expires_at),
        "token": token,
    }


@router.get("/invitations")
def list_invitations(
    principal: Principal = Depends(require_permission("admins.invite")),
    db: Session = Depends(get_db),
):
    return [
        {
            "id": item.id,
            "email": item.email,
            "role": item.role_name,
            "created_by": item.created_by,
            "created_at": _iso(item.created_at),
            "expires_at": _iso(item.expires_at),
            "accepted_at": _iso(item.accepted_at),
            "revoked_at": _iso(item.revoked_at),
        }
        for item in db.query(AdminInvitation).order_by(AdminInvitation.created_at.desc()).all()
    ]


@router.delete("/invitations/{invitation_id}", status_code=204)
def revoke_invitation(
    invitation_id: str,
    request: Request,
    principal: Principal = Depends(require_permission("admins.invite", require_mfa=True)),
    db: Session = Depends(get_db),
):
    invitation = db.query(AdminInvitation).filter(AdminInvitation.id == invitation_id).first()
    if invitation is None:
        raise HTTPException(status_code=404, detail="Invitation not found")
    invitation.revoked_at = utcnow()
    _audit(
        db, request, principal, "admin.invitation.revoked", "invitation", invitation.id,
        before={"email": invitation.email, "role": invitation.role_name},
        reason="invitation revoked",
    )
    db.commit()
    return Response(status_code=204)
