from sqlalchemy import BigInteger, Boolean, Column, Integer, String

from app.db.base import Base


class DeliveryOutbox(Base):
    """Read-only ORM projection used for administrative fraud counters."""

    __tablename__ = "delivery_outbox"
    __table_args__ = {"extend_existing": True}

    id = Column(String(36), primary_key=True)
    campaign_id = Column(BigInteger().with_variant(Integer, "sqlite"), nullable=False)
    is_fraud = Column(Boolean, nullable=False, default=False)
