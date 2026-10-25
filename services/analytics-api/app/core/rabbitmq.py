import asyncio
import aio_pika
import json
import logging
import os
from typing import Optional, Callable, Dict, Any
from contextlib import asynccontextmanager
from datetime import datetime

from app.db.clickhouse import clickhouse_client

logger = logging.getLogger(__name__)


class RabbitMQConsumer:
    def __init__(self, url: Optional[str] = None):
        self.url = url or os.getenv(
            "RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672/"
        )
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
            await self.queue.bind(self.exchange, "ad.impression")
            await self.queue.bind(self.exchange, "ad.click")
            
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

        async with self.queue.iterator() as queue_iter:
            async for message in queue_iter:
                try:
                    async with message.process(requeue=True):
                        try:
                            data = json.loads(message.body.decode())
                            logger.info(f"Received message: {data}")
                            callback(data)
                        except json.JSONDecodeError as e:
                            logger.error(f"Failed to decode message: {e}")
                except asyncio.CancelledError:
                    raise
                except Exception:
                    logger.exception("Failed to process RabbitMQ message; it was requeued")

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
        if event_type in {"ad_created", "ad_updated"}:
            logger.info("Analytics: metadata event %s does not change delivery metrics", event_type)
            return
        if event_type not in {"ad_impression", "ad_click"}:
            logger.warning("Unknown event type: %s", event_type)
            return

        occurred_at = message.get("occurred_at")
        try:
            timestamp = datetime.fromisoformat(occurred_at.replace("Z", "+00:00"))
        except (AttributeError, ValueError) as exc:
            raise ValueError("delivery event has an invalid occurred_at") from exc
        if timestamp.tzinfo is not None:
            timestamp = timestamp.replace(tzinfo=None)

        stats_data = [
            (
                str(message["event_id"]),
                str(message["delivery_id"]),
                timestamp.date(),
                int(message["campaign_id"]),
                int(message["ad_id"]),
                int(message["creative_id"]),
                str(message["placement"]),
                int(message.get("site_id", 0)),
                int(message.get("placement_id", 0)),
                int(message.get("format_id", 0)),
                str(message.get("placement_code", "")),
                str(message.get("format_code", "")),
                int(message.get("audience_age", 0)),
                str(message.get("audience_gender", "")),
                str(message.get("audience_interests", "")),
                str(message.get("country", "")),
                str(message.get("region", "")),
                str(message.get("city", "")),
                str(message.get("device_type", "")),
                str(message.get("operating_system", "")),
                1 if event_type == "ad_impression" else 0,
                1 if event_type == "ad_click" else 0,
                float(message.get("cost", 0.0)) if event_type == "ad_impression" else 0.0,
                timestamp,
            )
        ]
        clickhouse_client.insert_delivery_stats(stats_data)
        logger.info(
            "Analytics: saved %s for delivery %s",
            event_type,
            message["delivery_id"],
        )

    return handle_message
