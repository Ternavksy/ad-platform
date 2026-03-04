"""Add transaction_id to ads and creatives

Revision ID: a1e1ae57334c
Revises: 714cf48329fa
Create Date: 2026-03-02 15:08:23.695984

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1e1ae57334c'
down_revision: Union[str, Sequence[str], None] = '714cf48329fa'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Add transaction_id column to ads table
    op.add_column('ads', sa.Column('transaction_id', sa.Integer(), nullable=True))
    op.create_foreign_key(
        'fk_ads_transaction_id', 
        'ads', 'transactions', 
        ['transaction_id'], ['id']
    )
    
    # Add transaction_id column to creatives table
    op.add_column('creatives', sa.Column('transaction_id', sa.Integer(), nullable=True))
    op.create_foreign_key(
        'fk_creatives_transaction_id', 
        'creatives', 'transactions', 
        ['transaction_id'], ['id']
    )


def downgrade() -> None:
    """Downgrade schema."""
    # Drop foreign keys
    op.drop_constraint('fk_creatives_transaction_id', 'creatives', type_='foreignkey')
    op.drop_constraint('fk_ads_transaction_id', 'ads', type_='foreignkey')
    
    # Drop columns
    op.drop_column('creatives', 'transaction_id')
    op.drop_column('ads', 'transaction_id')
