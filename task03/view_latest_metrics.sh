#!/bin/bash
echo "=== Latest Metrics Log - Replication Section ==="
grep -A5 "Replication Metrics" /home/results/batch_delete_100_*_metrics.log 2>/dev/null | tail -10
