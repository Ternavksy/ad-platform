"""add sites, placements and ad formats

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-10-24

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "d4e5f6a7b8c9"
down_revision: Union[str, Sequence[str], None] = "c3d4e5f6a7b8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "ad_formats",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("code", sa.String(length=64), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("width", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("height", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="active"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("code", name="uq_ad_formats_code"),
    )
    op.create_table(
        "sites",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("domain", sa.String(length=255), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="active"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "domain", name="uq_sites_user_domain"),
    )
    op.create_index("ix_sites_user_id", "sites", ["user_id"])
    op.create_table(
        "placements",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("site_id", sa.BigInteger(), nullable=False),
        sa.Column("format_id", sa.BigInteger(), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("code", sa.String(length=36), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="active"),
        sa.ForeignKeyConstraint(["format_id"], ["ad_formats.id"]),
        sa.ForeignKeyConstraint(["site_id"], ["sites.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("code", name="uq_placements_code"),
    )
    op.create_index("ix_placements_site_id", "placements", ["site_id"])

    formats = sa.table(
        "ad_formats",
        sa.column("code", sa.String),
        sa.column("name", sa.String),
        sa.column("kind", sa.String),
        sa.column("width", sa.Integer),
        sa.column("height", sa.Integer),
        sa.column("status", sa.String),
    )
    op.bulk_insert(
        formats,
        [
            {"code": "banner_320x50", "name": "Мобильный баннер", "kind": "banner", "width": 320, "height": 50, "status": "active"},
            {"code": "banner_300x250", "name": "Средний прямоугольник", "kind": "banner", "width": 300, "height": 250, "status": "active"},
            {"code": "banner_728x90", "name": "Горизонтальный баннер", "kind": "banner", "width": 728, "height": 90, "status": "active"},
            {"code": "native_feed", "name": "Нативный блок", "kind": "native", "width": 0, "height": 0, "status": "active"},
            {"code": "story_9x16", "name": "История 9:16", "kind": "story", "width": 1080, "height": 1920, "status": "active"},
        ],
    )

    op.add_column("ads", sa.Column("placement_id", sa.BigInteger(), nullable=True))
    op.create_foreign_key(
        "fk_ads_placement_id",
        "ads",
        "placements",
        ["placement_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_ads_placement_id", "ads", ["placement_id"])

    for table in ("ad_deliveries", "delivery_outbox"):
        op.add_column(table, sa.Column("site_id", sa.BigInteger(), nullable=False, server_default="0"))
        op.add_column(table, sa.Column("placement_id", sa.BigInteger(), nullable=False, server_default="0"))
        op.add_column(table, sa.Column("format_id", sa.BigInteger(), nullable=False, server_default="0"))
        op.add_column(table, sa.Column("placement_code", sa.String(length=36), nullable=False, server_default=""))
        op.add_column(table, sa.Column("format_code", sa.String(length=64), nullable=False, server_default=""))

    op.add_column("ad_deliveries", sa.Column("format_width", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("ad_deliveries", sa.Column("format_height", sa.Integer(), nullable=False, server_default="0"))


def downgrade() -> None:
    op.drop_column("ad_deliveries", "format_height")
    op.drop_column("ad_deliveries", "format_width")
    for table in ("delivery_outbox", "ad_deliveries"):
        op.drop_column(table, "format_code")
        op.drop_column(table, "placement_code")
        op.drop_column(table, "format_id")
        op.drop_column(table, "placement_id")
        op.drop_column(table, "site_id")
    op.drop_index("ix_ads_placement_id", table_name="ads")
    op.drop_constraint("fk_ads_placement_id", "ads", type_="foreignkey")
    op.drop_column("ads", "placement_id")
    op.drop_table("placements")
    op.drop_table("sites")
    op.drop_table("ad_formats")
