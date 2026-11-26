-- Run before enabling the consumer. Existing duplicates must be resolved manually.
-- This predicate matches the existing PHP sealing notification format.
CREATE UNIQUE INDEX IF NOT EXISTS notifications_one_sealed_per_capsule_idx
    ON notifications (capsule_id)
    WHERE message LIKE 'Capsule "%" was sealed for you until %.';
