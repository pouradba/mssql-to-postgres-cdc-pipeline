-- ============================================
-- Logical Replication Subscriber Setup
-- Run on: PG_HOST (PostgreSQL Subscriber)
-- ============================================

-- 1. Subscribe to SourceDB_A
\c SourceDB_A
CREATE SUBSCRIPTION sub_SourceDB_A_ysecit_dev
  CONNECTION 'host=PG_HOST port=5432 dbname=SourceDB_A user=devdbe password=CHANGE_ME'
  PUBLICATION pub_SourceDB_A
  WITH (
    copy_data = true,
    create_slot = true,
    slot_name = 'sub_SourceDB_A_ysecit_dev'
  );

-- 2. Subscribe to SourceDB_B
\c SourceDB_B
CREATE SUBSCRIPTION sub_SourceDB_B_ysecit_dev
  CONNECTION 'host=PG_HOST port=5432 dbname=SourceDB_B user=devdbe password=CHANGE_ME'
  PUBLICATION pub_SourceDB_B
  WITH (
    copy_data = true,
    create_slot = true,
    slot_name = 'sub_SourceDB_B_ysecit_dev'
  );

-- 3. Verify subscriptions
SELECT subname, subenabled, subslotname, subpublications FROM pg_subscription;

-- 4. Check subscription activity
SELECT subname, received_lsn, latest_end_lsn,
  (EXTRACT(EPOCH FROM now() - last_msg_receipt_time))::int AS lag_seconds
FROM pg_stat_subscription
WHERE subname IS NOT NULL;

-- 5. Monitor for errors
SELECT subname, last_error_count, last_error_message
FROM pg_stat_subscription_stats
WHERE last_error_count > 0;
