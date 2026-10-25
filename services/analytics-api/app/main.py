import asyncio
import logging
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest

from app.api.analytics import router
from app.core.rabbitmq import create_message_handler, rabbitmq_consumer
from app.db.clickhouse import clickhouse_client


logger = logging.getLogger(__name__)

REQUESTS = Counter(
    "analytics_http_requests_total",
    "Total HTTP requests handled by analytics-api",
    ["method", "path", "status"],
)


async def connect_rabbitmq(retries: int = 30, delay_seconds: float = 2.0) -> None:
    for attempt in range(1, retries + 1):
        if await rabbitmq_consumer.connect():
            return
        logger.warning(
            "RabbitMQ is unavailable (attempt %s/%s)", attempt, retries
        )
        await asyncio.sleep(delay_seconds)
    raise RuntimeError("RabbitMQ did not become ready")


@asynccontextmanager
async def lifespan(app: FastAPI):
    clickhouse_client.connect()
    consumer_task = None

    await connect_rabbitmq()
    consumer_task = asyncio.create_task(
        rabbitmq_consumer.consume(create_message_handler())
    )
    logger.info("RabbitMQ consumer started")

    try:
        yield
    finally:
        if consumer_task:
            consumer_task.cancel()
            with suppress(asyncio.CancelledError):
                await consumer_task
        await rabbitmq_consumer.close()
        logger.info("RabbitMQ consumer stopped")


app = FastAPI(title="Analytics API", lifespan=lifespan)
app.include_router(router)


@app.middleware("http")
async def count_requests(request: Request, call_next):
    response = await call_next(request)
    REQUESTS.labels(
        method=request.method,
        path=request.url.path,
        status=str(response.status_code),
    ).inc()
    return response


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
