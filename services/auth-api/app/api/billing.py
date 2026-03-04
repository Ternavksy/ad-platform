from decimal import Decimal
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, condecimal
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.balance import Balance
from app.models.transaction import Transaction
from app.models.ad import Ad
from app.models.creative import Creative

router = APIRouter(prefix="/billing", tags=["billing"])


class AmountRequest(BaseModel):
    user_id: int
    amount: condecimal(gt=Decimal("0"), max_digits=12, decimal_places=2)
    description: Optional[str] = None


class TransactionResponse(BaseModel):
    id: int
    user_id: int
    amount: Decimal
    type: str
    description: Optional[str]
    created_at: str


@router.post("/deposit", status_code=200)
def deposit(data: AmountRequest, db: Session = Depends(get_db)):
    balance = (
        db.query(Balance)
        .filter(Balance.user_id == data.user_id)
        .with_for_update()
        .first()
    )
    if balance is None:
        raise HTTPException(status_code=404, detail="Balance not found")

    balance.amount += data.amount

    transaction = Transaction(
        user_id=data.user_id,
        amount=data.amount,
        type="deposit",
        description=data.description,
    )
    db.add(transaction)
    db.flush()

    return {
        "user_id": data.user_id,
        "balance": float(balance.amount),
        "transaction_id": transaction.id,
    }


@router.post("/withdraw", status_code=200)
def withdraw(data: AmountRequest, db: Session = Depends(get_db)):
    balance = (
        db.query(Balance)
        .filter(Balance.user_id == data.user_id)
        .with_for_update()
        .first()
    )
    if balance is None:
        raise HTTPException(status_code=404, detail="Balance not found")
    if balance.amount < data.amount:
        raise HTTPException(status_code=422, detail="Insufficient funds")

    balance.amount -= data.amount

    transaction = Transaction(
        user_id=data.user_id,
        amount=data.amount,
        type="withdraw",
        description=data.description,
    )
    db.add(transaction)
    db.flush()

    return {
        "user_id": data.user_id,
        "balance": float(balance.amount),
        "transaction_id": transaction.id,
    }


@router.get("/balance/{user_id}", status_code=200)
def get_balance(user_id: int, db: Session = Depends(get_db)):
    balance = db.query(Balance).filter(Balance.user_id == user_id).first()
    if balance is None:
        raise HTTPException(status_code=404, detail="Balance not found")

    return {"user_id": user_id, "balance": float(balance.amount)}


@router.get("/transactions/{user_id}", status_code=200)
def get_transactions(user_id: int, db: Session = Depends(get_db)):
    transactions = (
        db.query(Transaction)
        .filter(Transaction.user_id == user_id)
        .all()
    )

    return [
        {
            "id": t.id,
            "user_id": t.user_id,
            "amount": float(t.amount),
            "type": t.type,
            "description": t.description,
            "created_at": t.created_at.isoformat(),
        }
        for t in transactions
    ]


@router.post("/charge-for-ad", status_code=200)
def charge_for_ad(
    user_id: int,
    ad_id: int,
    amount: condecimal(gt=Decimal("0"), max_digits=12, decimal_places=2),
    db: Session = Depends(get_db),
):
    balance = (
        db.query(Balance)
        .filter(Balance.user_id == user_id)
        .with_for_update()
        .first()
    )
    if balance is None:
        raise HTTPException(status_code=404, detail="Balance not found")
    if balance.amount < amount:
        raise HTTPException(status_code=422, detail="Insufficient funds")

    balance.amount -= amount

    transaction = Transaction(
        user_id=user_id,
        amount=amount,
        type="ad_creation",
        description=f"Charge for ad creation (ad_id: {ad_id})",
    )
    db.add(transaction)
    db.flush()

    ad = db.query(Ad).filter(Ad.id == ad_id).first()
    if ad:
        ad.transaction_id = transaction.id

    return {
        "user_id": user_id,
        "balance": float(balance.amount),
        "transaction_id": transaction.id,
        "ad_id": ad_id,
    }


@router.post("/charge-for-creative", status_code=200)
def charge_for_creative(
    user_id: int,
    creative_id: int,
    amount: condecimal(gt=Decimal("0"), max_digits=12, decimal_places=2),
    db: Session = Depends(get_db),
):
    balance = (
        db.query(Balance)
        .filter(Balance.user_id == user_id)
        .with_for_update()
        .first()
    )
    if balance is None:
        raise HTTPException(status_code=404, detail="Balance not found")
    if balance.amount < amount:
        raise HTTPException(status_code=422, detail="Insufficient funds")

    balance.amount -= amount

    transaction = Transaction(
        user_id=user_id,
        amount=amount,
        type="creative_creation",
        description=f"Charge for creative creation (creative_id: {creative_id})",
    )
    db.add(transaction)
    db.flush()

    creative = db.query(Creative).filter(Creative.id == creative_id).first()
    if creative:
        creative.transaction_id = transaction.id

    return {
        "user_id": user_id,
        "balance": float(balance.amount),
        "transaction_id": transaction.id,
        "creative_id": creative_id,
    }