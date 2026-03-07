import pika
import json
import logging
from typing import Optional
from contextlib import contextmanager

logger = logging.getLogger(__name__)


class RabbitMQService:
    def __init__(self, url: str = "amqp://guest:guest@rabbitmq:5672/"):
        self.url = url
        self.connection = None
        self.channel = None

    def connect(self):
        """Establish connection to RabbitMQ"""
        try:
            self.connection = pika.BlockingConnection(
                pika.URLParameters(self.url)
            )
            self.channel = self.connection.channel()
            
            self.channel.exchange_declare(
                exchange='ad_events',
                exchange_type='topic',
                durable=True
            )
            
            logger.info("Connected to RabbitMQ successfully")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to RabbitMQ: {e}")
            return False

    def publish_ad_created(self, ad_id: str):
        """Publish ad created event"""
        if not self.channel:
            logger.warning("RabbitMQ channel not available")
            return

        event = {
            "type": "ad_created",
            "ad_id": ad_id,
            "created": "2026-03-06T13:00:00Z"
        }

        try:
            self.channel.basic_publish(
                exchange='ad_events',
                routing_key='ad.created',
                body=json.dumps(event),
                properties=pika.BasicProperties(
                    content_type='application/json',
                    delivery_mode=2
                )
            )
            logger.info(f"Published ad_created event for ad {ad_id}")
        except Exception as e:
            logger.error(f"Failed to publish ad_created event: {e}")

    def publish_ad_updated(self, ad_id: str):
        """Publish ad updated event"""
        if not self.channel:
            logger.warning("RabbitMQ channel not available")
            return

        event = {
            "type": "ad_updated",
            "ad_id": ad_id,
            "updated": "2026-03-06T13:00:00Z"
        }

        try:
            self.channel.basic_publish(
                exchange='ad_events',
                routing_key='ad.updated',
                body=json.dumps(event),
                properties=pika.BasicProperties(
                    content_type='application/json',
                    delivery_mode=2
                )
            )
            logger.info(f"Published ad_updated event for ad {ad_id}")
        except Exception as e:
            logger.error(f"Failed to publish ad_updated event: {e}")

    def close(self):
        """Close RabbitMQ connection"""
        if self.channel:
            self.channel.close()
        if self.connection:
            self.connection.close()
        logger.info("RabbitMQ connection closed")


rabbitmq_service = RabbitMQService()


@contextmanager
def get_rabbitmq():
    """Context manager for RabbitMQ connection"""
    if rabbitmq_service.connect():
        try:
            yield rabbitmq_service
        finally:
            rabbitmq_service.close()
    else:
        yield None