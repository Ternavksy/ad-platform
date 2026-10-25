"""add audience, geography and device targeting

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-10-24

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "e5f6a7b8c9d0"
down_revision: Union[str, Sequence[str], None] = "d4e5f6a7b8c9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def delivery_columns() -> tuple[sa.Column, ...]:
    return (
        sa.Column("audience_age", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("audience_gender", sa.String(length=32), nullable=False, server_default=""),
        sa.Column("audience_interests", sa.String(length=2048), nullable=False, server_default=""),
        sa.Column("country", sa.String(length=2), nullable=False, server_default=""),
        sa.Column("region", sa.String(length=128), nullable=False, server_default=""),
        sa.Column("city", sa.String(length=128), nullable=False, server_default=""),
        sa.Column("device_type", sa.String(length=32), nullable=False, server_default=""),
        sa.Column("operating_system", sa.String(length=32), nullable=False, server_default=""),
    )


def upgrade() -> None:
    ad_columns = (
        sa.Column("target_min_age", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("target_max_age", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("target_genders", sa.String(length=255), nullable=False, server_default=""),
        sa.Column("target_interests", sa.String(length=2048), nullable=False, server_default=""),
        sa.Column("target_countries", sa.String(length=1024), nullable=False, server_default=""),
        sa.Column("target_regions", sa.String(length=2048), nullable=False, server_default=""),
        sa.Column("target_cities", sa.String(length=2048), nullable=False, server_default=""),
        sa.Column("target_device_types", sa.String(length=255), nullable=False, server_default=""),
        sa.Column("target_operating_systems", sa.String(length=255), nullable=False, server_default=""),
    )
    for column in ad_columns:
        op.add_column("ads", column)

    for table in ("ad_deliveries", "delivery_outbox"):
        for column in delivery_columns():
            op.add_column(table, column)


def downgrade() -> None:
    delivery_names = (
        "operating_system",
        "device_type",
        "city",
        "region",
        "country",
        "audience_interests",
        "audience_gender",
        "audience_age",
    )
    for table in ("delivery_outbox", "ad_deliveries"):
        for name in delivery_names:
            op.drop_column(table, name)

    ad_names = (
        "target_operating_systems",
        "target_device_types",
        "target_cities",
        "target_regions",
        "target_countries",
        "target_interests",
        "target_genders",
        "target_max_age",
        "target_min_age",
    )
    for name in ad_names:
        op.drop_column("ads", name)
