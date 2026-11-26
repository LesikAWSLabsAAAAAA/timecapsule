import unittest
from unittest.mock import MagicMock, patch

import handler


class OpenerTests(unittest.TestCase):
    def test_result_and_atomic_statement(self):
        conn = MagicMock()
        cursor = conn.__enter__.return_value.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = (3,)
        with patch.object(handler, "connect", return_value=conn):
            self.assertEqual(handler.handler({}, None), {"eventType": "capsules.opened", "openedCount": 3})
        sql = cursor.execute.call_args.args[0]
        self.assertIn("UPDATE capsules", sql)
        self.assertIn("INSERT INTO notifications", sql)
        self.assertIn("opened_at IS NULL", sql)

    def test_empty_result_does_not_match_opened_filter(self):
        conn = MagicMock()
        conn.__enter__.return_value.cursor.return_value.__enter__.return_value.fetchone.return_value = (0,)
        with patch.object(handler, "connect", return_value=conn):
            self.assertEqual(handler.handler({}, None), {"eventType": "capsules.none_opened", "openedCount": 0})

    def test_database_failure_propagates(self):
        with patch.object(handler, "connect", side_effect=RuntimeError("db unavailable")):
            with self.assertRaises(RuntimeError):
                handler.handler({}, None)


if __name__ == "__main__":
    unittest.main()
