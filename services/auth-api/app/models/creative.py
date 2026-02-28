from sqlalchemy import Column, BigInteger, String, ForeignKey
from app.db.base import Base

class Creative(Base):
    __tablename__ = "creatives"

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    ad_id = Column(BigInteger, ForeignKey("ads.id"), nullable=False)
    content = Column(String(1024), nullable=False)
