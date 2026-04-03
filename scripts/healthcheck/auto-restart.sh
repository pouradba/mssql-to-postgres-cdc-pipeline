#!/bin/bash
# Self-Healing: Auto-restart failed Debezium connector tasks
# Cron: */5 * * * * /opt/cdc/scripts/healthcheck/auto-restart.sh >> /var/log/cdc-restart.log 2>&1

CONNECT_URL="http://10.200.32.11:8083"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

for CONNECTOR in $(curl -sf "${CONNECT_URL}/connectors" 2>/dev/null | python3 -c "import sys,json; [print(c) for c in json.load(sys.stdin)]" 2>/dev/null); do
  STATUS=$(curl -sf "${CONNECT_URL}/connectors/${CONNECTOR}/status" 2>/dev/null)
  if [ $? -ne 0 ]; then continue; fi

  # Check connector state
  CONN_STATE=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin)['connector']['state'])" 2>/dev/null)

  # Check each task
  TASKS=$(echo "$STATUS" | python3 -c "
import sys,json
d = json.load(sys.stdin)
for t in d.get('tasks', []):
    if t['state'] != 'RUNNING':
        print(f\"{t['id']}:{t['state']}\")
" 2>/dev/null)

  if [ -n "$TASKS" ]; then
    for TASK_INFO in $TASKS; do
      TASK_ID=$(echo "$TASK_INFO" | cut -d: -f1)
      TASK_STATE=$(echo "$TASK_INFO" | cut -d: -f2)
      echo "[${TIMESTAMP}] RESTART: ${CONNECTOR}/tasks/${TASK_ID} (was: ${TASK_STATE})"
      curl -sf -X POST "${CONNECT_URL}/connectors/${CONNECTOR}/tasks/${TASK_ID}/restart" > /dev/null 2>&1
    done
  fi

  # Restart entire connector if PAUSED or FAILED
  if [ "$CONN_STATE" = "FAILED" ]; then
    echo "[${TIMESTAMP}] RESTART CONNECTOR: ${CONNECTOR} (was: FAILED)"
    curl -sf -X POST "${CONNECT_URL}/connectors/${CONNECTOR}/restart" > /dev/null 2>&1
  fi
done
