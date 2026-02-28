from sqlalchemy import Column, BigInteger, String, ForeignKey
from app.db.base import Base

class Ad(Base):
    __tablename__ = "ads"

    id = Column(BigInteger, primary_key=True)
    campaign_id = Column(BigInteger, ForeignKey("campaigns.id"), nullable=False)
    title = Column(String(255), nullable=False)
    status = Column(String(32), default="active")
