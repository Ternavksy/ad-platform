from sqlalchemy import Column, Integer, String, ForeignKey
from app.db.base import Base

class Campaign(Base):
    __tablename__ = "campaigns"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String(255), nullable=False)
    status = Column(String(32), default="draft")
