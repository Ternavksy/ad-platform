from jose import jwt

from app.core.security import hash_password, verify_password, create_access_token, SECRET_KEY, ALGORITHM


def test_hash_and_verify():
    pw = "s3cr3t"
    h = hash_password(pw)
    assert verify_password(pw, h)
    assert not verify_password("bad", h)


def test_create_access_token_payload():
    token = create_access_token("42", "admin")
    payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    assert payload.get("sub") == "42"
    assert payload.get("role") == "admin"
    assert "exp" in payload
