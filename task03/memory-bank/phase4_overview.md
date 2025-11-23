# Phase 4 Overview – Metrics & Instrumentation

## Quick Reference

**Phase**: 4 of 7  
**Status**: ✅ Complete (November 20, 2025)  
**Dependencies**: Phase 1 ✅, Phase 2 ✅, Phase 3 ✅  
**Enables**: Phase 5 (Cleanup Methods), Phase 6 (Orchestration)  
**Estimated Effort**: 12-16 hours  
**Actual Effort**: ~12 hours  

---

## What is Phase 4?

Phase 4 implements **comprehensive metrics collection and instrumentation** for measuring and comparing the performance of different cleanup methods. This phase doesn't implement the cleanup methods themselves—it creates the measurement framework that will be used in Phase 5 to evaluate each method.

### Why is this needed?

The goal of this project is to **experimentally determine the fastest cleanup method**. Without proper metrics, we can't:

- Objectively compare methods (which is actually faster?)
- Measure real-world impact (how much does cleanup slow down the application?)
- Understand tradeoffs (fast cleanup but huge replication lag?)
- Make data-driven recommendations (when to use which method?)

Phase 4 provides the **measurement instrumentation** that makes scientific comparison possible.

---

## The Big Picture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cleanup Benchmark Flow                       │
└─────────────────────────────────────────────────────────────────┘

Phase 1: Environment Setup ✅
Phase 2: Data Loading ✅
Phase 3: Load Simulation ✅
   
Phase 4: Metrics & Instrumentation ← YOU ARE HERE
   ↓
   Build measurement framework:
   • Collect MySQL status variables (InnoDB metrics)
   • Monitor replication lag on replica
   • Track table sizes and space freed
   • Measure binlog growth
   • Calculate delete throughput (rows/sec)
   • Measure query latency impact
   • Track lock contention
   
   This framework will be used by Phase 5 to evaluate cleanup methods
   
Phase 5: Cleanup Methods (will use Phase 4 metrics)
   ↓
   For each method (partition drop, truncate, copy, batch delete):
   1. Capture metrics BEFORE cleanup
   2. Execute cleanup
   3. Capture metrics AFTER cleanup
   4. Calculate deltas and log results
   
Phase 6: Orchestration (automates Phase 4+5)
Phase 7: Documentation (interprets Phase 4 results)
```

---

## What Gets Built

### Primary Deliverable: Metrics Collection Framework

A set of bash functions and workflows integrated into `db-cleanup.sh` that:

1. **Capture snapshots** of system state before/after cleanup
2. **Measure duration** with nanosecond precision
3. **Calculate throughput** (rows deleted per second)
4. **Monitor replication** lag in real-time
5. **Track resource usage** (table sizes, binlog growth, locks)
6. **Log all metrics** to structured files for analysis
7. **Enable comparison** between methods

### Key Components

#### 1. Metrics Collection Functions

Helper functions in `db-cleanup.sh`:

```bash
# Get current timestamp with nanosecond precision
get_timestamp()

# Query MySQL status variable
get_status_var(variable_name)

# Get table size and row count
get_table_info(database, table)

# Get exact row count
get_row_count(database, table)

# Query replication lag from replica
get_replication_lag()

# Get InnoDB history list length (purge lag)
get_history_list_length()

# Get binlog file list and sizes
get_binlog_list()

# Measure query execution time
measure_query_latency(query)
```

#### 2. Snapshot Capture

Before and after each cleanup:

```bash
capture_metrics_snapshot() {
  # Capture at a single point in time:
  # - InnoDB row operations (inserts, deletes, updates)
  # - InnoDB locking metrics (lock time, lock waits)
  # - Table sizes (data, indexes, free space)
  # - Row counts
  # - Replication lag
  # - Binlog state
  # - Timestamp
  
  # Return structured data (associative array or JSON)
}
```

#### 3. Metrics Logging

Write results to files:

```bash
log_metrics(method, snapshot_before, snapshot_after, duration) {
  # Create log file: results/<method>_<timestamp>_metrics.csv
  
  # Write summary section:
  # - Method name, table, start/end time, duration
  # - Rows before/after/deleted
  # - Primary metric: rows_deleted_per_second
  
  # Write detailed sections:
  # - InnoDB metrics (deltas)
  # - Replication metrics (lag before/during/after)
  # - Table size changes
  # - Binlog growth
  # - Query latency impact
}
```

#### 4. Integration Wrapper

Instrument each cleanup method:

```bash
run_cleanup_with_metrics() {
  local method_name=$1
  
  # Before cleanup
  snapshot_before=$(capture_metrics_snapshot "before")
  start_ts=$(get_timestamp)
  
  # Execute cleanup method
  execute_cleanup_method "$method_name"
  
  # After cleanup
  end_ts=$(get_timestamp)
  snapshot_after=$(capture_metrics_snapshot "after")
  
  # Calculate and log
  duration=$(echo "$end_ts - $start_ts" | bc)
  log_metrics "$method_name" "$snapshot_before" "$snapshot_after" "$duration"
}
```

---

## Key Metrics Explained

### 1. Delete Throughput (Primary Metric)

**What**: Rows deleted per second

**Formula**: `rows_deleted_per_second = (rows_before - rows_after) / duration_seconds`

**Example**:
- Rows before: 100,000
- Rows after: 50,000
- Duration: 25 seconds
- Throughput: (100,000 - 50,000) / 25 = **2,000 rows/sec**

**Why it matters**: This is the primary performance metric. Higher is better.

**Expected ranges**:
- DROP PARTITION: Instant (millions of rows/sec)
- TRUNCATE TABLE: Very fast (hundreds of thousands/sec)
- Copy-to-new-table: Moderate (thousands/sec)
- Batch DELETE: Slowest (hundreds to thousands/sec)

---

### 2. Replication Lag

**What**: How far behind the replica is from the master (in seconds)

**Source**: `SHOW REPLICA STATUS` on the replica server

**Measured**:
- Before cleanup starts
- Every 10 seconds during cleanup
- After cleanup completes
- **Maximum lag** during cleanup (worst case)

**Why it matters**: High replication lag means:
- Replica data is stale (bad for read replicas)
- Risk of running out of relay log space
- Longer recovery time if master fails

**Example**:
```
Before cleanup:     0 seconds (caught up)
During cleanup:     5s → 12s → 18s → 25s → 15s
After cleanup:      3 seconds
Maximum lag:        25 seconds
```

**Expected**:
- DROP PARTITION: Minimal lag (small DDL statement)
- TRUNCATE: Minimal lag (small DDL statement)
- Copy-to-new-table: High lag (logs all INSERT + DDL)
- Batch DELETE: High lag (logs all DELETE statements)

---

### 3. Table Size and Space Freed

**What**: Actual disk space freed by cleanup

**Source**: `information_schema.TABLES`

**Metrics**:
- `DATA_LENGTH`: Size of table data in bytes
- `INDEX_LENGTH`: Size of indexes in bytes
- `DATA_FREE`: Free space inside table file (fragmentation)

**Calculation**:
```
space_freed = (DATA_LENGTH + INDEX_LENGTH)_before - 
              (DATA_LENGTH + INDEX_LENGTH)_after
```

**Why it matters**: 
- Some methods don't actually free space to OS (batch DELETE)
- High `DATA_FREE` after cleanup = fragmentation
- May need `OPTIMIZE TABLE` after batch DELETE

**Example**:
```
Before:
  DATA_LENGTH:  500 MB
  INDEX_LENGTH: 100 MB
  DATA_FREE:    10 MB
  Total:        600 MB

After (batch DELETE):
  DATA_LENGTH:  500 MB  (unchanged!)
  INDEX_LENGTH: 100 MB  (unchanged!)
  DATA_FREE:    260 MB  (increased!)
  Total:        600 MB  (no space freed to OS)

After (TRUNCATE or partition drop):
  DATA_LENGTH:  250 MB  (reduced!)
  INDEX_LENGTH: 50 MB   (reduced!)
  DATA_FREE:    0 MB    (no fragmentation)
  Total:        300 MB  (300 MB freed!)
```

---

### 4. Binary Log Growth

**What**: How much binlog data is generated by cleanup

**Source**: `SHOW BINARY LOGS`

**Why it matters**:
- Large binlog = longer replication time
- Large binlog = more disk space needed
- Affects backup and point-in-time recovery

**Expected**:
- DROP PARTITION: Tiny (one DDL statement)
- TRUNCATE: Tiny (one DDL statement)
- Copy-to-new-table: Large (logs CREATE + all INSERTs + RENAME + DROP)
- Batch DELETE: Large (logs every DELETE statement)

**Example**:
```
Batch DELETE (50,000 rows, batch size 1000):
  50 DELETE statements in binlog
  Binlog growth: ~2-5 MB

DROP PARTITION (50,000 rows):
  1 ALTER TABLE statement in binlog
  Binlog growth: ~1 KB
```

---

### 5. Query Latency Impact

**What**: How much slower are application queries during cleanup?

**Measurement**:
- Run sample queries 10x before cleanup (baseline)
- Run sample queries during cleanup (impacted)
- Run sample queries 10x after cleanup (recovered)
- Calculate average and p95 latency for each phase

**Sample queries**:
1. SELECT recent data: `SELECT * FROM table WHERE ts >= NOW() - INTERVAL 5 MINUTE LIMIT 10`
2. UPDATE recent data: `UPDATE table SET data = data + 1 WHERE ts >= NOW() - INTERVAL 10 MINUTE LIMIT 10`

**Why it matters**:
- Shows real impact on application performance
- Some methods block all queries (TRUNCATE)
- Some methods only slow specific queries (batch DELETE)

**Example**:
```
Method: Batch DELETE
Query: SELECT recent data

Baseline (before):     5 ms average, 8 ms p95
During cleanup:        45 ms average, 120 ms p95  (9x slower!)
After cleanup:         6 ms average, 9 ms p95     (recovered)

Method: DROP PARTITION
Query: SELECT recent data

Baseline (before):     5 ms average, 8 ms p95
During cleanup:        5 ms average, 8 ms p95     (no impact!)
After cleanup:         5 ms average, 8 ms p95     (no impact!)
```

---

### 6. InnoDB History List Length

**What**: Purge lag in InnoDB (how many transaction history records need cleanup)

**Source**: `SHOW ENGINE INNODB STATUS` or `information_schema.INNODB_METRICS`

**Why it matters**:
- High history list = old MVCC versions not purged
- Can slow down queries and cause bloat
- Indicates rate of change exceeds InnoDB's purge capacity

**Expected**:
- Should stay low during DDL methods (DROP/TRUNCATE)
- May grow during large batch DELETE operations

---

### 7. Lock Contention

**What**: How much locking conflict occurs during cleanup

**Metrics**:
- `Innodb_row_lock_time`: Total time spent waiting for row locks
- `Innodb_row_lock_waits`: Number of times had to wait for row lock

**Why it matters**:
- High lock wait time = application queries are blocked
- Indicates concurrent UPDATE/DELETE conflicts
- Batch DELETE has most contention

---

## How Metrics Guide Method Selection

### Scenario 1: Production Application, Read Replicas Active

**Priority**: Minimize replication lag, minimize query latency impact

**Best method**: DROP PARTITION
- Near-zero replication lag
- No query latency impact
- Instant execution

**Worst method**: Batch DELETE
- High replication lag (logs all DELETEs)
- Query latency increases (lock contention)

---

### Scenario 2: Nightly Batch Job, No Replicas

**Priority**: Maximum throughput, disk space recovery

**Best methods**: TRUNCATE (if all data can be deleted) or Copy-to-new-table
- Fast execution
- Immediate space recovery
- No fragmentation

**Worst method**: Batch DELETE
- Slower execution
- No space recovery (need OPTIMIZE TABLE after)
- High fragmentation

---

### Scenario 3: Cannot Use Partitioning

**Priority**: Balance speed and impact

**Options**:
- **Copy-to-new-table** if downtime acceptable (brief table lock during RENAME)
- **Batch DELETE** if must keep table online, tune batch size based on metrics

---

## Output Format

### Metrics Log File Example

```
=== Cleanup Metrics Report ===
Method:              batch_delete_5000
Table:               cleanup_batch
Start Time:          2025-11-20 15:30:00
End Time:            2025-11-20 15:30:45
Duration:            45 seconds

=== Row Statistics ===
Rows Before:         100000
Rows After:          50000
Rows Deleted:        50000
Delete Throughput:   1111.11 rows/sec

=== InnoDB Metrics ===
Innodb_rows_deleted (before):  1234567
Innodb_rows_deleted (after):   1284567
Delta:                          50000

Innodb_row_lock_time (before): 12345 ms
Innodb_row_lock_time (after):  23456 ms
Delta:                          11111 ms (lock contention increased)

History List Length (before):  100
History List Length (after):   450
History List Length (max):     612

=== Replication Metrics ===
Seconds_Behind_Source (before):  0
Seconds_Behind_Source (after):   8
Maximum Lag During Cleanup:      12 seconds
Average Lag During Cleanup:      7 seconds

=== Table Size Metrics ===
DATA_LENGTH (before):    524288000 bytes (500 MB)
DATA_LENGTH (after):     524288000 bytes (500 MB)
INDEX_LENGTH (before):   104857600 bytes (100 MB)
INDEX_LENGTH (after):    104857600 bytes (100 MB)
DATA_FREE (before):      10485760 bytes (10 MB)
DATA_FREE (after):       272629760 bytes (260 MB)
Space Freed to OS:       0 bytes
Fragmentation:           43.5%

=== Binlog Metrics ===
Binlog Growth:           3145728 bytes (3 MB)

=== Query Latency ===
SELECT latency (baseline):      5 ms avg, 8 ms p95
SELECT latency (during):        42 ms avg, 115 ms p95
SELECT latency (after):         6 ms avg, 9 ms p95

UPDATE latency (baseline):      8 ms avg, 12 ms p95
UPDATE latency (during):        78 ms avg, 250 ms p95
UPDATE latency (after):         9 ms avg, 13 ms p95

=== Batch Details ===
Total Batches:      10
Average Batch Throughput: 1125 rows/sec
First Batch:        1200 rows/sec
Last Batch:         950 rows/sec
Throughput Trend:   Decreasing (degradation over time)
```

### Summary CSV (for comparison)

```csv
timestamp,method,table,rows_deleted,duration_sec,throughput,replication_lag_max,space_freed_mb,binlog_growth_mb,query_latency_impact_pct
2025-11-20T15:30:00,partition_drop,cleanup_partitioned,50000,0.5,100000,0,250,0.001,0
2025-11-20T15:35:00,truncate,cleanup_truncate,100000,2.1,47619,1,600,0.002,5
2025-11-20T15:40:00,copy,cleanup_copy,50000,35.5,1408,45,250,150,15
2025-11-20T15:50:00,batch_delete_5000,cleanup_batch,50000,45.0,1111,12,0,3,700
```

---

## Implementation Phases

### Phase 4A: Basic Metrics (Core)
- [ ] Timestamp and duration measurement
- [ ] Row count before/after
- [ ] Delete throughput calculation
- [ ] Basic logging to file

### Phase 4B: InnoDB Metrics
- [ ] Status variables (rows deleted, lock time)
- [ ] History list length
- [ ] Buffer pool metrics

### Phase 4C: Replication Metrics
- [ ] Connect to replica
- [ ] Query replication lag
- [ ] Time series during cleanup

### Phase 4D: Resource Metrics
- [ ] Table sizes from information_schema
- [ ] Binlog growth tracking
- [ ] Space freed calculation

### Phase 4E: Latency Metrics
- [ ] Sample query execution timing
- [ ] Baseline vs during vs after
- [ ] Latency percentiles

### Phase 4F: Batch Metrics (DELETE only)
- [ ] Per-batch logging
- [ ] Throughput trend analysis

---

## Testing Strategy

### 1. Function Testing
Test each helper function independently:
```bash
# Test status variable query
get_status_var "Innodb_rows_deleted"
# Should return a number

# Test table info query
get_table_info "cleanup_bench" "cleanup_batch"
# Should return DATA_LENGTH, INDEX_LENGTH, etc.
```

### 2. Snapshot Testing
Test metrics capture:
```bash
# Capture snapshot before any changes
snapshot1=$(capture_metrics_snapshot "test1")

# Make a small change (insert 100 rows)
mysql -e "INSERT INTO cleanup_bench.cleanup_batch ..."

# Capture snapshot after
snapshot2=$(capture_metrics_snapshot "test2")

# Verify snapshot2 shows 100 more rows
```

### 3. Integration Testing
Test full metrics collection:
```bash
# Run simple DELETE with metrics
./run-in-container.sh db-cleanup.sh --method test --delete-limit 100

# Verify log file created
# Verify metrics make sense (duration > 0, rows deleted = 100, etc.)
```

### 4. Concurrent Workload Testing
Test with background traffic:
```bash
# Start traffic
./run-in-container.sh db-traffic.sh &

# Run cleanup with metrics
./run-in-container.sh db-cleanup.sh --method batch

# Verify replication lag captured
# Verify latency impact measured
```

---

## Success Criteria

Phase 4 is successful when:

1. ✅ All helper functions implemented and tested
2. ✅ Metrics snapshot captures all required data
3. ✅ Duration and throughput calculated accurately
4. ✅ Replication lag measured from replica
5. ✅ Table size changes tracked correctly
6. ✅ Binlog growth measured
7. ✅ Query latency impact measurable
8. ✅ Results logged to structured file
9. ✅ Log format is parseable and complete
10. ✅ Can run test cleanup and verify metrics
11. ✅ Ready to instrument actual cleanup methods (Phase 5)
12. ✅ Documentation explains metrics and interpretation

---

## Common Questions

**Q: Why measure replication lag on the replica, not the master?**

**A**: The replica is where lag occurs! The master doesn't have a "lag" metric because it's the source of truth. We need to connect to the replica and query `SHOW REPLICA STATUS` to see how far behind it is.

---

**Q: Why do we need both `TABLE_ROWS` (estimated) and `COUNT(*)` (exact)?**

**A**: 
- `TABLE_ROWS` from `information_schema.TABLES` is an **estimate** (fast but not exact)
- `COUNT(*)` is **exact** but slow on large tables
- We use `COUNT(*)` for before/after comparison (accuracy needed for throughput calculation)
- We can log both for reference

---

**Q: What if cleanup is so fast we can't measure it?**

**A**: Use nanosecond precision timestamps (`date +%s.%N`). Even if cleanup takes 0.001 seconds, we can measure it. For very fast methods (DROP PARTITION), the throughput will be astronomical (millions of rows/sec).

---

**Q: How do we measure query latency without impacting the cleanup?**

**A**: 
- Measure baseline **before** cleanup (10 samples)
- During cleanup, run sample queries every 5-10 seconds (not continuously)
- Measure recovery **after** cleanup (10 samples)
- The latency measurement overhead is minimal

---

**Q: What if the replica isn't configured or accessible?**

**A**: Gracefully degrade:
- Try to connect to replica
- If it fails, log a warning and skip replication metrics
- Continue with other metrics
- Document in results that replication metrics unavailable

---

## Related Documents

- **Detailed Tasks**: `phase4_metrics_tasks.md` - Complete implementation checklist
- **Original Spec**: `implementation_metrics.md` - High-level requirements
- **Phase 3 Summary**: `phase3_implementation_summary.md` - Load simulation (provides concurrent workload)
- **Phase 5 Preview**: `implementation_cleanup_methods.md` - Methods that will use these metrics
- **Metrics Dictionary**: `metrics.md` - Detailed metric definitions

---

**Last Updated**: 2025-11-20  
**Status**: Ready to implement  
**Estimated Effort**: 12-16 hours  
**Next Step**: Begin implementation following `phase4_metrics_tasks.md`
