from sqlalchemy import Column, Integer, String, ForeignKey
from app.db.base import Base

class Creative(Base):
    __tablename__ = "creatives"

    id = Column(Integer, primary_key=True)
    ad_id = Column(Integer, ForeignKey("ads.id"), nullable=False)
    content = Column(String(1024), nullable=False)
