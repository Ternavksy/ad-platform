from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    clickhouse_host: str = "clickhouse"
    clickhouse_port: int = 8123
    clickhouse_database: str = "analytics"
    clickhouse_username: str = "default"
    clickhouse_password: str = ""
    
    redis_host: str = "redis"
    redis_port: int = 6379
    redis_db: int = 0
    
    rabbitmq_host: str = "rabbitmq"
    rabbitmq_port: int = 5672
    rabbitmq_username: str = "guest"
    rabbitmq_password: str = "guest"
    
    class Config:
        env_file = ".env"


settings = Settings()