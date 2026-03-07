#!/usr/bin/env python3
"""
RabbitMQ Worker for processing ad events
"""

import pika
import json
import logging
import os
import sys
import time
from typing import Dict, Any

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class AdEventWorker:
    def __init__(self, rabbitmq_url: str = "amqp://guest:guest@rabbitmq:5672/"):
        self.rabbitmq_url = rabbitmq_url
        self.connection = None
        self.channel = None

    def connect(self):
        """Establish connection to RabbitMQ"""
        while True:
            try:
                self.connection = pika.BlockingConnection(
                    pika.URLParameters(self.rabbitmq_url)
                )
                self.channel = self.connection.channel()
                self.channel.exchange_declare(
                    exchange="ad_events",
                    exchange_type="topic",
                    durable=True
                )

                self.channel.queue_declare(
                    queue="ad_worker_queue",
                    durable=True
                )

                self.channel.queue_bind(
                    exchange="ad_events",
                    queue="ad_worker_queue",
                    routing_key="ad.created"
                )

                self.channel.queue_bind(
                    exchange="ad_events",
                    queue="ad_worker_queue",
                    routing_key="ad.updated"
                )

                logger.info("Connected to RabbitMQ successfully")
                return

            except Exception as e:
                logger.warning(f"RabbitMQ not ready: {e}")
                time.sleep(5)

    def process_message(self, ch, method, properties, body):
        """Process incoming message"""
        try:
            data = json.loads(body.decode())
            logger.info(f"Processing message: {data}")

            event_type = data.get("type")
            ad_id = data.get("ad_id")

            if event_type == "ad_created":
                self.handle_ad_created(data)
            elif event_type == "ad_updated":
                self.handle_ad_updated(data)
            else:
                logger.warning(f"Unknown event type: {event_type}")

            ch.basic_ack(delivery_tag=method.delivery_tag)

        except json.JSONDecodeError as e:
            logger.error(f"Failed to decode message: {e}")
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

        except Exception as e:
            logger.error(f"Error processing message: {e}")
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

    def handle_ad_created(self, data: Dict[str, Any]):
        """Handle ad created event"""
        ad_id = data.get("ad_id")
        logger.info(f"Worker: Processing ad_created event for ad {ad_id}")
        time.sleep(0.1)

        logger.info(f"Worker: Completed processing ad_created event for ad {ad_id}")

    def handle_ad_updated(self, data: Dict[str, Any]):
        """Handle ad updated event"""
        ad_id = data.get("ad_id")
        logger.info(f"Worker: Processing ad_updated event for ad {ad_id}")
        time.sleep(0.1)

        logger.info(f"Worker: Completed processing ad_updated event for ad {ad_id}")

    def start(self):
        """Start consuming messages"""
        self.connect()

        try:
            self.channel.basic_qos(prefetch_count=1)

            self.channel.basic_consume(
                queue="ad_worker_queue",
                on_message_callback=self.process_message
            )

            logger.info("Starting worker...")
            self.channel.start_consuming()

        except KeyboardInterrupt:
            logger.info("Worker stopped by user")

        except Exception as e:
            logger.error(f"Error in worker: {e}")

        finally:
            self.stop()

    def stop(self):
        """Stop the worker"""
        try:
            if self.channel:
                self.channel.stop_consuming()
        except Exception:
            pass

        if self.connection:
            self.connection.close()

        logger.info("Worker stopped")


def main():
    """Main entry point"""
    rabbitmq_url = os.getenv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672/")

    worker = AdEventWorker(rabbitmq_url)

    try:
        worker.start()
    except Exception as e:
        logger.error(f"Worker failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()