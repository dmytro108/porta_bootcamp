#!/bin/bash
echo "=== Latest Metrics Log ==="
cat /home/results/batch_delete_1000_*_metrics.log 2>/dev/null | head -60 || echo "No metrics file found"

echo -e "\n=== Latest Batch CSV (first 10 rows) ==="
head -11 /home/results/batch_delete_1000_*_batches.csv 2>/dev/null | tail -10 || echo "No batch CSV found"
