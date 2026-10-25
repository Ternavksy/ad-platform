from sqlalchemy import Column, BigInteger, DateTime, Integer, String, ForeignKey
from app.db.base import Base

class Creative(Base):
    __tablename__ = "creatives"

    id = Column(BigInteger().with_variant(Integer, "sqlite"), primary_key=True, autoincrement=True)
    ad_id = Column(BigInteger, ForeignKey("ads.id"), nullable=False)
    content = Column(String(1024), nullable=False)
    transaction_id = Column(BigInteger, ForeignKey("transactions.id"), nullable=True)
    media_type = Column(String(16), nullable=False, default="text")
    media_url = Column(String(2048), nullable=False, default="")
    media_path = Column(String(255), nullable=False, default="")
    mime_type = Column(String(128), nullable=False, default="")
    file_name = Column(String(255), nullable=False, default="")
    file_size = Column(BigInteger, nullable=False, default=0)
    moderation_status = Column(String(16), nullable=False, default="draft")
    moderation_reason = Column(String(500), nullable=False, default="")
    submitted_at = Column(DateTime, nullable=True)
    reviewed_at = Column(DateTime, nullable=True)
    reviewed_by = Column(BigInteger, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
