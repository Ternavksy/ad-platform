import asyncio
import aio_pika
import json
import logging
from typing import Optional, Callable, Dict, Any
from contextlib import asynccontextmanager
from datetime import datetime

from app.db.clickhouse import clickhouse_client

logger = logging.getLogger(__name__)


class RabbitMQConsumer:
    def __init__(self, url: str = "amqp://guest:guest@rabbitmq:5672/"):
        self.url = url
        self.connection = None
        self.channel = None
        self.exchange = None
        self.queue = None

    async def connect(self):
        """Establish connection to RabbitMQ"""
        try:
            self.connection = await aio_pika.connect_robust(self.url)
            self.channel = await self.connection.channel()
            
            self.exchange = await self.channel.declare_exchange(
                "ad_events",
                aio_pika.ExchangeType.TOPIC,
                durable=True
            )
            
            self.queue = await self.channel.declare_queue(
                "analytics_queue",
                durable=True
            )
            
            await self.queue.bind(self.exchange, "ad.created")
            await self.queue.bind(self.exchange, "ad.updated")
            
            logger.info("Connected to RabbitMQ successfully")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to RabbitMQ: {e}")
            return False

    async def consume(self, callback: Callable[[Dict[str, Any]], None]):
        """Start consuming messages"""
        if not self.queue:
            logger.warning("RabbitMQ queue not available")
            return

        try:
            async with self.queue.iterator() as queue_iter:
                async for message in queue_iter:
                    async with message.process():
                        try:
                            data = json.loads(message.body.decode())
                            logger.info(f"Received message: {data}")
                            callback(data)
                        except json.JSONDecodeError as e:
                            logger.error(f"Failed to decode message: {e}")
        except Exception as e:
            logger.error(f"Error in message consumption: {e}")

    async def close(self):
        """Close RabbitMQ connection"""
        if self.channel:
            await self.channel.close()
        if self.connection:
            await self.connection.close()
        logger.info("RabbitMQ connection closed")


rabbitmq_consumer = RabbitMQConsumer()


@asynccontextmanager
async def get_rabbitmq_consumer():
    """Context manager for RabbitMQ consumer"""
    if await rabbitmq_consumer.connect():
        try:
            yield rabbitmq_consumer
        finally:
            await rabbitmq_consumer.close()
    else:
        yield None


def create_message_handler():
    """Create a message handler for analytics"""
    
    def handle_message(message: Dict[str, Any]):
        event_type = message.get("type")
        ad_id = message.get("ad_id")

        if event_type in {"ad_created", "ad_updated"}:
            logger.info(f"Analytics: Processing {event_type} event for ad {ad_id}")
            now = datetime.now()
            # Записываем событие в ClickHouse для статистики
            stats_data = [
                (
                    now.date(),
                    message.get("campaign_id", 0),
                    int(ad_id) if ad_id else 0,
                    message.get("creative_id", 0),
                    1,  # показы
                    0,  # клики
                    0.0,  # стоимость
                    now,
                )
            ]
            try:
                clickhouse_client.insert_ad_stats(stats_data)
                logger.info(f"Analytics: Saved {event_type} event for ad {ad_id} to ClickHouse")
            except Exception:
                logger.exception(f"Failed to save {event_type} event to ClickHouse")

        else:
            logger.warning(f"Unknown event type: {event_type}")

    return handle_message