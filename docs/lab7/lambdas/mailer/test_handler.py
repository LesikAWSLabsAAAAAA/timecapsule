import json
import os
import unittest
from unittest.mock import MagicMock, patch

import handler


def record(message_id, body):
    return {"messageId": message_id, "body": json.dumps(body)}


class MailerTests(unittest.TestCase):
    def test_batch_reports_only_failures(self):
        conn = MagicMock()
        cursor = conn.__enter__.return_value.cursor.return_value.__enter__.return_value
        events = [
            record("ok", {"eventType": "capsule.sealed", "capsuleId": 5}),
            record("bad", {"eventType": "capsule.sealed", "capsuleId": True}),
            record("wrong", {"eventType": "other", "capsuleId": 5}),
        ]
        with patch.object(handler, "connect", return_value=conn), \
             patch.object(handler.time, "sleep") as sleep, \
             patch.dict(os.environ, {"MAIL_DELAY_SECONDS": "2"}):
            self.assertEqual(handler.handler({"Records": events}, None),
                             {"batchItemFailures": [{"itemIdentifier": "bad"}, {"itemIdentifier": "wrong"}]})
        sleep.assert_called_once_with(2.0)
        self.assertEqual(cursor.execute.call_args.args[1], (5,))
        self.assertIn("ON CONFLICT (capsule_id)", cursor.execute.call_args.args[0])

    def test_database_failure_is_retried(self):
        with patch.object(handler, "connect", side_effect=RuntimeError("db unavailable")), \
             patch.object(handler.time, "sleep"):
            result = handler.handler({"Records": [record("x", {"eventType": "capsule.sealed", "capsuleId": 2})]}, None)
        self.assertEqual(result, {"batchItemFailures": [{"itemIdentifier": "x"}]})

    def test_reject_bad_delay(self):
        with patch.dict(os.environ, {"MAIL_DELAY_SECONDS": "nan"}):
            with self.assertRaises(ValueError):
                handler.process(record("x", {"eventType": "capsule.sealed", "capsuleId": 2}))


if __name__ == "__main__":
    unittest.main()
