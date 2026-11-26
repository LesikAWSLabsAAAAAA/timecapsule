"""Scheduled atomic opening of due TimeCapsule capsules."""
import os


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


def handler(event, context):
    # UPDATE and notification insertion commit together. PostgreSQL rechecks
    # opened_at after waiting for concurrent updates.
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                WITH opened AS (
                    UPDATE capsules c
                       SET opened_at = (NOW() AT TIME ZONE 'UTC')
                      FROM users u
                     WHERE u.id = c.user_id AND c.opened_at IS NULL
                       AND c.open_at <= (NOW() AT TIME ZONE 'UTC')
                    RETURNING c.id, c.user_id, c.title, c.recipient_email, u.email
                ), inserted AS (
                    INSERT INTO notifications (capsule_id, user_id, recipient, message)
                    SELECT id, user_id, COALESCE(recipient_email, email),
                           'Your capsule "' || title || '" is now open.'
                      FROM opened
                    RETURNING id
                )
                SELECT count(*) FROM inserted
                """
            )
            count = cur.fetchone()[0]
    return {
        "eventType": "capsules.opened" if count else "capsules.none_opened",
        "openedCount": count,
    }
