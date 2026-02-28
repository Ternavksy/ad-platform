from datetime import datetime
from sqlalchemy import Column, BigInteger, Numeric, ForeignKey, String, DateTime
from app.db.base import Base


class Transaction(Base):
    __tablename__ = "transactions"

    id = Column(BigInteger, primary_key = True)
    user_id = Column(BigInteger, ForeignKey("users.id"), nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    type = Column(String(32), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
