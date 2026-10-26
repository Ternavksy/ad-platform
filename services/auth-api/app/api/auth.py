import uuid
from datetime import timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy.orm import Session

from app.core.access import ADMIN_ROLES, assign_roles, user_permissions, user_roles
from app.core.authentication import (
    Principal,
    get_current_principal,
    issue_token_pair,
    revoke_user_sessions,
    rotate_refresh_token,
    user_is_available,
)
from app.core.security import (
    consume_recovery_code,
    create_mfa_challenge,
    create_totp_secret,
    decode_access_token,
    decrypt_secret,
    encrypt_secret,
    generate_recovery_codes,
    hash_password,
    hash_token,
    totp_uri,
    utcnow,
    verify_password,
    verify_totp,
)
from app.core.security_state import SecurityStateUnavailable, security_state_cache
from app.db.session import get_db
from app.models.admin import AdminInvitation, PasswordResetToken, UserSession
from app.models.balance import Balance
from app.models.user import User
from app.schemas.user import UserCreate


router = APIRouter(prefix="/auth", tags=["auth"])


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=32)


class MFARequest(BaseModel):
    challenge_token: str
    code: str = Field(min_length=6, max_length=32)


class InvitationAcceptRequest(BaseModel):
    token: str = Field(min_length=32)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class PasswordResetCompleteRequest(BaseModel):
    token: str = Field(min_length=32)
    password: str = Field(min_length=8, max_length=128)


def serialize_user(user: User) -> dict:
    roles = user_roles(user)
    permissions = user_permissions(user)
    return {
        "id": user.id,
        "email": user.email,
        "role": user.role,
        "roles": roles,
        "permissions": permissions,
        "status": user.status,
        "mfa_enabled": user.mfa_confirmed_at is not None,
        "password_reset_required": user.password_reset_required,
        "workspaces": [
            "advertiser",
            *(["admin"] if set(roles) & ADMIN_ROLES else []),
        ],
    }


@router.post("/register", status_code=201)
def register(data: UserCreate, db: Session = Depends(get_db)):
    email = str(data.email).strip().lower()
    if len(data.password) < 8:
        raise HTTPException(status_code=422, detail="Password must contain at least 8 characters")
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(status_code=400, detail="User already exists")
    user = User(email=email, password_hash=hash_password(data.password), role="user")
    db.add(user)
    db.flush()
    assign_roles(db, user, ["user"])
    db.add(Balance(user_id=user.id, amount=0))
    db.flush()
    security_state_cache.set_user(user)
    db.commit()
    return {"id": user.id, "email": user.email}


@router.post("/invitations/accept", status_code=201)
def accept_invitation(data: InvitationAcceptRequest, db: Session = Depends(get_db)):
    now = utcnow()
    invitation = (
        db.query(AdminInvitation)
        .filter(AdminInvitation.token_hash == hash_token(data.token))
        .with_for_update()
        .first()
    )
    email = str(data.email).strip().lower()
    if (
        invitation is None
        or invitation.email != email
        or invitation.accepted_at is not None
        or invitation.revoked_at is not None
        or invitation.expires_at.replace(tzinfo=invitation.expires_at.tzinfo or now.tzinfo) <= now
    ):
        raise HTTPException(status_code=400, detail="Invitation is invalid or expired")
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(status_code=409, detail="User already exists")
    user = User(email=email, password_hash=hash_password(data.password), role="admin")
    db.add(user)
    db.flush()
    assign_roles(db, user, [invitation.role_name])
    db.add(Balance(user_id=user.id, amount=0))
    invitation.accepted_at = now
    security_state_cache.set_user(user)
    db.commit()
    return {"id": user.id, "email": user.email, "mfa_setup_required": True}


@router.post("/login")
def login(data: UserCreate, request: Request, db: Session = Depends(get_db)):
    now = utcnow()
    email = str(data.email).strip().lower()
    ip_address = request.client.host if request.client else ""
    try:
        security_state_cache.check_login_rate_limit(email, ip_address)
    except PermissionError:
        raise HTTPException(status_code=429, detail="Too many login attempts. Try again later")
    except SecurityStateUnavailable:
        raise HTTPException(status_code=503, detail="Login security service is unavailable")
    user = db.query(User).filter(User.email == email).with_for_update().first()
    if user and user.locked_until:
        locked_until = user.locked_until.replace(tzinfo=user.locked_until.tzinfo or now.tzinfo)
        if locked_until > now:
            raise HTTPException(status_code=429, detail="Too many failed attempts. Try again later")
    if not user or not verify_password(data.password, user.password_hash):
        if user:
            user.failed_login_attempts += 1
            if user.failed_login_attempts >= 5:
                user.locked_until = now + timedelta(minutes=15)
            db.commit()
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not user_is_available(user, now):
        raise HTTPException(status_code=403, detail="Account is not active")
    security_state_cache.clear_login_rate_limit(email, ip_address)
    user.failed_login_attempts = 0
    user.locked_until = None
    user.last_login_at = now
    roles = user_roles(user)
    security_state_cache.set_user(user)
    if set(roles) & {"admin", "superadmin"}:
        if user.mfa_confirmed_at is None:
            secret = (
                decrypt_secret(user.mfa_secret_encrypted)
                if user.mfa_secret_encrypted
                else create_totp_secret()
            )
            user.mfa_secret_encrypted = encrypt_secret(secret)
            db.commit()
            return {
                "mfa_setup_required": True,
                "mfa_challenge": create_mfa_challenge(str(user.id), "setup"),
                "mfa_secret": secret,
                "otpauth_uri": totp_uri(secret, user.email),
            }
        db.commit()
        return {
            "mfa_required": True,
            "mfa_challenge": create_mfa_challenge(str(user.id), "login"),
        }
    response = issue_token_pair(db, user, request, mfa=False)
    db.commit()
    return response


@router.post("/mfa/confirm")
def confirm_mfa(data: MFARequest, request: Request, db: Session = Depends(get_db)):
    try:
        payload = decode_access_token(data.challenge_token, "mfa_challenge")
        user_id = int(payload["sub"])
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=401, detail="Invalid MFA challenge")
    user = db.query(User).filter(User.id == user_id).with_for_update().first()
    if user is None or not user_is_available(user):
        raise HTTPException(status_code=401, detail="Account is not active")
    if not user.mfa_secret_encrypted:
        raise HTTPException(status_code=409, detail="MFA setup was not started")
    valid = verify_totp(decrypt_secret(user.mfa_secret_encrypted), data.code)
    used_recovery = False
    if not valid and payload.get("purpose") == "login":
        valid, updated_codes = consume_recovery_code(user.mfa_recovery_codes, data.code)
        if valid:
            user.mfa_recovery_codes = updated_codes
            used_recovery = True
    if not valid:
        raise HTTPException(status_code=401, detail="Invalid MFA code")
    recovery_codes: list[str] = []
    if payload.get("purpose") == "setup":
        recovery_codes, serialized = generate_recovery_codes()
        user.mfa_recovery_codes = serialized
        user.mfa_confirmed_at = utcnow()
    response = issue_token_pair(db, user, request, mfa=True)
    if recovery_codes:
        response["recovery_codes"] = recovery_codes
    if used_recovery:
        response["recovery_code_used"] = True
    db.commit()
    return response


@router.post("/refresh")
def refresh(data: RefreshRequest, request: Request, db: Session = Depends(get_db)):
    response = rotate_refresh_token(db, data.refresh_token, request)
    db.commit()
    return response


@router.post("/password-reset/complete", status_code=204)
def complete_password_reset(
    data: PasswordResetCompleteRequest,
    db: Session = Depends(get_db),
):
    now = utcnow()
    reset = (
        db.query(PasswordResetToken)
        .filter(PasswordResetToken.token_hash == hash_token(data.token))
        .with_for_update()
        .first()
    )
    expires_at = None if reset is None else reset.expires_at
    if expires_at is not None and expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if reset is None or reset.used_at is not None or expires_at is None or expires_at <= now:
        raise HTTPException(status_code=400, detail="Password reset token is invalid or expired")
    user = db.query(User).filter(User.id == reset.user_id).with_for_update().first()
    if user is None or user.status in {"blocked", "deleted"}:
        raise HTTPException(status_code=403, detail="Account is not active")
    user.password_hash = hash_password(data.password)
    user.password_reset_required = False
    user.token_version += 1
    user.row_version += 1
    user.updated_at = now
    reset.used_at = now
    revoke_user_sessions(db, user.id)
    try:
        security_state_cache.set_user(user, strict=True)
    except SecurityStateUnavailable:
        raise HTTPException(status_code=503, detail="Security state service is unavailable")
    db.commit()
    return None


@router.post("/logout", status_code=204)
def logout(
    data: RefreshRequest,
    principal: Principal = Depends(get_current_principal),
    db: Session = Depends(get_db),
):
    session = db.query(UserSession).filter(
        UserSession.refresh_token_hash == hash_token(data.refresh_token),
        UserSession.user_id == principal.user_id,
    ).first()
    if session and session.revoked_at is None:
        session.revoked_at = utcnow()
        try:
            security_state_cache.set_session(session.id, active=False, strict=True)
        except SecurityStateUnavailable:
            raise HTTPException(status_code=503, detail="Security state service is unavailable")
    db.commit()


@router.post("/logout-all", status_code=204)
def logout_all(
    principal: Principal = Depends(get_current_principal),
    db: Session = Depends(get_db),
):
    revoke_user_sessions(db, principal.user_id)
    principal.user.token_version += 1
    principal.user.row_version += 1
    try:
        security_state_cache.set_user(principal.user, strict=True)
    except SecurityStateUnavailable:
        raise HTTPException(status_code=503, detail="Security state service is unavailable")
    db.commit()


@router.get("/me")
def me(principal: Principal = Depends(get_current_principal)):
    return serialize_user(principal.user)
