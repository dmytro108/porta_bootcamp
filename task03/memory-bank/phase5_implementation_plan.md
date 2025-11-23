# Phase 5 Implementation Plan: Cleanup Methods

**Status**: Ready for Implementation  
**Dependencies**: Phase 1 ✅, Phase 2 ✅, Phase 3 ✅, Phase 4 ✅  
**Enables**: Phase 6 (Orchestration), Results Analysis  
**Estimated Effort**: 12-16 hours  
**Target Completion**: November 21-22, 2025  

---

## Phase 5 Overview

Phase 5 implements the four cleanup methods that are the core of this benchmark project. Each method will be integrated with the Phase 4 metrics framework to enable objective performance comparison.

### The Four Methods

1. **DROP PARTITION** - Fast partition-level removal (DDL)
2. **TRUNCATE TABLE** - Fast full-table truncation (DDL)
3. **Copy-to-New-Table** - CREATE + INSERT + RENAME + DROP pattern (DDL + DML)
4. **Batch DELETE** - Incremental DELETE with LIMIT (DML)

### Success Criteria

Phase 5 is complete when:
- All four cleanup methods implemented and tested
- Each method integrated with Phase 4 metrics collection
- Results logged to `task03/results/` directory
- Each method can clean data older than 10 days
- Methods run successfully with concurrent `db-traffic.sh` load
- Documentation updated with usage examples
- Ready for Phase 6 orchestration and comparison

---

## Implementation Strategy

### Approach

**Incremental Development**: Implement and test each method individually before moving to the next.

**Pattern**:
```bash
1. Implement cleanup logic for method
2. Integrate with metrics framework
3. Test without concurrent load
4. Test with db-traffic.sh running
5. Validate results and metrics log
6. Document method-specific notes
7. Move to next method
```

### Order of Implementation

**Recommended sequence** (simplest to most complex):

1. **TRUNCATE TABLE** - Simplest, single SQL statement
2. **DROP PARTITION** - Single DDL, but requires partition identification
3. **Copy-to-New-Table** - Multi-step, but straightforward logic
4. **Batch DELETE** - Most complex, requires loop and per-batch tracking

---

## Detailed Task Plan

## Stage 1: TRUNCATE TABLE Method (2-3 hours)

⚠️ **CRITICAL NOTE**: TRUNCATE TABLE does **NOT** meet the requirement to "remove records older than 10 days while keeping recent data". It removes **ALL** data from the table. This method is included to measure its performance characteristics, but is **only suitable when the entire table can be cleared**.

### 1.1 Core Implementation

**Task**: Implement `execute_truncate_cleanup()` function in `db-cleanup.sh`

**Input Parameters**:
- `$1` - table name (default: `cleanup_truncate`)

**Logic**:
```bash
execute_truncate_cleanup() {
    local table=${1:-cleanup_truncate}
    local database=${DB_NAME:-cleanup_bench}
    
    log "INFO" "Executing TRUNCATE cleanup on ${database}.${table}"
    
    # Execute TRUNCATE
    local sql="TRUNCATE TABLE ${database}.${table};"
    mysql_exec "$sql"
    
    if [ $? -ne 0 ]; then
        log "ERROR" "TRUNCATE failed"
        return 1
    fi
    
    log "INFO" "TRUNCATE completed successfully"
    return 0
}
```

**SQL Pattern**:
```sql
TRUNCATE TABLE cleanup_bench.cleanup_truncate;
```

### 1.2 Metrics Integration

**Task**: Create `run_truncate_cleanup()` wrapper with metrics

**Logic**:
```bash
run_truncate_cleanup() {
    local table=${1:-cleanup_truncate}
    local method="truncate"
    
    log "INFO" "Starting TRUNCATE cleanup with metrics collection"
    
    # 1. Pre-cleanup snapshot
    local snapshot_before=$(capture_metrics_snapshot "before" "$table")
    local start_ts=$(get_timestamp)
    
    # 2. Execute cleanup
    execute_truncate_cleanup "$table"
    local exit_code=$?
    
    # 3. Post-cleanup snapshot
    local end_ts=$(get_timestamp)
    local snapshot_after=$(capture_metrics_snapshot "after" "$table")
    
    # 4. Calculate duration
    local duration=$(calculate_duration "$start_ts" "$end_ts")
    
    # 5. Log metrics
    if [ $exit_code -eq 0 ]; then
        log_metrics "$method" "$table" "$snapshot_before" "$snapshot_after" "$duration"
        log "INFO" "TRUNCATE cleanup complete: duration=${duration}s"
    else
        log "ERROR" "TRUNCATE cleanup failed"
        return 1
    fi
    
    return 0
}
```

### 1.3 Testing

**Test 1: Basic Functionality**
```bash
# Setup: Load data
./run-in-container.sh db-load.sh --rows 10000

# Execute: TRUNCATE cleanup
./run-in-container.sh db-cleanup.sh --method truncate

# Verify:
# - cleanup_truncate table is empty (0 rows) - ALL DATA REMOVED
# - Metrics log created in results/
# - Duration < 5 seconds
# - rows_deleted = 10000 (all rows, not just old ones)
# - space_freed > 0
# - binlog_growth minimal (~1 KB)
# NOTE: This removes ALL data, not just records older than 10 days
```

**Test 2: With Concurrent Load**
```bash
# Setup: Load data
./run-in-container.sh db-load.sh --rows 10000

# Start traffic
./run-in-container.sh db-traffic.sh --rows-per-second 10 &
TRAFFIC_PID=$!

# Execute cleanup
./run-in-container.sh db-cleanup.sh --method truncate

# Stop traffic
kill $TRAFFIC_PID

# Verify:
# - Cleanup successful
# - No errors in cleanup or traffic logs
# - Metrics captured
```

### 1.4 Expected Results

**Characteristics**:
- **Duration**: 1-3 seconds
- **rows_deleted_per_second**: 50,000 - 500,000 (very fast)
- **Replication lag**: Minimal (<2 seconds)
- **Binlog growth**: ~1 KB (single DDL statement)
- **Space freed**: Full (all DATA_LENGTH + INDEX_LENGTH)
- **Fragmentation**: 0% (fresh table)

⚠️ **CRITICAL WARNINGS**:
- **REMOVES ALL DATA** - Does NOT keep recent 10 days (removes everything)
- **DOES NOT MEET PROJECT REQUIREMENT** for selective cleanup
- Table locked during operation (brief)
- Only suitable for:
  - Temporary tables that can be fully cleared
  - Staging tables in batch processing
  - Tables that need complete refresh
- **NOT suitable for production tables with retention requirements**

### 1.5 Documentation

**Task**: Document TRUNCATE method characteristics

**Create**: Section in results log template showing:
- ⚠️ **CRITICAL: Does NOT meet selective cleanup requirement (removes ALL data)**
- When to use TRUNCATE (only when entire table can be cleared)
- Limitations (removes all data - no retention of recent records)
- Expected performance profile
- Use cases (batch processing, full refresh scenarios, temporary tables)
- Comparison note: Faster than other methods, but NOT suitable for production with retention policy

---

## Stage 2: DROP PARTITION Method (3-4 hours)

### 2.1 Partition Identification

**Task**: Implement `identify_old_partitions()` function

**Input Parameters**:
- `$1` - table name
- `$2` - retention days (default: 10)

**Logic**:
```bash
identify_old_partitions() {
    local table=${1:-cleanup_partitioned}
    local retention_days=${2:-10}
    local database=${DB_NAME:-cleanup_bench}
    
    log "INFO" "Identifying partitions older than ${retention_days} days"
    
    # Calculate cutoff date
    local cutoff_days=$(date -d "${retention_days} days ago" +%s)
    local cutoff_days_since_epoch=$(( cutoff_days / 86400 ))
    local to_days_cutoff=$(mysql_exec "SELECT TO_DAYS(NOW() - INTERVAL ${retention_days} DAY)" | tail -1)
    
    # Query partitions from information_schema
    local sql="
    SELECT PARTITION_NAME
    FROM information_schema.PARTITIONS
    WHERE TABLE_SCHEMA = '${database}'
      AND TABLE_NAME = '${table}'
      AND PARTITION_NAME NOT IN ('pFUTURE')
      AND PARTITION_DESCRIPTION < ${to_days_cutoff}
    ORDER BY PARTITION_DESCRIPTION;
    "
    
    local partitions=$(mysql_exec "$sql" | tail -n +2)  # Skip header
    
    if [ -z "$partitions" ]; then
        log "INFO" "No partitions found to drop"
        echo ""
        return 0
    fi
    
    log "INFO" "Found partitions to drop: $(echo $partitions | tr '\n' ',' | sed 's/,$//')"
    echo "$partitions"
    return 0
}
```

### 2.2 Core Implementation

**Task**: Implement `execute_partition_drop_cleanup()` function

**Logic**:
```bash
execute_partition_drop_cleanup() {
    local table=${1:-cleanup_partitioned}
    local retention_days=${2:-10}
    local database=${DB_NAME:-cleanup_bench}
    
    log "INFO" "Executing DROP PARTITION cleanup on ${database}.${table}"
    
    # Identify partitions to drop
    local partitions=$(identify_old_partitions "$table" "$retention_days")
    
    if [ -z "$partitions" ]; then
        log "INFO" "No partitions to drop, cleanup complete"
        return 0
    fi
    
    # Build partition list for ALTER TABLE
    local partition_list=$(echo "$partitions" | tr '\n' ',' | sed 's/,$//')
    
    # Execute DROP PARTITION
    local sql="ALTER TABLE ${database}.${table} DROP PARTITION ${partition_list};"
    
    log "INFO" "Executing: $sql"
    mysql_exec "$sql"
    
    if [ $? -ne 0 ]; then
        log "ERROR" "DROP PARTITION failed"
        return 1
    fi
    
    log "INFO" "DROP PARTITION completed successfully"
    return 0
}
```

**SQL Pattern**:
```sql
ALTER TABLE cleanup_bench.cleanup_partitioned 
DROP PARTITION p20251101, p20251102, p20251103;
```

### 2.3 Metrics Integration

**Task**: Create `run_partition_drop_cleanup()` wrapper

**Logic**: Same pattern as TRUNCATE (see Stage 1.2), but:
- Call `execute_partition_drop_cleanup()`
- Method name: `"partition_drop"`
- Additional logging: number of partitions dropped

### 2.4 Testing

**Test 1: Basic Functionality**
```bash
# Setup: Load data spanning 20 days
./run-in-container.sh db-load.sh --rows 10000

# Verify partitions exist
./run-in-container.sh db-cleanup.sh --method partition_drop --dry-run

# Execute cleanup (drop partitions >10 days old)
./run-in-container.sh db-cleanup.sh --method partition_drop

# Verify:
# - Partitions for dates >10 days ago removed
# - Row count reduced (approximately half)
# - Metrics log created
# - Duration < 3 seconds
```

**Test 2: No Partitions to Drop**
```bash
# Setup: Run partition drop twice
./run-in-container.sh db-cleanup.sh --method partition_drop
./run-in-container.sh db-cleanup.sh --method partition_drop

# Second run should:
# - Report "No partitions to drop"
# - Complete successfully
# - rows_deleted = 0
```

**Test 3: Partition Maintenance Integration**
```bash
# Verify partition maintenance still works after drop
./run-in-container.sh db-partition-maintenance.sh --dry-run
./run-in-container.sh db-partition-maintenance.sh

# Should add new partition for tomorrow
```

### 2.5 Expected Results

**Characteristics**:
- **Duration**: 0.5-2 seconds
- **rows_deleted_per_second**: 500,000 - 5,000,000 (very fast)
- **Replication lag**: Minimal (<1 second)
- **Binlog growth**: ~1 KB per partition dropped
- **Space freed**: Full (partition data + indexes removed)
- **Fragmentation**: 0% (partition deleted completely)

**Advantages**:
- Fastest method for partitioned tables
- No fragmentation
- Space immediately freed
- Minimal replication lag

**Requirements**:
- Table must be partitioned by date/time
- Partition boundaries must align with retention policy

### 2.6 Documentation

**Task**: Document partition identification logic

**Include**:
- How to determine which partitions are old
- TO_DAYS() calculation explanation
- How to handle pFUTURE partition (exclude from drops)
- How to verify partition structure before cleanup

---

## Stage 3: Copy-to-New-Table Method (3-4 hours)

### 3.1 Core Implementation

**Task**: Implement `execute_copy_cleanup()` function

**Logic**:
```bash
execute_copy_cleanup() {
    local table=${1:-cleanup_copy}
    local retention_days=${2:-10}
    local database=${DB_NAME:-cleanup_bench}
    local temp_table="${table}_new"
    local old_table="${table}_old"
    
    log "INFO" "Executing copy-to-new-table cleanup on ${database}.${table}"
    
    # Step 1: Create new table with same structure
    log "INFO" "Step 1: Creating new table ${temp_table}"
    local sql_create="CREATE TABLE ${database}.${temp_table} LIKE ${database}.${table};"
    mysql_exec "$sql_create"
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to create new table"
        return 1
    fi
    
    # Step 2: Copy recent data (keep data newer than retention_days)
    log "INFO" "Step 2: Copying data to new table (retaining data < ${retention_days} days old)"
    local sql_insert="
    INSERT INTO ${database}.${temp_table}
    SELECT * FROM ${database}.${table}
    WHERE ts >= NOW() - INTERVAL ${retention_days} DAY;
    "
    mysql_exec "$sql_insert"
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to copy data to new table"
        # Cleanup: drop temp table
        mysql_exec "DROP TABLE IF EXISTS ${database}.${temp_table};"
        return 1
    fi
    
    # Step 3: Atomic table swap
    log "INFO" "Step 3: Swapping tables"
    local sql_rename="
    RENAME TABLE 
        ${database}.${table} TO ${database}.${old_table},
        ${database}.${temp_table} TO ${database}.${table};
    "
    mysql_exec "$sql_rename"
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to rename tables"
        # Cleanup: drop temp table
        mysql_exec "DROP TABLE IF EXISTS ${database}.${temp_table};"
        return 1
    fi
    
    # Step 4: Drop old table
    log "INFO" "Step 4: Dropping old table"
    local sql_drop="DROP TABLE ${database}.${old_table};"
    mysql_exec "$sql_drop"
    
    if [ $? -ne 0 ]; then
        log "WARNING" "Failed to drop old table, but cleanup succeeded"
        # Not critical - table swap already happened
    fi
    
    log "INFO" "Copy-to-new-table cleanup completed successfully"
    return 0
}
```

**SQL Pattern**:
```sql
-- Step 1
CREATE TABLE cleanup_bench.cleanup_copy_new LIKE cleanup_bench.cleanup_copy;

-- Step 2
INSERT INTO cleanup_bench.cleanup_copy_new
SELECT * FROM cleanup_bench.cleanup_copy
WHERE ts >= NOW() - INTERVAL 10 DAY;

-- Step 3
RENAME TABLE 
    cleanup_bench.cleanup_copy TO cleanup_bench.cleanup_copy_old,
    cleanup_bench.cleanup_copy_new TO cleanup_bench.cleanup_copy;

-- Step 4
DROP TABLE cleanup_bench.cleanup_copy_old;
```

### 3.2 Metrics Integration

**Task**: Create `run_copy_cleanup()` wrapper

**Special Considerations**:
- Metrics snapshot BEFORE CREATE (table in original state)
- Metrics snapshot AFTER DROP (cleanup complete)
- Log intermediate step durations if verbose mode enabled

**Additional Metrics to Log**:
- Rows copied (retained data count)
- Rows deleted (original count - retained count)
- Time per step (CREATE, INSERT, RENAME, DROP)

### 3.3 Testing

**Test 1: Basic Functionality**
```bash
# Setup: Load 10K rows spanning 20 days
./run-in-container.sh db-load.sh --rows 10000

# Execute copy cleanup (retain last 10 days)
./run-in-container.sh db-cleanup.sh --method copy

# Verify:
# - cleanup_copy exists with ~5K rows (last 10 days)
# - cleanup_copy_old does NOT exist (dropped)
# - cleanup_copy_new does NOT exist (renamed)
# - Metrics log shows ~5K rows deleted
# - Space freed > 0
# - Fragmentation = 0%
```

**Test 2: Error Recovery**
```bash
# Test: Simulate failure during INSERT (low disk space, etc.)
# Expected behavior:
# - Temp table cleaned up
# - Original table unchanged
# - Error logged
```

**Test 3: With Concurrent Writes**
```bash
# Start traffic
./run-in-container.sh db-traffic.sh --rows-per-second 20 &
TRAFFIC_PID=$!

# Execute cleanup
./run-in-container.sh db-cleanup.sh --method copy

# Stop traffic
kill $TRAFFIC_PID

# Verify:
# - Cleanup successful
# - New data written during cleanup is LOST (expected!)
# - Document this limitation
```

### 3.4 Expected Results

**Characteristics**:
- **Duration**: 10-60 seconds (depends on data volume)
- **rows_deleted_per_second**: 1,000 - 10,000 (moderate)
- **Replication lag**: High (10-60 seconds) - logs all INSERTs + DDL
- **Binlog growth**: Large (logs CREATE + all rows + RENAME + DROP)
- **Space freed**: Full (new table has no fragmentation)
- **Fragmentation**: 0% (fresh table)

**Advantages**:
- No fragmentation in result table
- Full space recovery
- Works without partitioning

**Disadvantages**:
- Locks table during RENAME (brief but critical)
- Loses concurrent writes during copy
- High replication lag
- Large binlog growth

**Use Cases**:
- Scheduled maintenance windows
- Tables without partitioning
- When fragmentation is a problem
- Acceptable brief downtime during RENAME

### 3.5 Documentation

**Task**: Document copy-to-new-table method

**Critical Warnings**:
- Data written between CREATE and RENAME will be LOST
- Brief table lock during RENAME
- Requires 2x table space temporarily (original + new)
- High replication lag expected

**Best Practices**:
- Run during low-traffic periods
- Consider read-only mode during execution
- Monitor disk space (need 2x table size available)

---

## Stage 4: Batch DELETE Method (4-5 hours)

### 4.1 Core Implementation

**Task**: Implement `execute_batch_delete_cleanup()` function

**Input Parameters**:
- `$1` - table name
- `$2` - retention days
- `$3` - batch size (default: 5000)
- `$4` - batch delay seconds (default: 0.1)

**Logic**:
```bash
execute_batch_delete_cleanup() {
    local table=${1:-cleanup_batch}
    local retention_days=${2:-10}
    local batch_size=${3:-5000}
    local batch_delay=${4:-0.1}
    local database=${DB_NAME:-cleanup_bench}
    
    log "INFO" "Executing batch DELETE cleanup on ${database}.${table}"
    log "INFO" "Parameters: retention=${retention_days}d, batch_size=${batch_size}, delay=${batch_delay}s"
    
    # Initialize counters
    local batch_num=0
    local total_deleted=0
    local rows_affected=1
    
    # Create batch log file
    local batch_log="${RESULTS_DIR}/batch_delete_${batch_size}_$(date +%Y%m%d_%H%M%S)_batches.csv"
    echo "batch_id,timestamp,rows_deleted,duration_sec,throughput_rows_per_sec,replication_lag_sec" > "$batch_log"
    
    # Execute DELETE in batches
    while [ $rows_affected -gt 0 ]; do
        batch_num=$((batch_num + 1))
        
        # Record batch start
        local batch_start=$(get_timestamp)
        local batch_start_readable=$(date +"%Y-%m-%d %H:%M:%S")
        
        # Execute DELETE for one batch
        local sql="
        DELETE FROM ${database}.${table}
        WHERE ts < NOW() - INTERVAL ${retention_days} DAY
        ORDER BY ts
        LIMIT ${batch_size};
        "
        
        mysql_exec "$sql"
        
        # Get rows affected
        rows_affected=$(mysql_exec "SELECT ROW_COUNT();" | tail -1)
        
        # Record batch end
        local batch_end=$(get_timestamp)
        local batch_duration=$(calculate_duration "$batch_start" "$batch_end")
        
        # Calculate batch throughput
        local batch_throughput=0
        if [ $rows_affected -gt 0 ]; then
            batch_throughput=$(awk "BEGIN {printf \"%.2f\", $rows_affected / $batch_duration}")
            total_deleted=$((total_deleted + rows_affected))
            
            # Get current replication lag
            local current_lag=$(get_replication_lag)
            
            # Log batch metrics
            echo "${batch_num},${batch_start_readable},${rows_affected},${batch_duration},${batch_throughput},${current_lag}" >> "$batch_log"
            
            log "INFO" "Batch ${batch_num}: deleted ${rows_affected} rows in ${batch_duration}s (${batch_throughput} rows/sec)"
            
            # Sleep between batches
            if [ $rows_affected -eq $batch_size ]; then
                sleep "$batch_delay"
            fi
        else
            log "INFO" "No more rows to delete, cleanup complete"
            break
        fi
        
        # Safety check: prevent infinite loop
        if [ $batch_num -ge 10000 ]; then
            log "ERROR" "Exceeded maximum batch count (10000), aborting"
            return 1
        fi
    done
    
    log "INFO" "Batch DELETE completed: ${batch_num} batches, ${total_deleted} total rows deleted"
    log "INFO" "Per-batch metrics logged to: ${batch_log}"
    
    return 0
}
```

**SQL Pattern**:
```sql
-- Executed repeatedly until ROW_COUNT() = 0
DELETE FROM cleanup_bench.cleanup_batch
WHERE ts < NOW() - INTERVAL 10 DAY
ORDER BY ts
LIMIT 5000;
```

### 4.2 Batch Metrics Collection

**Task**: Implement per-batch metrics tracking

**Batch Log Format** (CSV):
```csv
batch_id,timestamp,rows_deleted,duration_sec,throughput_rows_per_sec,replication_lag_sec
1,2025-11-20 15:30:00,5000,4.2,1190.48,0
2,2025-11-20 15:30:05,5000,4.5,1111.11,2
3,2025-11-20 15:30:10,5000,5.1,980.39,5
...
```

**Analysis Function**: `analyze_batch_metrics()`

```bash
analyze_batch_metrics() {
    local batch_log=$1
    
    if [ ! -f "$batch_log" ]; then
        log "WARNING" "Batch log not found: $batch_log"
        return 1
    fi
    
    log "INFO" "Analyzing batch metrics from: $batch_log"
    
    # Calculate statistics using awk
    awk -F',' 'NR>1 {
        total_rows += $3
        total_duration += $4
        sum_throughput += $5
        max_lag = ($6 > max_lag) ? $6 : max_lag
        min_throughput = (min_throughput == 0 || $5 < min_throughput) ? $5 : min_throughput
        max_throughput = ($5 > max_throughput) ? $5 : max_throughput
        count++
    }
    END {
        printf "Total Batches: %d\n", count
        printf "Total Rows Deleted: %d\n", total_rows
        printf "Total Duration: %.2f seconds\n", total_duration
        printf "Average Throughput: %.2f rows/sec\n", sum_throughput / count
        printf "Min Throughput: %.2f rows/sec\n", min_throughput
        printf "Max Throughput: %.2f rows/sec\n", max_throughput
        printf "Throughput Degradation: %.1f%%\n", ((max_throughput - min_throughput) / max_throughput) * 100
        printf "Max Replication Lag: %.2f seconds\n", max_lag
    }' "$batch_log"
}
```

### 4.3 Metrics Integration

**Task**: Create `run_batch_delete_cleanup()` wrapper

**Special Considerations**:
- Collect overall metrics (before/after snapshots)
- Collect per-batch metrics (separate log file)
- Analyze batch metrics at end
- Include batch analysis in summary

**Additional Metrics**:
- Total batches executed
- Average batch throughput
- Throughput degradation (first vs last batch)
- Maximum replication lag observed

### 4.4 Parameter Tuning Tests

**Task**: Test different batch sizes

**Test Matrix**:
```
| Batch Size | Expected Throughput | Replication Lag | Lock Contention |
| ---------- | ------------------- | --------------- | --------------- |
| 1000       | Lower               | Lower           | Lower           |
| 5000       | Medium              | Medium          | Medium          |
| 10000      | Higher              | Higher          | Higher          |
```

**Test Procedure**:
```bash
# Test 1: Small batches (1000)
./run-in-container.sh db-load.sh --rows 50000
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 1000

# Test 2: Medium batches (5000)
./run-in-container.sh db-load.sh --rows 50000
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 5000

# Test 3: Large batches (10000)
./run-in-container.sh db-load.sh --rows 50000
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 10000

# Compare results:
# - Total duration
# - Average throughput
# - Replication lag
# - Fragmentation impact
```

### 4.5 Testing

**Test 1: Basic Functionality**
```bash
# Setup: Load 10K rows
./run-in-container.sh db-load.sh --rows 10000

# Execute batch DELETE
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 5000

# Verify:
# - Approximately 5K rows deleted (old data)
# - Multiple batches executed
# - Batch log created
# - Metrics log created
# - Fragmentation increased (DATA_FREE > 0)
```

**Test 2: With Concurrent Load**
```bash
# Start traffic
./run-in-container.sh db-traffic.sh --rows-per-second 20 &
TRAFFIC_PID=$!

# Execute cleanup
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 5000

# Stop traffic
kill $TRAFFIC_PID

# Verify:
# - Cleanup successful
# - No deadlocks
# - Query latency increased during cleanup
# - Replication lag tracked in batch log
```

**Test 3: Throughput Degradation**
```bash
# Setup: Load 100K rows for longer test
./run-in-container.sh db-load.sh --rows 100000

# Execute large cleanup
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 5000

# Analyze batch log:
# - Compare first batch throughput vs last batch
# - Expected: 10-30% degradation
# - Cause: Index overhead, fragmentation
```

**Test 4: OPTIMIZE TABLE After Cleanup**
```bash
# Run batch delete
./run-in-container.sh db-cleanup.sh --method batch_delete

# Check fragmentation
mysql -e "SELECT DATA_FREE, DATA_LENGTH FROM information_schema.TABLES 
          WHERE TABLE_NAME='cleanup_batch';"

# Run OPTIMIZE (optional Phase 5 enhancement)
mysql -e "OPTIMIZE TABLE cleanup_bench.cleanup_batch;"

# Check fragmentation again (should be 0)
```

### 4.6 Expected Results

**Characteristics**:
- **Duration**: 30-300 seconds (depends on data volume and batch size)
- **rows_deleted_per_second**: 500 - 5,000 (slowest method)
- **Replication lag**: Medium-High (5-60 seconds)
- **Binlog growth**: Large (logs every DELETE statement)
- **Space freed**: NONE (space marked as DATA_FREE but not released)
- **Fragmentation**: High (20-50% depending on data distribution)

**Batch Characteristics**:
- **First batch**: Highest throughput
- **Middle batches**: Gradual slowdown
- **Last batch**: Lowest throughput (may be 50-70% of first batch)
- **Degradation cause**: Index overhead increases, fragmentation

**Advantages**:
- Table remains online during cleanup
- No table locks (row-level locking only)
- Incremental progress (can stop/resume)
- Low impact per batch

**Disadvantages**:
- Slowest method
- High replication lag accumulation
- Large binlog growth
- Space NOT freed (requires OPTIMIZE TABLE)
- Fragmentation increases
- Performance degrades over time

**Use Cases**:
- Must keep table online 24/7
- Incremental cleanup during low-traffic periods
- Cannot use partitioning
- Acceptable performance degradation

### 4.7 Documentation

**Task**: Document batch DELETE tuning

**Include**:
- Batch size selection guidelines
  - Small (1K): Lower impact, slower overall
  - Medium (5K): Balanced
  - Large (10K+): Higher impact, faster overall
- Batch delay tuning (replication catch-up time)
- Throughput degradation explanation
- Fragmentation impact
- When to run OPTIMIZE TABLE

**Post-Cleanup Recommendations**:
```sql
-- Check fragmentation
SELECT TABLE_NAME, DATA_FREE, DATA_LENGTH, INDEX_LENGTH,
       ROUND(DATA_FREE / (DATA_LENGTH + INDEX_LENGTH) * 100, 2) AS fragmentation_pct
FROM information_schema.TABLES
WHERE TABLE_NAME = 'cleanup_batch';

-- Reclaim space (if fragmentation > 20%)
OPTIMIZE TABLE cleanup_bench.cleanup_batch;
```

---

## Stage 5: CLI Integration (2 hours)

### 5.1 Command-Line Interface

**Task**: Extend `db-cleanup.sh` argument parsing

**New Options**:
```bash
--method <name>           # truncate|partition_drop|copy|batch_delete|all
--table <name>           # Override default table (optional)
--retention-days <n>     # Days of data to retain (default: 10)
--batch-size <n>         # For batch_delete method (default: 5000)
--batch-delay <n>        # Seconds between batches (default: 0.1)
--dry-run                # Show what would be done, don't execute
--help                   # Show usage information
```

**Usage Examples**:
```bash
# Run TRUNCATE cleanup
./run-in-container.sh db-cleanup.sh --method truncate

# Run partition drop with custom retention
./run-in-container.sh db-cleanup.sh --method partition_drop --retention-days 7

# Run batch delete with custom batch size
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 10000

# Run copy method on custom table
./run-in-container.sh db-cleanup.sh --method copy --table cleanup_copy

# Dry run to preview actions
./run-in-container.sh db-cleanup.sh --method all --dry-run

# Run all methods sequentially
./run-in-container.sh db-cleanup.sh --method all
```

### 5.2 Method Dispatch

**Task**: Implement method dispatcher

**Logic**:
```bash
run_cleanup() {
    local method=$1
    
    case "$method" in
        truncate)
            run_truncate_cleanup "$TABLE"
            ;;
        partition_drop|partition)
            run_partition_drop_cleanup "$TABLE" "$RETENTION_DAYS"
            ;;
        copy)
            run_copy_cleanup "$TABLE" "$RETENTION_DAYS"
            ;;
        batch_delete|batch)
            run_batch_delete_cleanup "$TABLE" "$RETENTION_DAYS" "$BATCH_SIZE" "$BATCH_DELAY"
            ;;
        all)
            run_all_methods
            ;;
        *)
            log "ERROR" "Unknown method: $method"
            show_usage
            exit 1
            ;;
    esac
}
```

### 5.3 All Methods Sequential Execution

**Task**: Implement `run_all_methods()` function

**Logic**:
```bash
run_all_methods() {
    log "INFO" "Running all cleanup methods sequentially"
    
    # Reload data before each method to ensure fair comparison
    local original_rows=100000
    
    # Method 1: Partition Drop
    log "INFO" "=== Method 1: DROP PARTITION ==="
    reload_table "cleanup_partitioned" "$original_rows"
    run_partition_drop_cleanup "cleanup_partitioned" "$RETENTION_DAYS"
    
    # Method 2: Truncate
    log "INFO" "=== Method 2: TRUNCATE TABLE ==="
    reload_table "cleanup_truncate" "$original_rows"
    run_truncate_cleanup "cleanup_truncate"
    
    # Method 3: Copy
    log "INFO" "=== Method 3: Copy-to-New-Table ==="
    reload_table "cleanup_copy" "$original_rows"
    run_copy_cleanup "cleanup_copy" "$RETENTION_DAYS"
    
    # Method 4: Batch Delete
    log "INFO" "=== Method 4: Batch DELETE ==="
    reload_table "cleanup_batch" "$original_rows"
    run_batch_delete_cleanup "cleanup_batch" "$RETENTION_DAYS" "$BATCH_SIZE" "$BATCH_DELAY"
    
    log "INFO" "All methods completed"
    log "INFO" "Results saved to: $RESULTS_DIR"
    log "INFO" "Run 'generate_summary_report' to compare methods"
}

reload_table() {
    local table=$1
    local rows=$2
    
    log "INFO" "Reloading ${table} with ${rows} rows"
    
    # Truncate table
    mysql_exec "TRUNCATE TABLE ${DB_NAME}.${table};"
    
    # Reload from CSV (reuse existing CSV if available)
    db-load.sh --rows "$rows" --table "$table" --quiet
}
```

---

## Stage 6: Testing & Validation (2-3 hours)

### 6.1 Integration Tests

**Test Suite**: Run all methods with standard dataset

**Test Script**: `test-all-methods.sh`
```bash
#!/bin/bash

set -e

echo "=== Task 03 Cleanup Methods Integration Test ==="

# Configuration
ROWS=50000
RETENTION=10

# Test 1: Load data
echo "Loading test data..."
./run-in-container.sh db-load.sh --rows $ROWS

# Test 2: TRUNCATE method
echo ""
echo "Testing TRUNCATE method..."
./run-in-container.sh db-cleanup.sh --method truncate

# Test 3: DROP PARTITION method
echo ""
echo "Testing DROP PARTITION method..."
./run-in-container.sh db-load.sh --rows $ROWS --table cleanup_partitioned
./run-in-container.sh db-cleanup.sh --method partition_drop --retention-days $RETENTION

# Test 4: Copy method
echo ""
echo "Testing Copy-to-New-Table method..."
./run-in-container.sh db-load.sh --rows $ROWS --table cleanup_copy
./run-in-container.sh db-cleanup.sh --method copy --retention-days $RETENTION

# Test 5: Batch DELETE method
echo ""
echo "Testing Batch DELETE method..."
./run-in-container.sh db-load.sh --rows $ROWS --table cleanup_batch
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 5000

# Verify results
echo ""
echo "=== Test Results ==="
echo "Check logs in: task03/results/"
ls -lh task03/results/

echo ""
echo "Integration tests complete!"
```

### 6.2 Concurrent Load Tests

**Test**: Run cleanup with `db-traffic.sh` generating load

**Test Script**: `test-with-load.sh`
```bash
#!/bin/bash

echo "=== Cleanup Methods with Concurrent Load Test ==="

# Load data
./run-in-container.sh db-load.sh --rows 50000

# Start background traffic
echo "Starting background traffic..."
./run-in-container.sh db-traffic.sh --rows-per-second 20 &
TRAFFIC_PID=$!

# Wait for traffic to start
sleep 5

# Run cleanup methods
echo "Running batch DELETE with concurrent load..."
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 5000

# Stop traffic
echo "Stopping background traffic..."
kill $TRAFFIC_PID
wait $TRAFFIC_PID 2>/dev/null

echo "Test complete!"
```

### 6.3 Performance Benchmarks

**Goal**: Establish baseline performance for each method

**Dataset Sizes**:
- Small: 10,000 rows
- Medium: 100,000 rows
- Large: 1,000,000 rows (optional, if time permits)

**Metrics to Record**:
- Duration
- Throughput (rows/sec)
- Replication lag
- Binlog growth
- Space freed
- Fragmentation

**Benchmark Script**: `benchmark-all.sh`
```bash
#!/bin/bash

for size in 10000 100000; do
    echo "=== Benchmarking with ${size} rows ==="
    
    # Run all methods
    ./run-in-container.sh db-load.sh --rows $size --force-regenerate
    ./run-in-container.sh db-cleanup.sh --method all
    
    # Generate report
    echo "Results for ${size} rows:"
    cat task03/results/summary.csv
done
```

---

## Stage 7: Documentation (1-2 hours)

### 7.1 Update README.md

**Task**: Add Phase 5 documentation to `task03/README.md`

**Sections to Add**:

#### 4. Cleanup Methods

Description of each method with characteristics:

```markdown
## Cleanup Methods

This project implements and compares four cleanup methods for removing old data from large MySQL tables.

### Method 1: DROP PARTITION

**Table**: `cleanup_partitioned`

**SQL**: `ALTER TABLE cleanup_partitioned DROP PARTITION p20251101, ...;`

**Characteristics**:
- Fastest method (millions of rows/sec)
- Minimal replication lag (<1 sec)
- Full space recovery
- No fragmentation
- Requires partitioned table

**Usage**:
```bash
./run-in-container.sh db-cleanup.sh --method partition_drop
```

**When to Use**: Production tables with date-based partitioning and regular cleanup needs.

---

### Method 2: TRUNCATE TABLE

**Table**: `cleanup_truncate`

**SQL**: `TRUNCATE TABLE cleanup_truncate;`

**Characteristics**:
- Very fast (hundreds of thousands rows/sec)
- Minimal replication lag (<2 sec)
- Full space recovery
- No fragmentation
- **Removes ALL data** (not selective)

**Usage**:
```bash
./run-in-container.sh db-cleanup.sh --method truncate
```

**When to Use**: Batch processing where entire table can be cleared (temporary tables, staging tables).

**Warning**: Removes all data, not just old data. Not suitable for selective cleanup.

---

### Method 3: Copy-to-New-Table

**Table**: `cleanup_copy`

**SQL**:
```sql
CREATE TABLE cleanup_copy_new LIKE cleanup_copy;
INSERT INTO cleanup_copy_new SELECT * FROM cleanup_copy WHERE ts >= NOW() - INTERVAL 10 DAY;
RENAME TABLE cleanup_copy TO cleanup_copy_old, cleanup_copy_new TO cleanup_copy;
DROP TABLE cleanup_copy_old;
```

**Characteristics**:
- Moderate speed (thousands of rows/sec)
- High replication lag (10-60 sec)
- Full space recovery
- No fragmentation
- Brief table lock during RENAME
- Loses concurrent writes

**Usage**:
```bash
./run-in-container.sh db-cleanup.sh --method copy --retention-days 10
```

**When to Use**: Scheduled maintenance windows, tables without partitioning, when fragmentation is problematic.

**Warning**: Data written between CREATE and RENAME will be lost. Run during low-traffic periods.

---

### Method 4: Batch DELETE

**Table**: `cleanup_batch`

**SQL**:
```sql
DELETE FROM cleanup_batch 
WHERE ts < NOW() - INTERVAL 10 DAY 
ORDER BY ts 
LIMIT 5000;
-- Repeated until no rows match
```

**Characteristics**:
- Slowest method (hundreds to low thousands rows/sec)
- Medium-high replication lag (5-60 sec)
- **No space recovery** (requires OPTIMIZE TABLE)
- High fragmentation (20-50%)
- Table stays online
- Performance degrades over time

**Usage**:
```bash
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 5000
```

**Tuning**:
- Smaller batch size: Lower impact, slower overall
- Larger batch size: Higher impact, faster overall
- Default: 5000 rows per batch

**Post-Cleanup**:
```bash
# Check fragmentation
mysql -e "SELECT DATA_FREE, DATA_LENGTH FROM information_schema.TABLES WHERE TABLE_NAME='cleanup_batch';"

# Reclaim space (run during maintenance window)
mysql -e "OPTIMIZE TABLE cleanup_bench.cleanup_batch;"
```

**When to Use**: Must keep table online 24/7, incremental cleanup during low-traffic, cannot use partitioning.
```

### 7.2 Usage Examples

**Task**: Create comprehensive examples section

```markdown
## Usage Examples

### Run Single Method
```bash
# Partition drop
./run-in-container.sh db-cleanup.sh --method partition_drop

# Truncate
./run-in-container.sh db-cleanup.sh --method truncate

# Copy
./run-in-container.sh db-cleanup.sh --method copy

# Batch delete
./run-in-container.sh db-cleanup.sh --method batch_delete
```

### Custom Parameters
```bash
# Custom retention period (7 days instead of 10)
./run-in-container.sh db-cleanup.sh --method partition_drop --retention-days 7

# Custom batch size
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 10000

# Custom table
./run-in-container.sh db-cleanup.sh --method copy --table my_custom_table
```

### Run All Methods
```bash
# Compare all methods with same dataset
./run-in-container.sh db-cleanup.sh --method all
```

### Dry Run
```bash
# Preview what would be done
./run-in-container.sh db-cleanup.sh --method partition_drop --dry-run
```

### With Concurrent Load
```bash
# Start background traffic
./run-in-container.sh db-traffic.sh --rows-per-second 20 &
TRAFFIC_PID=$!

# Run cleanup
./run-in-container.sh db-cleanup.sh --method batch_delete

# Stop traffic
kill $TRAFFIC_PID
```
```

### 7.3 Results Interpretation Guide

**Task**: Document how to read and compare results

```markdown
## Interpreting Results

### Metrics Logs

Each cleanup execution creates a metrics log in `task03/results/`:

```
results/
├── partition_drop_20251120_153000_metrics.log
├── truncate_20251120_153100_metrics.log
├── copy_20251120_153200_metrics.log
├── batch_delete_5000_20251120_153300_metrics.log
└── batch_delete_5000_20251120_153300_batches.csv
```

### Key Metrics

**rows_deleted_per_second**: Primary performance metric
- Higher is better
- Partition drop: 500K - 5M
- Truncate: 50K - 500K
- Copy: 1K - 10K
- Batch delete: 500 - 5K

**Replication Lag**: Impact on replicas
- Lower is better
- Partition drop: <1 sec
- Truncate: <2 sec
- Copy: 10-60 sec
- Batch delete: 5-60 sec

**Space Freed**: Disk space recovered
- Higher is better
- Partition drop: 100%
- Truncate: 100%
- Copy: 100%
- Batch delete: 0% (requires OPTIMIZE)

**Fragmentation**: Table fragmentation after cleanup
- Lower is better
- Partition drop: 0%
- Truncate: 0%
- Copy: 0%
- Batch delete: 20-50%

### Method Selection Guide

**Choose DROP PARTITION when**:
- Table is partitioned by date/time
- Regular cleanup schedule (daily/weekly)
- Production environment
- Speed is critical
- **Best overall method when partitioning is available**

**Choose TRUNCATE when**:
- Entire table can be cleared
- Temporary or staging tables
- Batch processing workflows
- **Not suitable for selective cleanup**

**Choose Copy-to-New-Table when**:
- Table not partitioned
- Scheduled maintenance windows
- Fragmentation is problematic
- Brief downtime acceptable
- **Good for periodic cleanup with defragmentation**

**Choose Batch DELETE when**:
- Table must stay online 24/7
- Cannot use partitioning
- Incremental cleanup needed
- Performance degradation acceptable
- Can run OPTIMIZE TABLE later
- **Last resort when other methods unavailable**
```

---

## Phase 5 Deliverables

### Files Modified
1. **`task03/db-cleanup.sh`** - Extended with all four cleanup methods
   - `execute_truncate_cleanup()`
   - `execute_partition_drop_cleanup()`
   - `execute_copy_cleanup()`
   - `execute_batch_delete_cleanup()`
   - `run_truncate_cleanup()`
   - `run_partition_drop_cleanup()`
   - `run_copy_cleanup()`
   - `run_batch_delete_cleanup()`
   - `identify_old_partitions()`
   - `analyze_batch_metrics()`
   - CLI argument parsing for all methods

### Files Created
1. **`task03/results/<method>_<timestamp>_metrics.log`** - Per-execution metrics logs
2. **`task03/results/batch_delete_<size>_<timestamp>_batches.csv`** - Per-batch metrics
3. **Test scripts** (optional):
   - `test-all-methods.sh`
   - `test-with-load.sh`
   - `benchmark-all.sh`

### Documentation Updated
1. **`task03/README.md`** - Complete cleanup methods documentation
2. **`task03/memory-bank/phase5_implementation_summary.md`** - Implementation results
3. **`task03/memory-bank/phase5_tasks.md`** - Task completion checklist

---

## Success Criteria Checklist

Phase 5 is complete when:

- [ ] **TRUNCATE method** implemented and tested
  - [ ] execute_truncate_cleanup() function working
  - [ ] Metrics integration complete
  - [ ] Test without load passed
  - [ ] Test with concurrent load passed
  
- [ ] **DROP PARTITION method** implemented and tested
  - [ ] identify_old_partitions() function working
  - [ ] execute_partition_drop_cleanup() function working
  - [ ] Metrics integration complete
  - [ ] Partition identification accurate
  - [ ] Test without load passed
  - [ ] Test with concurrent load passed
  
- [ ] **Copy-to-New-Table method** implemented and tested
  - [ ] execute_copy_cleanup() function working
  - [ ] All 4 steps (CREATE, INSERT, RENAME, DROP) working
  - [ ] Error recovery implemented
  - [ ] Metrics integration complete
  - [ ] Test without load passed
  - [ ] Test with concurrent load passed
  
- [ ] **Batch DELETE method** implemented and tested
  - [ ] execute_batch_delete_cleanup() function working
  - [ ] Per-batch metrics logging working
  - [ ] analyze_batch_metrics() function working
  - [ ] Batch size parameter tuning tested
  - [ ] Throughput degradation measured
  - [ ] Test without load passed
  - [ ] Test with concurrent load passed
  
- [ ] **CLI Integration** complete
  - [ ] All command-line options implemented
  - [ ] Method dispatch working
  - [ ] Dry-run mode working
  - [ ] Help text complete and accurate
  
- [ ] **All Methods Sequential Execution** working
  - [ ] run_all_methods() function implemented
  - [ ] Data reload between methods working
  - [ ] All four methods execute successfully
  
- [ ] **Documentation** complete
  - [ ] task03/README.md updated with all methods
  - [ ] Usage examples documented
  - [ ] Results interpretation guide written
  - [ ] Method selection guide provided
  - [ ] phase5_implementation_summary.md created
  
- [ ] **Testing** complete
  - [ ] All methods tested individually
  - [ ] All methods tested with concurrent load
  - [ ] Integration tests passed
  - [ ] Performance benchmarks collected
  - [ ] Results validated and sensible

---

## Risk Mitigation

### Risk 1: Partition Drop Fails
**Mitigation**: 
- Verify partition structure in dry-run mode
- Check partition names match expected pattern
- Test with single partition first

### Risk 2: Copy Method Loses Data
**Mitigation**:
- Document warning prominently
- Consider read-only mode during execution
- Test with small dataset first

### Risk 3: Batch DELETE Runs Forever
**Mitigation**:
- Add safety counter (max 10,000 batches)
- Log progress every batch
- Allow Ctrl+C to interrupt gracefully

### Risk 4: Metrics Collection Fails
**Mitigation**:
- Test metrics framework independently first
- Graceful degradation if metric unavailable
- Log warnings, don't abort cleanup

---

## Timeline Estimate

| Stage | Task                     | Effort     | Dependencies |
| ----- | ------------------------ | ---------- | ------------ |
| 1     | TRUNCATE method          | 2-3h       | Phase 4      |
| 2     | DROP PARTITION method    | 3-4h       | Phase 4      |
| 3     | Copy-to-New-Table method | 3-4h       | Phase 4      |
| 4     | Batch DELETE method      | 4-5h       | Phase 4      |
| 5     | CLI Integration          | 2h         | Stages 1-4   |
| 6     | Testing & Validation     | 2-3h       | Stages 1-5   |
| 7     | Documentation            | 1-2h       | Stages 1-6   |
|       | **Total**                | **12-16h** |              |

**Recommended Schedule**:
- **Day 1 (4-6 hours)**: Stages 1-2 (TRUNCATE + DROP PARTITION)
- **Day 2 (4-6 hours)**: Stages 3-4 (Copy + Batch DELETE)
- **Day 3 (3-4 hours)**: Stages 5-7 (Integration, Testing, Documentation)

---

## Next Steps After Phase 5

**Phase 6: Orchestration & Automation**
- Enhanced orchestration in db-cleanup.sh
- Summary report generation
- Comparison tables and charts
- Cron integration for scheduled cleanup

**Phase 7: Final Documentation**
- Complete project documentation
- How to run experiments
- Results interpretation
- Best practices guide
- Troubleshooting section

---

## Related Documents

- **Phase 4 Summary**: `phase4_implementation_summary.md` - Metrics framework
- **Cleanup Methods Spec**: `implementation_cleanup_methods.md` - Original requirements
- **Orchestration Spec**: `implementation_orchestration.md` - Phase 6 preview
- **README**: `README.md` - Project overview
- **Phase 1**: `phase1_implementation_summary.md` - Database schema
- **Phase 2**: `phase2_implementation_summary.md` - Data loading
- **Phase 3**: `phase3_implementation_summary.md` - Load simulation

---

**Document Status**: Complete and Ready for Implementation  
**Last Updated**: November 20, 2025  
**Created By**: Implementation Planning Agent  
**Review Status**: Ready for execution

---

## Appendix: Quick Reference

### Command Quick Reference
```bash
# Individual methods
./run-in-container.sh db-cleanup.sh --method truncate
./run-in-container.sh db-cleanup.sh --method partition_drop
./run-in-container.sh db-cleanup.sh --method copy
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 5000

# All methods
./run-in-container.sh db-cleanup.sh --method all

# With concurrent load
./run-in-container.sh db-traffic.sh --rows-per-second 20 &
./run-in-container.sh db-cleanup.sh --method <name>
kill $!

# Results
ls -lh task03/results/
cat task03/results/<method>_*_metrics.log
```

### Expected Performance Summary
| Method         | Speed     | Repl Lag | Space Freed | Fragmentation | Partitioning Required |
| -------------- | --------- | -------- | ----------- | ------------- | --------------------- |
| DROP PARTITION | Fastest   | Minimal  | 100%        | 0%            | Yes                   |
| TRUNCATE       | Very Fast | Minimal  | 100%        | 0%            | No                    |
| Copy           | Moderate  | High     | 100%        | 0%            | No                    |
| Batch DELETE   | Slow      | Medium   | 0%          | 20-50%        | No                    |

### Decision Tree
```
Need to cleanup old data?
├─ Is table partitioned by date?
│  └─ YES → Use DROP PARTITION (best option)
│  └─ NO → Continue
├─ Can you delete ALL data?
│  └─ YES → Use TRUNCATE
│  └─ NO → Continue
├─ Can table be offline briefly (RENAME lock)?
│  └─ YES → Use Copy-to-New-Table
│  └─ NO → Use Batch DELETE (last resort, remember OPTIMIZE TABLE after)
```
