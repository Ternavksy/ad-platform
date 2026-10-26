from jose import jwt

from app.core.security import (
    ALGORITHM,
    AUDIENCE,
    ISSUER,
    SECRET_KEY,
    create_access_token,
    hash_password,
    verify_password,
)


def test_hash_and_verify():
    pw = "s3cr3t"
    h = hash_password(pw)
    assert verify_password(pw, h)
    assert not verify_password("bad", h)


def test_create_access_token_payload():
    token = create_access_token("42", "admin")
    payload = jwt.decode(
        token,
        SECRET_KEY,
        algorithms=[ALGORITHM],
        audience=AUDIENCE,
        issuer=ISSUER,
    )
    assert payload.get("sub") == "42"
    assert payload.get("role") == "admin"
    assert payload.get("roles") == ["admin"]
    assert payload.get("typ") == "access"
    assert "exp" in payload
