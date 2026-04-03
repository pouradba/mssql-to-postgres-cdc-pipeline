#!/bin/bash
# CDC Pipeline Health Check
# Run: ./cdc-health-check.sh
# Cron: */10 * * * * /opt/cdc/scripts/healthcheck/cdc-health-check.sh

CONNECT_URL="http://10.200.32.11:8083"
PG_PUB="10.200.30.30"
PG_SUB="10.200.32.71"
SCORE=0
MAX_SCORE=0

echo "╔══════════════════════════════════════════╗"
echo "║   CDC Pipeline Health Check              ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 1. Check Kafka broker
MAX_SCORE=$((MAX_SCORE + 10))
if curl -sf http://10.200.32.11:9092 > /dev/null 2>&1 || docker exec kafka-kraft kafka-broker-api-versions.sh --bootstrap-server localhost:9092 > /dev/null 2>&1; then
  echo "[OK] Kafka broker: RUNNING"
  SCORE=$((SCORE + 10))
else
  echo "[FAIL] Kafka broker: NOT REACHABLE"
fi

# 2. Check Debezium Connect
MAX_SCORE=$((MAX_SCORE + 10))
CONNECT_STATUS=$(curl -sf "${CONNECT_URL}/" 2>/dev/null)
if [ $? -eq 0 ]; then
  echo "[OK] Debezium Connect: RUNNING"
  SCORE=$((SCORE + 10))
else
  echo "[FAIL] Debezium Connect: NOT REACHABLE"
fi

# 3. Check each connector
for CONNECTOR in masterdb-source-v2 logindb-source-v2 postgres-masterdb-sink postgres-logindb-sink; do
  MAX_SCORE=$((MAX_SCORE + 10))
  STATUS=$(curl -sf "${CONNECT_URL}/connectors/${CONNECTOR}/status" 2>/dev/null)
  if [ $? -eq 0 ]; then
    STATE=$(echo "$STATUS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['connector']['state'])" 2>/dev/null)
    FAILED=$(echo "$STATUS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(1 for t in d.get('tasks',[]) if t['state']!='RUNNING'))" 2>/dev/null)
    if [ "$STATE" = "RUNNING" ] && [ "$FAILED" = "0" ]; then
      echo "[OK] ${CONNECTOR}: RUNNING (0 tasks failed)"
      SCORE=$((SCORE + 10))
    else
      echo "[WARN] ${CONNECTOR}: ${STATE} (${FAILED} tasks failed)"
      SCORE=$((SCORE + 5))
      # Auto-restart failed tasks
      echo "       Attempting restart..."
      curl -sf -X POST "${CONNECT_URL}/connectors/${CONNECTOR}/tasks/0/restart" > /dev/null 2>&1
    fi
  else
    echo "[FAIL] ${CONNECTOR}: NOT FOUND"
  fi
done

# 4. Check logical replication slots on publisher
MAX_SCORE=$((MAX_SCORE + 10))
INACTIVE_SLOTS=$(PGPASSWORD="${PG_PASSWORD:-DBYsec@2024}" psql -h "$PG_PUB" -U postgres -t -c "SELECT count(*) FROM pg_replication_slots WHERE NOT active" 2>/dev/null | tr -d ' ')
if [ "${INACTIVE_SLOTS:-0}" = "0" ]; then
  echo "[OK] Logical replication slots: all active"
  SCORE=$((SCORE + 10))
else
  echo "[WARN] Logical replication slots: ${INACTIVE_SLOTS} inactive"
  SCORE=$((SCORE + 5))
fi

# 5. Check subscriber lag
MAX_SCORE=$((MAX_SCORE + 10))
SUB_LAG=$(PGPASSWORD="${PG_PASSWORD:-DBYsec@2024}" psql -h "$PG_SUB" -U postgres -t -c "SELECT COALESCE(max((EXTRACT(EPOCH FROM now() - last_msg_receipt_time))::int), 0) FROM pg_stat_subscription WHERE subname IS NOT NULL" 2>/dev/null | tr -d ' ')
if [ "${SUB_LAG:-999}" -lt 30 ]; then
  echo "[OK] Subscription lag: ${SUB_LAG}s"
  SCORE=$((SCORE + 10))
elif [ "${SUB_LAG:-999}" -lt 120 ]; then
  echo "[WARN] Subscription lag: ${SUB_LAG}s"
  SCORE=$((SCORE + 5))
else
  echo "[FAIL] Subscription lag: ${SUB_LAG}s"
fi

# Grade
echo ""
PCT=$((SCORE * 100 / MAX_SCORE))
if [ $PCT -ge 95 ]; then GRADE="A+";
elif [ $PCT -ge 85 ]; then GRADE="A";
elif [ $PCT -ge 70 ]; then GRADE="B";
elif [ $PCT -ge 50 ]; then GRADE="C";
else GRADE="F"; fi

echo "Score: ${SCORE}/${MAX_SCORE} (${PCT}%)"
echo "Grade: ${GRADE}"
echo ""
