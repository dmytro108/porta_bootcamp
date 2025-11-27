#!/bin/bash
echo "=== Complete Metrics Report (Latest) ==="
cat /home/results/batch_delete_100_*_metrics.log 2>/dev/null | tail -50
