# Mailer

Python Lambda `handler.handler`. SQS event-source mapping receives **raw** SNS
delivery: each `Records[].body` is JSON `{"eventType":"capsule.sealed","capsuleId":123}`;
`capsuleId` is a positive PostgreSQL integer. The PHP producer publishes this
contract. Extra properties are ignored.
Message IDs come from `Records[].messageId`. Invalid messages and DB errors are
returned in `batchItemFailures`; enable `ReportBatchItemFailures` on the mapping,
configure redrive/DLQ and size the visibility timeout for retries and the whole batch.
Use batch size 1 for FIFO queues; larger FIFO batches require stop-on-first-failure
handling not implemented here.

The message is a simulated email: after `MAIL_DELAY_SECONDS` (default 3), insert
the same notification as PHP, taking owner, title, recipient and opening time
from the database. A deleted/missing capsule is acknowledged without insertion.
No real email is sent. The unique partial index in `001_sealed_unique.sql` must
be installed on the existing schema **before** switching traffic to the worker.
It also prevents duplicate legacy PHP sealed notifications; check and resolve
existing duplicates first. Do not run the legacy synchronous sender in parallel
with this worker: PHP does not handle unique violations. The index recognizes
notification type by the legacy message text; changing that format requires a
schema/contract migration. Delay happens on retries too.

Set `DB_HOST`, `DB_USER`, `DB_PASSWORD`; optionally `DB_PORT` (5432), `DB_NAME`
(timecapsule), `DB_SSLMODE` (`verify-full`, default, or `verify-ca`), and
`DB_SSLROOTCERT` (path to trusted CA bundle). `verify-full` requires a hostname
matching the DB certificate. Provision CA and credentials securely outside this
repository; network access to PostgreSQL is required. Package `requirements.txt`
for the target Lambda Python runtime and CPU architecture; no AWS SDK needed.
Run unit tests locally with `python3 -m unittest -v test_handler.py` from this
directory. The tests use mocks, not a PostgreSQL server.
