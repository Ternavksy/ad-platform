from sqlalchemy import Column, BigInteger, ForeignKey, Integer, Numeric

from app.db.base import Base


class Balance(Base):
    __tablename__ = "balances"

    user_id = Column(BigInteger().with_variant(Integer, "sqlite"), ForeignKey("users.id"), primary_key=True)
    amount = Column(Numeric(12,2), nullable = False, default = 0)
