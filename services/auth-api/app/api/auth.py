from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.security import hash_password, create_access_token, verify_password
from app.db.session import SessionLocal
from app.models.user import User
from app.schemas.user import UserCreate, Token

router = APIRouter(prefix="/auth", tags=["auth"])

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@router.post("/register")
def register(data: UserCreate, db: Session = Depends(get_db)):
    if db.query(User).filter(User.email == data.email).first():
        raise HTTPException(status_code = 400, detail="User already exists")

    user = User(
        email = data.email,
        password_hash = hash_password(data.password),
        role="user",
    )
    db.add(user)
    db.commit()
    return {"id": user.id, "email": user.email}

@router.post("/login", response_model=Token)
def login(data: UserCreate, db:Session = Depends(get_db)):
    user = db.query(User).filter(User.email == data.email).first()
    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    token = create_access_token(str(user.id), user.role)
    return {"access_token": token}