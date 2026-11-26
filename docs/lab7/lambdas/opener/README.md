# Opener

Python Lambda `handler.handler`, invoked by a schedule; the incoming event is
ignored. A single PostgreSQL transaction opens all due, still-unopened capsules
using UTC and inserts the existing PHP-format opening notification for each.
Returning normally means the DB transaction committed. Failures propagate so
the scheduler/Lambda can retry. The operation is repeatable, including concurrent
opener invocations, because the update only affects unopened rows.

The return value is `{"eventType":"capsules.opened","openedCount":N}` when
N > 0, otherwise `{"eventType":"capsules.none_opened","openedCount":0}`.
With an **asynchronous Lambda on-success destination** set to SNS, Lambda wraps
this under `responsePayload`. For an SNS subscription using
`FilterPolicyScope=MessageBody`, use:

```json
{"responsePayload":{"eventType":["capsules.opened"]}}
```

The function does not publish directly to SNS; scheduled invocation must be
asynchronous and the destination, its permissions and the subscription filter
must be configured separately. This notification is per invocation, not per
capsule. A commit followed by a lost invocation result may leave no matching SNS
event on retry; an outbox is needed for guaranteed publication.

Database environment variables, verified TLS, deployment dependencies and CA
requirements are identical to `../mailer/README.md`. The updated PHP request
handler no longer invokes the legacy opening path.

Run unit tests locally with `python3 -m unittest -v test_handler.py` from this
directory. They use mocks, not PostgreSQL. Large backlogs are processed in one
transaction; size Lambda timeout/resources accordingly or add batching.
