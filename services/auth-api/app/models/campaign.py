from sqlalchemy import Column, BigInteger, Integer, String, ForeignKey
from app.db.base import Base

class Campaign(Base):
    __tablename__ = "campaigns"

    id = Column(BigInteger().with_variant(Integer, "sqlite"), primary_key=True, autoincrement=True)
    user_id = Column(BigInteger, ForeignKey("users.id"), nullable=False)
    name = Column(String(255), nullable=False)
    status = Column(String(32), default="draft")
