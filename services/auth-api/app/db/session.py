from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

DATABASE_URL = "mysql+pymysql://dev:devpass@mysql:3306/ad_platform"

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping = True,
    future = True
)

SessionLocal = sessionmaker(
    bind=engine,
    autocommit=False,
    autoflush=False

)