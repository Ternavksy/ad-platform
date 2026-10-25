"""add real ad delivery and outbox

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2026-10-24

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "c3d4e5f6a7b8"
down_revision: Union[str, Sequence[str], None] = "b2c3d4e5f6a7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "ads",
        sa.Column("placement", sa.String(length=64), nullable=False, server_default="feed"),
    )
    op.add_column(
        "ads",
        sa.Column("destination_url", sa.String(length=2048), nullable=False, server_default=""),
    )
    op.add_column(
        "ads",
        sa.Column("weight", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_index("ix_ads_delivery", "ads", ["status", "placement"])

    op.create_table(
        "ad_deliveries",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("campaign_id", sa.BigInteger(), nullable=False),
        sa.Column("ad_id", sa.BigInteger(), nullable=False),
        sa.Column("creative_id", sa.BigInteger(), nullable=False),
        sa.Column("ad_title", sa.String(length=255), nullable=False),
        sa.Column("creative_content", sa.String(length=1024), nullable=False),
        sa.Column("placement", sa.String(length=64), nullable=False),
        sa.Column("visitor_id", sa.String(length=128), nullable=True),
        sa.Column("destination_url", sa.String(length=2048), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("clicked_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_ad_deliveries_ad_id", "ad_deliveries", ["ad_id"])
    op.create_index("ix_ad_deliveries_created_at", "ad_deliveries", ["created_at"])

    op.create_table(
        "delivery_outbox",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("delivery_id", sa.String(length=36), nullable=False),
        sa.Column("event_type", sa.String(length=32), nullable=False),
        sa.Column("campaign_id", sa.BigInteger(), nullable=False),
        sa.Column("ad_id", sa.BigInteger(), nullable=False),
        sa.Column("creative_id", sa.BigInteger(), nullable=False),
        sa.Column("placement", sa.String(length=64), nullable=False),
        sa.Column("occurred_at", sa.DateTime(), nullable=False),
        sa.Column("published_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_delivery_outbox_pending",
        "delivery_outbox",
        ["published_at", "occurred_at"],
    )
    op.create_index("ix_delivery_outbox_delivery", "delivery_outbox", ["delivery_id"])


def downgrade() -> None:
    op.drop_table("delivery_outbox")
    op.drop_table("ad_deliveries")
    op.drop_index("ix_ads_delivery", table_name="ads")
    op.drop_column("ads", "weight")
    op.drop_column("ads", "destination_url")
    op.drop_column("ads", "placement")
