"""add transaction description

Revision ID: b2c3d4e5f6a7
Revises: a1e1ae57334c
Create Date: 2026-10-23

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "b2c3d4e5f6a7"
down_revision: Union[str, Sequence[str], None] = "a1e1ae57334c"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "transactions",
        sa.Column("description", sa.String(length=255), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("transactions", "description")
