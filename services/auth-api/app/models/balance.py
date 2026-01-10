from sqlalchemy import Column, Integer, ForeignKey, Numeric

from app.db.base import Base


class Balance(Base):
    __tablename__ = "balances"

    user_id = Column(Integer, ForeignKey("users.id"), primary_key=True)
    amount = Column(Numeric(12,2), nullable = False, default = 0)
