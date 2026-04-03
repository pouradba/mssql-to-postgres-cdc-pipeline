#!/bin/bash
# Reset a Debezium connector (delete + recreate)
# Usage: ./reset-connector.sh <connector-name>

CONNECT_URL="http://10.200.32.11:8083"
CONNECTOR=$1
CONFIG_DIR="$(dirname "$0")/../../configs/connectors"

if [ -z "$CONNECTOR" ]; then
  echo "Usage: $0 <connector-name>"
  echo "Available connectors:"
  curl -sf "${CONNECT_URL}/connectors" 2>/dev/null | python3 -m json.tool
  exit 1
fi

echo "=== Resetting connector: ${CONNECTOR} ==="

# 1. Delete connector
echo "[1/3] Deleting connector..."
curl -sf -X DELETE "${CONNECT_URL}/connectors/${CONNECTOR}"
echo ""
sleep 2

# 2. Find config file
CONFIG_FILE="${CONFIG_DIR}/${CONNECTOR}.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[ERROR] Config file not found: ${CONFIG_FILE}"
  echo "Available configs:"
  ls -1 "${CONFIG_DIR}/"
  exit 1
fi

# 3. Recreate connector
echo "[2/3] Creating connector from ${CONFIG_FILE}..."
curl -sf -X POST "${CONNECT_URL}/connectors" \
  -H "Content-Type: application/json" \
  -d @"${CONFIG_FILE}"
echo ""
sleep 3

# 4. Verify
echo "[3/3] Verifying..."
curl -sf "${CONNECT_URL}/connectors/${CONNECTOR}/status" | python3 -m json.tool
echo ""
echo "=== Done ==="
