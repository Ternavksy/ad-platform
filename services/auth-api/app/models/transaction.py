from datetime import datetime, timezone
from sqlalchemy import Column, BigInteger, Integer, Numeric, ForeignKey, String, DateTime
from sqlalchemy.orm import relationship
from app.db.base import Base


def utc_now_naive() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class Transaction(Base):
    __tablename__ = "transactions"

    id = Column(BigInteger().with_variant(Integer, "sqlite"), primary_key = True, autoincrement=True)
    user_id = Column(BigInteger, ForeignKey("users.id"), nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    type = Column(String(32), nullable=False)
    description = Column(String(255), nullable=True)
    created_at = Column(DateTime, default=utc_now_naive)
    
    user = relationship("User", back_populates="transactions")
