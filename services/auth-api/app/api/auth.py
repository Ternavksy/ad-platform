import os

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.models.user import User
from app.models.balance import Balance
from app.schemas.user import UserCreate, Token

router = APIRouter(prefix="/auth", tags=["auth"])
bearer = HTTPBearer()


def configured_admin_emails() -> set[str]:
    return {
        value.strip().lower()
        for value in os.getenv("ADMIN_EMAILS", "").split(",")
        if value.strip()
    }


@router.post("/register", status_code=201)
def register(data: UserCreate, db: Session = Depends(get_db)):
    email = str(data.email).strip().lower()
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(status_code=400, detail="User already exists")

    user = User(
        email=email,
        password_hash=hash_password(data.password),
        role="admin" if email in configured_admin_emails() else "user",
    )
    db.add(user)
    db.flush()
    balance = Balance(user_id=user.id, amount=0)
    db.add(balance)
    db.commit()
    return {"id": user.id, "email": user.email}


@router.post("/login", response_model=Token)
def login(data: UserCreate, db: Session = Depends(get_db)):
    email = str(data.email).strip().lower()
    user = db.query(User).filter(User.email == email).first()
    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    token = create_access_token(str(user.id), user.role)
    return {"access_token": token}


@router.get("/me")
def me(
    credentials: HTTPAuthorizationCredentials = Depends(bearer),
    db: Session = Depends(get_db),
):
    try:
        payload = decode_access_token(credentials.credentials)
        user_id = int(payload["sub"])
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=401, detail="Invalid access token")

    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=401, detail="User not found")

    return {"id": user.id, "email": user.email, "role": user.role}
