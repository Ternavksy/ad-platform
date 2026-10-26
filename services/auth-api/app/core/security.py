import base64
import hashlib
import hmac
import json
import os
import secrets
import struct
import time
import uuid
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

import bcrypt
from jose import JWTError, jwt


SECRET_KEY = os.getenv("SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError("SECRET_KEY is not set")
ALGORITHM = "HS256"
ISSUER = os.getenv("JWT_ISSUER", "ad-platform-auth")
AUDIENCE = os.getenv("JWT_AUDIENCE", "ad-platform")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "15"))
REFRESH_TOKEN_EXPIRE_DAYS = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "30"))
MFA_CHALLENGE_EXPIRE_MINUTES = 5


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, hash_: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), hash_.encode("utf-8"))
    except (TypeError, ValueError):
        return False


def hash_token(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def hash_signal(value: str | None) -> str:
    return hash_token((value or "").strip()) if value else ""


def create_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def create_access_token(
    subject: str,
    role: str = "user",
    *,
    roles: list[str] | None = None,
    permissions: list[str] | None = None,
    token_version: int = 1,
    session_id: str | None = None,
    mfa: bool = False,
) -> str:
    now = utcnow()
    effective_roles = roles or [role]
    payload = {
        "sub": subject,
        "role": effective_roles[0] if effective_roles else role,
        "roles": effective_roles,
        "permissions": permissions or [],
        "token_version": token_version,
        "sid": session_id,
        "mfa": mfa,
        "jti": str(uuid.uuid4()),
        "typ": "access",
        "iss": ISSUER,
        "aud": AUDIENCE,
        "iat": now,
        "exp": now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def create_mfa_challenge(subject: str, purpose: str) -> str:
    now = utcnow()
    return jwt.encode(
        {
            "sub": subject,
            "purpose": purpose,
            "typ": "mfa_challenge",
            "jti": str(uuid.uuid4()),
            "iss": ISSUER,
            "aud": AUDIENCE,
            "iat": now,
            "exp": now + timedelta(minutes=MFA_CHALLENGE_EXPIRE_MINUTES),
        },
        SECRET_KEY,
        algorithm=ALGORITHM,
    )


def decode_access_token(token: str, expected_type: str | None = None) -> dict:
    try:
        payload = jwt.decode(
            token,
            SECRET_KEY,
            algorithms=[ALGORITHM],
            audience=AUDIENCE,
            issuer=ISSUER,
        )
    except JWTError as exc:
        raise ValueError("Invalid access token") from exc
    if expected_type and payload.get("typ") != expected_type:
        raise ValueError("Invalid token type")
    return payload


def _encryption_keys() -> tuple[bytes, bytes]:
    master = hashlib.sha512((os.getenv("MFA_ENCRYPTION_KEY") or SECRET_KEY).encode()).digest()
    return master[:32], master[32:]


def encrypt_secret(value: str) -> str:
    """Encrypt and authenticate a small TOTP secret using independent derived keys."""
    encryption_key, mac_key = _encryption_keys()
    nonce = secrets.token_bytes(16)
    raw = value.encode("utf-8")
    stream = b""
    counter = 0
    while len(stream) < len(raw):
        stream += hmac.new(encryption_key, nonce + struct.pack(">I", counter), hashlib.sha256).digest()
        counter += 1
    cipher = bytes(left ^ right for left, right in zip(raw, stream))
    tag = hmac.new(mac_key, nonce + cipher, hashlib.sha256).digest()
    return base64.urlsafe_b64encode(nonce + cipher + tag).decode("ascii")


def decrypt_secret(value: str) -> str:
    encryption_key, mac_key = _encryption_keys()
    packed = base64.urlsafe_b64decode(value.encode("ascii"))
    if len(packed) < 49:
        raise ValueError("Invalid encrypted secret")
    nonce, cipher, tag = packed[:16], packed[16:-32], packed[-32:]
    expected = hmac.new(mac_key, nonce + cipher, hashlib.sha256).digest()
    if not hmac.compare_digest(tag, expected):
        raise ValueError("Invalid encrypted secret")
    stream = b""
    counter = 0
    while len(stream) < len(cipher):
        stream += hmac.new(encryption_key, nonce + struct.pack(">I", counter), hashlib.sha256).digest()
        counter += 1
    return bytes(left ^ right for left, right in zip(cipher, stream)).decode("utf-8")


def create_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii").rstrip("=")


def totp_uri(secret: str, email: str) -> str:
    issuer = quote("Ad Platform")
    label = quote(f"Ad Platform:{email}")
    return f"otpauth://totp/{label}?secret={secret}&issuer={issuer}&digits=6&period=30"


def _totp(secret: str, counter: int) -> str:
    padded = secret + "=" * ((8 - len(secret) % 8) % 8)
    key = base64.b32decode(padded, casefold=True)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = (struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF) % 1_000_000
    return f"{value:06d}"


def verify_totp(secret: str, code: str, at_time: int | None = None) -> bool:
    if len(code) != 6 or not code.isdigit():
        return False
    counter = (at_time or int(time.time())) // 30
    return any(hmac.compare_digest(_totp(secret, counter + drift), code) for drift in (-1, 0, 1))


def generate_recovery_codes(count: int = 8) -> tuple[list[str], str]:
    codes = [f"{secrets.token_hex(4)[:4]}-{secrets.token_hex(4)[:4]}" for _ in range(count)]
    return codes, json.dumps([hash_token(code) for code in codes])


def consume_recovery_code(serialized: str | None, code: str) -> tuple[bool, str | None]:
    if not serialized:
        return False, serialized
    hashes = json.loads(serialized)
    candidate = hash_token(code.strip().lower())
    for index, value in enumerate(hashes):
        if hmac.compare_digest(value, candidate):
            del hashes[index]
            return True, json.dumps(hashes)
    return False, serialized
