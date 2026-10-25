"""add campaign budgets, bids and delivery schedule

Revision ID: f6a7b8c9d0e1
Revises: e5f6a7b8c9d0
Create Date: 2026-10-24

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "f6a7b8c9d0e1"
down_revision: Union[str, Sequence[str], None] = "e5f6a7b8c9d0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


money = sa.Numeric(precision=14, scale=6)


def upgrade() -> None:
    op.add_column("campaigns", sa.Column("budget_total", money, nullable=False, server_default="0"))
    op.add_column("campaigns", sa.Column("daily_limit", money, nullable=False, server_default="0"))
    op.add_column("campaigns", sa.Column("spent_total", money, nullable=False, server_default="0"))
    op.add_column("campaigns", sa.Column("spent_today", money, nullable=False, server_default="0"))
    op.add_column("campaigns", sa.Column("spent_date", sa.Date(), nullable=True))
    op.add_column("campaigns", sa.Column("starts_at", sa.DateTime(), nullable=True))
    op.add_column("campaigns", sa.Column("ends_at", sa.DateTime(), nullable=True))
    op.add_column("campaigns", sa.Column("schedule_days", sa.String(length=32), nullable=False, server_default=""))
    op.add_column("campaigns", sa.Column("schedule_start_hour", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("campaigns", sa.Column("schedule_end_hour", sa.Integer(), nullable=False, server_default="24"))
    op.create_index("ix_campaigns_delivery", "campaigns", ["status", "starts_at", "ends_at"])

    op.add_column("ads", sa.Column("bid_cpm", money, nullable=False, server_default="1"))

    for table in ("ad_deliveries", "delivery_outbox"):
        op.add_column(table, sa.Column("bid_cpm", money, nullable=False, server_default="0"))
        op.add_column(table, sa.Column("cost", money, nullable=False, server_default="0"))


def downgrade() -> None:
    for table in ("delivery_outbox", "ad_deliveries"):
        op.drop_column(table, "cost")
        op.drop_column(table, "bid_cpm")

    op.drop_column("ads", "bid_cpm")

    op.drop_index("ix_campaigns_delivery", table_name="campaigns")
    for name in (
        "schedule_end_hour",
        "schedule_start_hour",
        "schedule_days",
        "ends_at",
        "starts_at",
        "spent_date",
        "spent_today",
        "spent_total",
        "daily_limit",
        "budget_total",
    ):
        op.drop_column("campaigns", name)
