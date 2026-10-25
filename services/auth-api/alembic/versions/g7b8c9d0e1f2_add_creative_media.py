"""add image and video media to creatives

Revision ID: g7b8c9d0e1f2
Revises: f6a7b8c9d0e1
Create Date: 2026-10-25

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "g7b8c9d0e1f2"
down_revision: Union[str, Sequence[str], None] = "f6a7b8c9d0e1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("creatives", sa.Column("media_type", sa.String(length=16), nullable=False, server_default="text"))
    op.add_column("creatives", sa.Column("media_url", sa.String(length=2048), nullable=False, server_default=""))
    op.add_column("creatives", sa.Column("media_path", sa.String(length=255), nullable=False, server_default=""))
    op.add_column("creatives", sa.Column("mime_type", sa.String(length=128), nullable=False, server_default=""))
    op.add_column("creatives", sa.Column("file_name", sa.String(length=255), nullable=False, server_default=""))
    op.add_column("creatives", sa.Column("file_size", sa.BigInteger(), nullable=False, server_default="0"))

    op.add_column("ad_deliveries", sa.Column("creative_media_type", sa.String(length=16), nullable=False, server_default="text"))
    op.add_column("ad_deliveries", sa.Column("creative_media_url", sa.String(length=2048), nullable=False, server_default=""))
    op.add_column("ad_deliveries", sa.Column("creative_mime_type", sa.String(length=128), nullable=False, server_default=""))
    op.add_column("ad_deliveries", sa.Column("creative_file_name", sa.String(length=255), nullable=False, server_default=""))
    op.add_column("ad_deliveries", sa.Column("creative_file_size", sa.BigInteger(), nullable=False, server_default="0"))


def downgrade() -> None:
    for name in (
        "creative_file_size",
        "creative_file_name",
        "creative_mime_type",
        "creative_media_url",
        "creative_media_type",
    ):
        op.drop_column("ad_deliveries", name)

    for name in ("file_size", "file_name", "mime_type", "media_path", "media_url", "media_type"):
        op.drop_column("creatives", name)
