from sqlalchemy import Column, Integer, String, ForeignKey
from app.db.base import Base

class Ad(Base):
    __tablename__ = "ads"

    id = Column(Integer, primary_key=True)
    campaign_id = Column(Integer, ForeignKey("campaigns.id"), nullable=False)
    title = Column(String(255), nullable=False)
    status = Column(String(32), default="active")
