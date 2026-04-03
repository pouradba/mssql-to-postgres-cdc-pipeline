-- ============================================
-- Logical Replication Publisher Setup
-- Run on: 10.200.30.30 (PostgreSQL Publisher)
-- ============================================

-- 1. Verify wal_level = logical
SHOW wal_level;  -- Must be 'logical'

-- 2. Create publications for MasterDB
\c MasterDB
CREATE PUBLICATION pub_masterdb FOR ALL TABLES;

-- Verify
SELECT pubname, puballtables FROM pg_publication;
SELECT * FROM pg_publication_tables WHERE pubname = 'pub_masterdb' ORDER BY schemaname, tablename;

-- 3. Create publications for LoginDB
\c LoginDB
CREATE PUBLICATION pub_logindb FOR ALL TABLES;

-- Verify
SELECT pubname, puballtables FROM pg_publication;
SELECT * FROM pg_publication_tables WHERE pubname = 'pub_logindb' ORDER BY schemaname, tablename;

-- 4. Verify replication slots (created automatically by subscribers)
SELECT slot_name, slot_type, active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal,
  wal_status
FROM pg_replication_slots
ORDER BY slot_name;
