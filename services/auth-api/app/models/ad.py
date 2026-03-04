from sqlalchemy import Column, BigInteger, Integer, String, ForeignKey
from app.db.base import Base

class Ad(Base):
    __tablename__ = "ads"

    id = Column(BigInteger().with_variant(Integer, "sqlite"), primary_key=True, autoincrement=True)
    campaign_id = Column(BigInteger, ForeignKey("campaigns.id"), nullable=False)
    title = Column(String(255), nullable=False)
    transaction_id = Column(BigInteger, ForeignKey("transactions.id"), nullable=True)
    status = Column(String(32), default="active")
