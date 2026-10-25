"""add creative moderation workflow

Revision ID: h8c9d0e1f2a3
Revises: g7b8c9d0e1f2
Create Date: 2026-10-25

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "h8c9d0e1f2a3"
down_revision: Union[str, Sequence[str], None] = "g7b8c9d0e1f2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Existing creatives remain deliverable. New creatives are explicitly created
    # as drafts by ads-api and must pass moderation before delivery.
    op.add_column(
        "creatives",
        sa.Column(
            "moderation_status",
            sa.String(length=16),
            nullable=False,
            server_default="approved",
        ),
    )
    op.add_column(
        "creatives",
        sa.Column(
            "moderation_reason",
            sa.String(length=500),
            nullable=False,
            server_default="",
        ),
    )
    op.add_column("creatives", sa.Column("submitted_at", sa.DateTime(), nullable=True))
    op.add_column("creatives", sa.Column("reviewed_at", sa.DateTime(), nullable=True))
    op.add_column("creatives", sa.Column("reviewed_by", sa.BigInteger(), nullable=True))
    op.create_foreign_key(
        "fk_creatives_reviewed_by_users",
        "creatives",
        "users",
        ["reviewed_by"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_creatives_moderation_queue",
        "creatives",
        ["moderation_status", "submitted_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_creatives_moderation_queue", table_name="creatives")
    op.drop_constraint(
        "fk_creatives_reviewed_by_users", "creatives", type_="foreignkey"
    )
    for name in (
        "reviewed_by",
        "reviewed_at",
        "submitted_at",
        "moderation_reason",
        "moderation_status",
    ):
        op.drop_column("creatives", name)
