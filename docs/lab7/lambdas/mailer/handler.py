"""SQS raw-delivery consumer for simulated sealed-capsule emails."""
import json
import logging
import math
import os
import time

LOG = logging.getLogger(__name__)


def connect():
    import psycopg

    options = {
        "host": os.environ["DB_HOST"],
        "port": os.getenv("DB_PORT", "5432"),
        "dbname": os.getenv("DB_NAME", "timecapsule"),
        "user": os.environ["DB_USER"],
        "password": os.environ["DB_PASSWORD"],
        "sslmode": os.getenv("DB_SSLMODE", "verify-full"),
        "connect_timeout": 5,
    }
    if options["sslmode"] not in ("verify-full", "verify-ca"):
        raise ValueError("DB_SSLMODE must verify the PostgreSQL certificate")
    if os.getenv("DB_SSLROOTCERT"):
        options["sslrootcert"] = os.environ["DB_SSLROOTCERT"]
    return psycopg.connect(**options)


def process(record):
    body = json.loads(record["body"])
    if not isinstance(body, dict) or body.get("eventType") != "capsule.sealed":
        raise ValueError("Expected raw capsule.sealed event")
    capsule_id = body.get("capsuleId")
    if type(capsule_id) is not int or not 0 < capsule_id <= 2147483647:
        raise ValueError("capsuleId must be a positive PostgreSQL integer")
    delay = float(os.getenv("MAIL_DELAY_SECONDS", "3"))
    if not math.isfinite(delay) or delay < 0:
        raise ValueError("MAIL_DELAY_SECONDS must be finite and non-negative")
    time.sleep(delay)
    # Source fields come from the DB, not from untrusted/stale event payloads.
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO notifications (capsule_id, user_id, recipient, message)
                SELECT c.id, c.user_id, COALESCE(c.recipient_email, u.email),
                       'Capsule "' || c.title || '" was sealed for you until ' ||
                       to_char(c.open_at, 'FMDD Mon YYYY, HH24:MI') || ' UTC.'
                  FROM capsules c JOIN users u ON u.id = c.user_id
                 WHERE c.id = %s
                ON CONFLICT (capsule_id)
                  WHERE message LIKE 'Capsule "%%" was sealed for you until %%.'
                DO NOTHING
                """,
                (capsule_id,),
            )


def handler(event, context):
    failures = []
    for record in event["Records"]:
        try:
            process(record)
        except Exception:
            LOG.exception("Failed to process SQS message")
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
