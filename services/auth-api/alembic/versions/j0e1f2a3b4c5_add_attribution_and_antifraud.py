"""add attribution and antifraud metadata

Revision ID: j0e1f2a3b4c5
Revises: i9d0e1f2a3b4
Create Date: 2026-10-25

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "j0e1f2a3b4c5"
down_revision: Union[str, Sequence[str], None] = "i9d0e1f2a3b4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "ad_deliveries",
        sa.Column("source_ip_hash", sa.String(length=64), nullable=False, server_default=""),
    )
    op.add_column(
        "ad_deliveries",
        sa.Column("user_agent_hash", sa.String(length=64), nullable=False, server_default=""),
    )
    op.add_column(
        "ad_deliveries",
        sa.Column("click_is_fraud", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column(
        "ad_deliveries",
        sa.Column("click_fraud_reason", sa.String(length=255), nullable=False, server_default=""),
    )
    op.create_index(
        "ix_ad_deliveries_visitor_click",
        "ad_deliveries",
        ["visitor_id", "clicked_at"],
    )
    op.create_index(
        "ix_ad_deliveries_visitor_impression",
        "ad_deliveries",
        ["visitor_id", "impressed_at"],
    )
    op.create_index(
        "ix_ad_deliveries_ip_click",
        "ad_deliveries",
        ["source_ip_hash", "clicked_at"],
    )

    conversion_columns = (
        sa.Column("attribution_model", sa.String(length=32), nullable=False, server_default="view_through"),
        sa.Column("attribution_window_hours", sa.Integer(), nullable=False, server_default="24"),
        sa.Column("is_fraud", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("fraud_reason", sa.String(length=255), nullable=False, server_default=""),
    )
    for column in conversion_columns:
        op.add_column("delivery_conversions", column)

    outbox_columns = (
        sa.Column("attribution_model", sa.String(length=32), nullable=False, server_default=""),
        sa.Column("attribution_window_hours", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_fraud", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("fraud_reason", sa.String(length=255), nullable=False, server_default=""),
    )
    for column in outbox_columns:
        op.add_column("delivery_outbox", column)


def downgrade() -> None:
    for name in (
        "fraud_reason",
        "is_fraud",
        "attribution_window_hours",
        "attribution_model",
    ):
        op.drop_column("delivery_outbox", name)
        op.drop_column("delivery_conversions", name)

    op.drop_index("ix_ad_deliveries_ip_click", table_name="ad_deliveries")
    op.drop_index("ix_ad_deliveries_visitor_impression", table_name="ad_deliveries")
    op.drop_index("ix_ad_deliveries_visitor_click", table_name="ad_deliveries")
    op.drop_column("ad_deliveries", "click_fraud_reason")
    op.drop_column("ad_deliveries", "click_is_fraud")
    op.drop_column("ad_deliveries", "user_agent_hash")
    op.drop_column("ad_deliveries", "source_ip_hash")
