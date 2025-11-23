# Quick Reference: Using Refactored DB Cleanup Scripts

## For End Users (No Changes Required!)

### Basic Usage (Same as Before)
```bash
# Test metrics collection
./db-cleanup.sh --test-metrics

# Run cleanup methods
./db-cleanup.sh --method partition_drop
./db-cleanup.sh --method truncate
./db-cleanup.sh --method copy --retention-days 7
./db-cleanup.sh --method batch_delete --batch-size 10000

# Run all methods
./db-cleanup.sh --method all

# Get help
./db-cleanup.sh --help
```

## For Developers (New Capabilities!)

### Using Individual Modules

#### 1. Using Only Helpers
```bash
#!/bin/bash
source lib/helpers.sh

log "Starting my script"
row_count=$(get_row_count "mydb" "mytable")
log "Table has $row_count rows"
```

#### 2. Using Helpers + Metrics
```bash
#!/bin/bash
source lib/helpers.sh
source lib/metrics.sh

# Capture metrics snapshot
snapshot=$(capture_metrics_snapshot "before" "mytable")
echo "$snapshot"

# Get specific metrics
lag=$(get_replication_lag)
binlog_size=$(get_binlog_size)
log "Replication lag: ${lag}s, Binlog size: ${binlog_size} bytes"
```

#### 3. Using Full Stack
```bash
#!/bin/bash
source lib/helpers.sh
source lib/metrics.sh
source lib/cleanup-methods.sh

# Use any cleanup method programmatically
DATABASE="my_database"
RESULTS_DIR="./my_results"

run_partition_drop_cleanup "events_table" 30
```

### Creating Custom Cleanup Scripts

```bash
#!/bin/bash
set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/metrics.sh"

# Configuration
DATABASE="production"
TABLE="user_events"

# Custom cleanup logic with metrics
log "Starting custom cleanup for $TABLE"

snapshot_before=$(capture_metrics_snapshot "before" "$TABLE")
start_time=$(get_timestamp)

# Your custom cleanup SQL
mysql_query "DELETE FROM $DATABASE.$TABLE WHERE created_at < DATE_SUB(NOW(), INTERVAL 90 DAY)"

end_time=$(get_timestamp)
snapshot_after=$(capture_metrics_snapshot "after" "$TABLE")

# Log results
duration=$(calculate_duration "$start_time" "$end_time")
log_metrics "custom_cleanup" "$TABLE" "$snapshot_before" "$snapshot_after" "$duration"

log "Cleanup complete in ${duration}s"
```

## Module Dependencies

```
helpers.sh          ← Base module (no dependencies)
    ↓
metrics.sh          ← Depends on helpers.sh
    ↓
cleanup-methods.sh  ← Depends on helpers.sh + metrics.sh
    ↓
db-cleanup.sh       ← Main orchestrator (uses all)
```

**Important:** Always source in this order:
1. helpers.sh (first)
2. metrics.sh (second)
3. cleanup-methods.sh (third)

## Environment Variables Reference

### Required for All Scripts
```bash
export MYSQL_USER="root"
export MYSQL_PASSWORD="your_password"
export MYSQL_HOST="localhost"
export DATABASE="cleanup_bench"
export RESULTS_DIR="./results"
```

### Optional
```bash
export MYSQL_PORT="3306"                    # Default: 3306
export MYSQL_REPLICA_HOST="replica_host"   # For replication metrics
export VERBOSE="true"                       # Enable verbose logging
```

## Common Patterns

### Pattern 1: Measure Any Operation
```bash
source lib/helpers.sh
source lib/metrics.sh

# Before
snapshot_before=$(capture_metrics_snapshot "before" "mytable")
start_ts=$(get_timestamp)

# Your operation here
mysql_query "ALTER TABLE mytable ADD INDEX idx_created (created_at)"

# After
end_ts=$(get_timestamp)
snapshot_after=$(capture_metrics_snapshot "after" "mytable")
duration=$(calculate_duration "$start_ts" "$end_ts")

# Report
log_metrics "add_index" "mytable" "$snapshot_before" "$snapshot_after" "$duration"
```

### Pattern 2: Check Replication Status
```bash
source lib/helpers.sh
source lib/metrics.sh

lag=$(get_replication_lag)
if [[ $lag -gt 60 ]]; then
    log_error "Replication lag too high: ${lag}s"
    exit 1
fi

log "Replication lag OK: ${lag}s"
```

### Pattern 3: Custom Batch Processing
```bash
source lib/helpers.sh
source lib/metrics.sh

batch_size=1000
total=0

while true; do
    start_ts=$(get_timestamp)
    
    mysql_query "DELETE FROM mytable WHERE status='archived' LIMIT $batch_size"
    rows=$(mysql_query "SELECT ROW_COUNT()")
    
    [[ $rows -eq 0 ]] && break
    
    total=$((total + rows))
    duration=$(calculate_duration "$start_ts" "$(get_timestamp)")
    
    log "Batch: deleted $rows rows in ${duration}s (total: $total)"
    sleep 0.1
done

log "Completed: $total rows deleted"
```

## Troubleshooting

### Issue: "helpers.sh not found"
```bash
# Fix: Use absolute path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/helpers.sh"
```

### Issue: Function not found
```bash
# Check: Are all dependencies sourced?
source lib/helpers.sh      # Required first
source lib/metrics.sh      # Required for metrics
source lib/cleanup-methods.sh  # Required for cleanup
```

### Issue: MySQL connection failed
```bash
# Check: Environment variables set?
echo $MYSQL_USER
echo $MYSQL_PASSWORD
echo $MYSQL_HOST

# Test connection manually
mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1"
```

## Best Practices

1. **Always use `set -euo pipefail`** at script start
2. **Source helpers.sh first** before other modules
3. **Set SCRIPT_DIR** for reliable paths
4. **Use `log()` functions** instead of echo
5. **Check return codes** from cleanup functions
6. **Create RESULTS_DIR** before logging metrics
7. **Export required variables** before sourcing modules

## Testing Your Custom Scripts

```bash
# Syntax check
bash -n my_custom_script.sh

# Dry run with verbose logging
VERBOSE=true ./my_custom_script.sh

# Check generated metrics
ls -lh results/
cat results/latest_metrics.log
```

## Examples in the Wild

Check existing scripts for reference:
- `db-cleanup.sh` - Main orchestrator example
- `db-load.sh` - Uses helpers for logging
- `db-traffic.sh` - Could be enhanced with metrics

## Getting Help

```bash
# Built-in help
./db-cleanup.sh --help

# Module documentation
cat lib/README.md

# Function reference
grep "^[a-z_]*() {" lib/helpers.sh
grep "^[a-z_]*() {" lib/metrics.sh
grep "^[a-z_]*() {" lib/cleanup-methods.sh
```
