# DB Cleanup Library Modules

This directory contains modular Bash libraries used by the MySQL Cleanup Benchmark system.

## File Structure

```
lib/
├── helpers.sh          - Core utility functions
├── metrics.sh          - Metrics collection and analysis
├── cleanup-methods.sh  - Cleanup method implementations
└── README.md          - This file
```

## Module Descriptions

### helpers.sh
Core utility functions used across the entire system:

**Functions:**
- `log()` - Standard logging with timestamp
- `log_verbose()` - Verbose logging (only when VERBOSE=true)
- `log_error()` - Error logging to stderr
- `get_timestamp()` - Get nanosecond-precision timestamp
- `calculate_duration()` - Calculate duration between timestamps
- `mysql_query()` - Execute MySQL queries
- `get_status_var()` - Get MySQL status variables
- `get_innodb_metric()` - Get InnoDB metrics from information_schema
- `get_row_count()` - Count rows in a table
- `get_table_info()` - Get table size and metadata
- `load_environment()` - Load environment variables from .env files

**Dependencies:** None (base module)

**Usage:**
```bash
source lib/helpers.sh
log "Starting operation..."
timestamp=$(get_timestamp)
```

### metrics.sh
Comprehensive metrics collection and analysis:

**Function Categories:**
1. **InnoDB Metrics**
   - `get_history_list_length()` - Purge lag indicator
   - `get_lock_metrics()` - Lock wait statistics
   - `get_innodb_row_operations()` - Row-level operation counters

2. **Replication Metrics**
   - `get_replication_lag()` - Replica lag in seconds
   - `get_replication_status()` - Full replication status

3. **Binary Log Metrics**
   - `get_binlog_list()` - List of binary logs
   - `get_binlog_size()` - Total binlog size
   - `get_active_binlog()` - Current active binlog

4. **Query Latency**
   - `measure_query_latency()` - Single query execution time
   - `measure_latency_batch()` - Multiple runs with statistics
   - `measure_latency_baseline()` - Baseline SELECT/UPDATE latency

5. **Snapshot System**
   - `capture_metrics_snapshot()` - Comprehensive metrics snapshot
   - `parse_snapshot()` - Extract values from snapshot
   - `calculate_metrics_diff()` - Calculate delta between snapshots

6. **Metrics Logging**
   - `log_metrics()` - Write comprehensive metrics report
   - `analyze_batch_metrics()` - Analyze batch DELETE metrics

**Dependencies:** helpers.sh

**Usage:**
```bash
source lib/helpers.sh
source lib/metrics.sh

snapshot_before=$(capture_metrics_snapshot "before" "my_table")
# ... perform operation ...
snapshot_after=$(capture_metrics_snapshot "after" "my_table")
log_metrics "operation_name" "my_table" "$snapshot_before" "$snapshot_after" "$duration"
```

### cleanup-methods.sh
Implementation of all four cleanup methods:

**Cleanup Methods:**

1. **TRUNCATE TABLE** (`run_truncate_cleanup`)
   - Fastest but removes ALL data (not selective)
   - Use for temporary tables only

2. **DROP PARTITION** (`run_partition_drop_cleanup`)
   - Fast selective cleanup for partitioned tables
   - Requires table partitioning by date

3. **Copy-to-New-Table** (`run_copy_cleanup`)
   - Fast but data written during operation is LOST
   - Creates new table, copies recent data, swaps tables

4. **Batch DELETE** (`run_batch_delete_cleanup`)
   - Slowest but table stays online
   - Deletes in small batches with configurable delays
   - Space not freed until OPTIMIZE TABLE

**Helper Functions:**
- `identify_old_partitions()` - Find partitions to drop
- `execute_*_cleanup()` - Core implementation (no metrics)
- `run_*_cleanup()` - Wrapper with metrics collection
- `run_all_methods()` - Run all methods sequentially

**Dependencies:** helpers.sh, metrics.sh

**Usage:**
```bash
source lib/helpers.sh
source lib/metrics.sh
source lib/cleanup-methods.sh

# Run partition drop cleanup
run_partition_drop_cleanup "cleanup_partitioned" 10

# Run batch delete with custom parameters
run_batch_delete_cleanup "cleanup_batch" 10 5000 0.1
```

## Environment Variables

All modules respect these environment variables:

### Required
- `DATABASE` - Database name (default: cleanup_bench)
- `RESULTS_DIR` - Directory for metrics logs
- `MYSQL_HOST` - MySQL server host
- `MYSQL_USER` - MySQL username
- `MYSQL_PASSWORD` - MySQL password

### Optional
- `VERBOSE` - Enable verbose logging (true/false)
- `MYSQL_PORT` - MySQL port (default: 3306)
- `MYSQL_REPLICA_HOST` - Replica host for replication metrics
- `MYSQL_REPLICA_PORT` - Replica port

## Integration Example

The main `db-cleanup.sh` script sources all modules:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Load modules in order
source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/metrics.sh"
source "${LIB_DIR}/cleanup-methods.sh"

# Now all functions are available
run_partition_drop_cleanup "cleanup_partitioned" 10
```

## Error Handling

All modules follow these conventions:
- Return 0 on success, non-zero on failure
- Log errors to stderr using `log_error()`
- Use `set -euo pipefail` for strict error handling
- Clean up temporary resources on failure

## Testing

Each module can be tested independently:

```bash
# Test helpers
source lib/helpers.sh
VERBOSE=true
log "Testing log function"
log_verbose "This appears only in verbose mode"

# Test metrics
source lib/helpers.sh
source lib/metrics.sh
snapshot=$(capture_metrics_snapshot "test" "cleanup_batch")
echo "$snapshot"

# Test cleanup methods (requires database)
source lib/helpers.sh
source lib/metrics.sh
source lib/cleanup-methods.sh
execute_truncate_cleanup "test_table"
```

## Performance Notes

- All modules are designed for minimal overhead
- MySQL queries use `--skip-column-names --batch` for efficiency
- Timestamp functions use nanosecond precision
- Metrics collection adds ~1-2 seconds overhead per operation

## Maintenance

When modifying these modules:
1. Maintain backward compatibility with function signatures
2. Update this README with any new functions
3. Test with `bash -n scriptname.sh` for syntax errors
4. Verify integration with main script
5. Document any new environment variables
