import sys
from pathlib import Path
from logging.config import fileConfig

from alembic import context

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.append(str(BASE_DIR))

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

from app.db.base import Base
from app.models.user import User

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    from app.db.session import engine

    with engine.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
        )

        with context.begin_transaction():
            context.run_migrations()



if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
