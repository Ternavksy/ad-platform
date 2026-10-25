from sqlalchemy import Column, BigInteger, Date, DateTime, Integer, Numeric, String, ForeignKey
from app.db.base import Base

class Campaign(Base):
    __tablename__ = "campaigns"

    id = Column(BigInteger().with_variant(Integer, "sqlite"), primary_key=True, autoincrement=True)
    user_id = Column(BigInteger, ForeignKey("users.id"), nullable=False)
    name = Column(String(255), nullable=False)
    status = Column(String(32), default="draft")
    budget_total = Column(Numeric(14, 6), nullable=False, default=0)
    daily_limit = Column(Numeric(14, 6), nullable=False, default=0)
    spent_total = Column(Numeric(14, 6), nullable=False, default=0)
    spent_today = Column(Numeric(14, 6), nullable=False, default=0)
    spent_date = Column(Date, nullable=True)
    starts_at = Column(DateTime, nullable=True)
    ends_at = Column(DateTime, nullable=True)
    schedule_days = Column(String(32), nullable=False, default="")
    schedule_start_hour = Column(Integer, nullable=False, default=0)
    schedule_end_hour = Column(Integer, nullable=False, default=24)
