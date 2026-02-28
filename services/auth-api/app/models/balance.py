from sqlalchemy import Column, BigInteger, ForeignKey, Numeric

from app.db.base import Base


class Balance(Base):
    __tablename__ = "balances"

    user_id = Column(BigInteger, ForeignKey("users.id"), primary_key=True)
    amount = Column(Numeric(12,2), nullable = False, default = 0)
