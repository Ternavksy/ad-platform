from fastapi import FastAPI
from app.api.analytics import router
from app.core.rabbitmq import rabbitmq_consumer, create_message_handler
import asyncio
import logging


logger = logging.getLogger(__name__)

app = FastAPI()

app.include_router(router)

@app.get("/health")
def health():
    return {"status": "ok"}

@app.on_event("startup")
async def startup_event():
    """Start RabbitMQ consumer on startup"""
    try:
        if await rabbitmq_consumer.connect():
            message_handler = create_message_handler()
            asyncio.create_task(rabbitmq_consumer.consume(message_handler))
            logger.info("RabbitMQ consumer started")
        else:
            logger.warning("Failed to start RabbitMQ consumer")
    except Exception as e:
        logger.error(f"Error starting RabbitMQ consumer: {e}")

@app.on_event("shutdown")
async def shutdown_event():
    """Close RabbitMQ connection on shutdown"""
    try:
        await rabbitmq_consumer.close()
        logger.info("RabbitMQ consumer stopped")
    except Exception as e:
        logger.error(f"Error stopping RabbitMQ consumer: {e}")
