#!/usr/bin/env python3
"""
Push Debezium JMX metrics (via Jolokia) to Prometheus Pushgateway.
Cron: * * * * * /opt/cdc/scripts/monitoring/debezium-metrics-push.py

Requires: pip install requests
"""
import requests
import time
import sys

JOLOKIA_URL = "http://10.200.32.11:8778/jolokia"
PUSHGATEWAY_URL = "http://10.200.30.44:9091"
JOB_NAME = "debezium_cdc"

CONNECTORS = [
    {"name": "SourceDB_A-source-v2", "type": "source", "server": "SourceDB_A"},
    {"name": "SourceDB_B-source-v2", "type": "source", "server": "SourceDB_B"},
]

def get_jolokia_metric(connector_name, mbean_type="streaming"):
    """Fetch Debezium MBean metrics via Jolokia."""
    url = f"{JOLOKIA_URL}/read/debezium.sql_server:type=connector-metrics,context={mbean_type},server={connector_name}"
    try:
        r = requests.get(url, timeout=5)
        if r.status_code == 200:
            return r.json().get("value", {})
    except Exception as e:
        print(f"Error fetching {connector_name}: {e}", file=sys.stderr)
    return {}

def push_metrics(metrics_text):
    """Push metrics to Prometheus Pushgateway."""
    try:
        r = requests.post(
            f"{PUSHGATEWAY_URL}/metrics/job/{JOB_NAME}",
            data=metrics_text,
            headers={"Content-Type": "text/plain"}
        )
        return r.status_code == 200
    except Exception as e:
        print(f"Push failed: {e}", file=sys.stderr)
        return False

def main():
    lines = []
    timestamp = int(time.time() * 1000)

    for conn in CONNECTORS:
        metrics = get_jolokia_metric(conn["name"])
        if not metrics:
            continue

        labels = f'connector="{conn["name"]}",server="{conn["server"]}"'

        # Key Debezium metrics
        metric_map = {
            "debezium_milliseconds_since_last_event": "MilliSecondsSinceLastEvent",
            "debezium_total_number_of_events_seen": "TotalNumberOfEventsSeen",
            "debezium_number_of_committed_transactions": "NumberOfCommittedTransactions",
            "debezium_last_transaction_id": "LastTransactionId",
            "debezium_queue_total_capacity": "QueueTotalCapacity",
            "debezium_queue_remaining_capacity": "QueueRemainingCapacity",
            "debezium_connected": "Connected",
        }

        for prom_name, jolokia_key in metric_map.items():
            value = metrics.get(jolokia_key)
            if value is not None:
                try:
                    lines.append(f"{prom_name}{{{labels}}} {float(value)}")
                except (ValueError, TypeError):
                    pass

    if lines:
        push_metrics("\n".join(lines) + "\n")
        print(f"Pushed {len(lines)} metrics")
    else:
        print("No metrics collected")

if __name__ == "__main__":
    main()
