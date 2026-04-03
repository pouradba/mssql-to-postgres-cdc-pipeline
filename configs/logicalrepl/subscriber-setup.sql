-- ============================================
-- Logical Replication Subscriber Setup
-- Run on: 10.200.32.71 (PostgreSQL Subscriber)
-- ============================================

-- 1. Subscribe to MasterDB
\c MasterDB
CREATE SUBSCRIPTION sub_masterdb_ysecit_dev
  CONNECTION 'host=10.200.30.30 port=5432 dbname=MasterDB user=devdbe password=CHANGE_ME'
  PUBLICATION pub_masterdb
  WITH (
    copy_data = true,
    create_slot = true,
    slot_name = 'sub_masterdb_ysecit_dev'
  );

-- 2. Subscribe to LoginDB
\c LoginDB
CREATE SUBSCRIPTION sub_logindb_ysecit_dev
  CONNECTION 'host=10.200.30.30 port=5432 dbname=LoginDB user=devdbe password=CHANGE_ME'
  PUBLICATION pub_logindb
  WITH (
    copy_data = true,
    create_slot = true,
    slot_name = 'sub_logindb_ysecit_dev'
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
