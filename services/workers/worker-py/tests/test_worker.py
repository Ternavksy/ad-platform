import json
import unittest
from unittest.mock import Mock

from worker import AdEventWorker


class FakeChannel:
    def __init__(self):
        self.acked = []
        self.nacked = []

    def basic_ack(self, delivery_tag):
        self.acked.append(delivery_tag)

    def basic_nack(self, delivery_tag, requeue):
        self.nacked.append((delivery_tag, requeue))


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.worker = AdEventWorker()
        self.worker.handle_ad_created = Mock()
        self.worker.handle_ad_updated = Mock()
        self.channel = FakeChannel()
        self.method = type("Method", (), {"delivery_tag": 7})()

    def test_created_event_is_processed_and_acked(self):
        payload = {"type": "ad_created", "ad_id": "42"}

        self.worker.process_message(
            self.channel, self.method, None, json.dumps(payload).encode()
        )

        self.worker.handle_ad_created.assert_called_once_with(payload)
        self.assertEqual(self.channel.acked, [7])
        self.assertEqual(self.channel.nacked, [])

    def test_invalid_json_is_rejected(self):
        self.worker.process_message(self.channel, self.method, None, b"not-json")

        self.assertEqual(self.channel.acked, [])
        self.assertEqual(self.channel.nacked, [(7, False)])


if __name__ == "__main__":
    unittest.main()
