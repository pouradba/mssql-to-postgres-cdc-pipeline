-- ============================================
-- Logical Replication Publisher Setup
-- Run on: PG_HOST (PostgreSQL Publisher)
-- ============================================

-- 1. Verify wal_level = logical
SHOW wal_level;  -- Must be 'logical'

-- 2. Create publications for SourceDB_A
\c SourceDB_A
CREATE PUBLICATION pub_SourceDB_A FOR ALL TABLES;

-- Verify
SELECT pubname, puballtables FROM pg_publication;
SELECT * FROM pg_publication_tables WHERE pubname = 'pub_SourceDB_A' ORDER BY schemaname, tablename;

-- 3. Create publications for SourceDB_B
\c SourceDB_B
CREATE PUBLICATION pub_SourceDB_B FOR ALL TABLES;

-- Verify
SELECT pubname, puballtables FROM pg_publication;
SELECT * FROM pg_publication_tables WHERE pubname = 'pub_SourceDB_B' ORDER BY schemaname, tablename;

-- 4. Verify replication slots (created automatically by subscribers)
SELECT slot_name, slot_type, active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal,
  wal_status
FROM pg_replication_slots
ORDER BY slot_name;
