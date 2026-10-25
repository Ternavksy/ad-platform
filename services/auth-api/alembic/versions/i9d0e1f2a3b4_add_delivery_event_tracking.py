"""add impression, click and conversion event tracking

Revision ID: i9d0e1f2a3b4
Revises: h8c9d0e1f2a3
Create Date: 2026-10-25

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "i9d0e1f2a3b4"
down_revision: Union[str, Sequence[str], None] = "h8c9d0e1f2a3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


money = sa.Numeric(precision=14, scale=6)


def upgrade() -> None:
    op.add_column("ad_deliveries", sa.Column("impressed_at", sa.DateTime(), nullable=True))
    # Deliveries created before this migration already emitted impression events.
    op.execute("UPDATE ad_deliveries SET impressed_at = created_at")

    op.create_table(
        "delivery_conversions",
        sa.Column("delivery_id", sa.String(length=36), nullable=False),
        sa.Column("event_id", sa.String(length=128), nullable=False),
        sa.Column("conversion_type", sa.String(length=64), nullable=False, server_default="purchase"),
        sa.Column("value", money, nullable=False, server_default="0"),
        sa.Column("currency", sa.String(length=3), nullable=False, server_default=""),
        sa.Column("occurred_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["delivery_id"], ["ad_deliveries.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("delivery_id", "event_id"),
    )
    op.create_index(
        "ix_delivery_conversions_occurred_at",
        "delivery_conversions",
        ["occurred_at"],
    )

    op.add_column(
        "delivery_outbox",
        sa.Column("conversion_id", sa.String(length=128), nullable=False, server_default=""),
    )
    op.add_column(
        "delivery_outbox",
        sa.Column("conversion_type", sa.String(length=64), nullable=False, server_default=""),
    )
    op.add_column(
        "delivery_outbox",
        sa.Column("conversion_value", money, nullable=False, server_default="0"),
    )
    op.add_column(
        "delivery_outbox",
        sa.Column("conversion_currency", sa.String(length=3), nullable=False, server_default=""),
    )


def downgrade() -> None:
    op.drop_column("delivery_outbox", "conversion_currency")
    op.drop_column("delivery_outbox", "conversion_value")
    op.drop_column("delivery_outbox", "conversion_type")
    op.drop_column("delivery_outbox", "conversion_id")
    op.drop_index("ix_delivery_conversions_occurred_at", table_name="delivery_conversions")
    op.drop_table("delivery_conversions")
    op.drop_column("ad_deliveries", "impressed_at")
