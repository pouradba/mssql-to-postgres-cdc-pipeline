# MSSQL to PostgreSQL CDC Pipeline
**End-to-end Change Data Capture pipeline from SQL Server to PostgreSQL using Debezium, Kafka (KRaft), and Logical Replication**
## Architecture
MSSQL Source (SQL Server 2019)
SourceDB_A + SourceDB_B (CDC enabled)
|
v
Debezium Connect (:8083)
source-connector-a, source-connector-b
|
v
Kafka KRaft (:9092)
No ZooKeeper, single-node
|
v
JDBC Sink Connectors
pg-sink-a, pg-sink-b
|
v
PostgreSQL Publisher (:5432)
SourceDB_A + SourceDB_B (PG copies)
|
v  (Logical Replication)
PostgreSQL Subscriber (:5432)
sub_sourcedb_a, sub_sourcedb_b
## Table Coverage
| Database | CDC Tables | Logical Replication | Total |
|----------|-----------|-------------------|-------|
| SourceDB_A | 17 | 26 | 43 |
| SourceDB_B | 21 | 37 | 58 |
| **Total** | **38** | **63** | **101** |
## Connectors (4/4 RUNNING)
| Connector | Type | Direction |
|-----------|------|-----------|
| source-connector-a | Debezium MSSQL Source | MSSQL -> Kafka |
| source-connector-b | Debezium MSSQL Source | MSSQL -> Kafka |
| pg-sink-a | JDBC Sink | Kafka -> PostgreSQL |
| pg-sink-b | JDBC Sink | Kafka -> PostgreSQL |
## Critical Configuration
### TCP Keepalive (Prevents Silent Failures)
This was discovered after a production incident where connections dropped silently. Default keepalive (2 hours) is too long.
**Linux (PostgreSQL / Kafka server):**
```bash
# /etc/sysctl.conf
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
sudo sysctl -p
```
**Windows (MSSQL server):**
```powershell
# Registry - requires reboot
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "KeepAliveTime" -Value 60000
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "KeepAliveInterval" -Value 10000
```
### Sink Connector: delete.enabled
```json
{
  "delete.enabled": "true",
  "pk.mode": "record_key",
  "pk.fields": "Id"
}
```
Without this, DELETE operations from MSSQL are **silently dropped** on the PostgreSQL side.
### Self-Healing Cron
```bash
# Restart failed connector tasks every 5 minutes
*/5 * * * * /opt/cdc/scripts/healthcheck/auto-restart.sh >> /var/log/cdc-restart.log 2>&1
```
## Project Structure
configs/
connectors/              # 4 Debezium connector JSON configs
masterdb-source-v2.json
logindb-source-v2.json
postgres-masterdb-sink.json
postgres-logindb-sink.json
logicalrepl/             # Publisher + Subscriber SQL setup
publisher-setup.sql
subscriber-setup.sql
docker-compose.yml       # Kafka KRaft + Debezium Connect
scripts/
healthcheck/
cdc-health-check.sh    # Full pipeline health (graded A+ to F)
auto-restart.sh        # Self-healing connector restart
monitoring/
debezium-metrics-push.py  # Jolokia JMX -> Prometheus Pushgateway
maintenance/
reset-connector.sh     # Delete + recreate connector
## Quick Start
### Prerequisites
- Docker and Docker Compose on the middleware server
- MSSQL with CDC enabled on source databases
- PostgreSQL 15+ with wal_level = logical on publisher
- Network connectivity between all hosts
### 1. Deploy Kafka + Debezium
```bash
cd configs && docker-compose up -d
```
### 2. Create Source Connectors
```bash
curl -X POST http://CONNECT_HOST:8083/connectors \
  -H "Content-Type: application/json" \
  -d @configs/connectors/masterdb-source-v2.json
```
### 3. Create Sink Connectors
```bash
curl -X POST http://CONNECT_HOST:8083/connectors \
  -H "Content-Type: application/json" \
  -d @configs/connectors/postgres-masterdb-sink.json
```
### 4. Set Up Logical Replication
```bash
psql -h PG_PUBLISHER -f configs/logicalrepl/publisher-setup.sql
psql -h PG_SUBSCRIBER -f configs/logicalrepl/subscriber-setup.sql
```
### 5. Verify
```bash
# Check all connectors
curl -s http://CONNECT_HOST:8083/connectors?expand=status | python3 -m json.tool
# Check logical replication on subscriber
psql -h PG_SUBSCRIBER -c "SELECT subname, subenabled, received_lsn FROM pg_stat_subscription;"
```
## Monitoring
| Tool | Purpose |
|------|---------|
| **Grafana** | CDC Pipeline Monitor v5 + Logical Replication Monitor v4 |
| **Jolokia** | Debezium JMX MBeans (port 8778) for real-time lag |
| **Prometheus** | Metrics collection via Pushgateway |
| **Health Check** | cdc-health-check.sh with A+ to F grading |
## Troubleshooting
### Connector Task Failed
```bash
# Check status
curl -s http://CONNECT_HOST:8083/connectors/CONNECTOR_NAME/status | jq .
# Restart failed task
curl -X POST http://CONNECT_HOST:8083/connectors/CONNECTOR_NAME/tasks/0/restart
# Nuclear option: delete and recreate
./scripts/maintenance/reset-connector.sh CONNECTOR_NAME
```
### Logical Replication Lag
```sql
-- On publisher
SELECT slot_name, active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;
-- On subscriber
SELECT subname, received_lsn,
  (EXTRACT(EPOCH FROM now() - last_msg_receipt_time))::int AS lag_seconds
FROM pg_stat_subscription;
```
### Silent Connection Drops
If connectors show RUNNING but data stops flowing, check TCP keepalive. This was the number one production incident - connections to MSSQL dropped silently after network hiccups.
## Lessons Learned
1. **TCP keepalive = 60s** is critical - default (2 hours) causes silent connection failures
2. **delete.enabled=true** must be set on sink connectors - DELETEs are dropped by default
3. **snapshot.mode=recovery** after initial load - prevents full re-snapshot on restart
4. **Self-healing cron** every 5 minutes catches transient failures before they become incidents
5. **Monitor Jolokia MBeans** for real Debezium lag - Kafka consumer lag alone is insufficient
6. **Never test INSERT/DELETE** on tables with active publication subscribers
## Author
**PouraDBA** (Vijayakumar Poura) - Database Reliability Engineer | AMVANA Software India Pvt. Ltd. 
## License
MIT
