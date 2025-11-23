# Phase 4 – Metrics & Instrumentation: Task Checklist

This checklist breaks down Phase 4 into concrete, trackable tasks for implementing comprehensive metrics collection during cleanup operations.

---

## Prerequisites

- [x] Phase 1 completed: Database schema created with all four tables
- [x] Phase 2 completed: Data loading implemented and tested
- [x] Phase 3 completed: Background traffic simulation functional
- [x] `.env` in `task01/compose/` defines MySQL connection parameters
- [x] `run-in-container.sh` wrapper available for container execution
- [x] MySQL master-replica replication is healthy and operational
- [x] Understanding of MySQL status variables and performance_schema
- [x] Familiarity with InnoDB metrics and replication monitoring

---

**Phase 4 Status**: ✅ Complete (November 20, 2025)

All tasks below have been implemented and tested successfully.

---

## Phase 4 Tasks – Metrics & Instrumentation Implementation

### 1. MySQL Status Metrics Collection

#### 1.1 InnoDB Row Operations
- [ ] Implement function to capture `Innodb_rows_deleted` before/after cleanup
- [ ] Implement function to capture `Innodb_rows_inserted` during concurrent traffic
- [ ] Implement function to capture `Innodb_rows_updated` during concurrent traffic
- [ ] Implement function to capture `Innodb_rows_read` for query activity
- [ ] Calculate deltas (difference between before/after) for attribution
- [ ] Store raw values in metrics log file

#### 1.2 InnoDB Locking Metrics
- [ ] Implement function to capture `Innodb_row_lock_time` (milliseconds)
- [ ] Implement function to capture `Innodb_row_lock_waits` (count)
- [ ] Implement function to capture `Innodb_row_lock_current_waits` (current)
- [ ] Calculate lock wait time increase during cleanup
- [ ] Log lock contention indicators

#### 1.3 InnoDB Purge Lag (History List Length)
- [ ] Choose collection method:
  - [ ] Option A: Parse `SHOW ENGINE INNODB STATUS\G` output
  - [ ] Option B: Query `information_schema.INNODB_METRICS` for `trx_rseg_history_len`
- [ ] Implement function to extract history list length
- [ ] Capture value before cleanup start
- [ ] Capture value after cleanup end
- [ ] For long-running cleanups: capture periodically (every 10-30 seconds)
- [ ] Log history list length trend data

#### 1.4 InnoDB Buffer Pool Metrics (Optional)
- [ ] Capture `Innodb_buffer_pool_pages_dirty` before/after
- [ ] Capture `Innodb_buffer_pool_wait_free` (buffer pool pressure)
- [ ] Track buffer pool hit ratio changes

### 2. Replication Metrics Collection

#### 2.1 Replica Connection Setup
- [ ] Verify replica connection parameters in .env
- [ ] Test connectivity to replica MySQL instance
- [ ] Verify privileges to run `SHOW REPLICA STATUS` (or `SHOW SLAVE STATUS`)
- [ ] Handle differences between MySQL 8.0+ and 5.7 command syntax

#### 2.2 Replication Lag Measurement
- [ ] Implement function to query `Seconds_Behind_Source` (or `Seconds_Behind_Master`)
- [ ] Capture lag immediately before cleanup start
- [ ] Capture lag immediately after cleanup completion
- [ ] For long-running cleanup: capture lag every 10 seconds during execution
- [ ] Calculate maximum lag during cleanup
- [ ] Calculate average lag during cleanup
- [ ] Store lag time series in metrics log

#### 2.3 Replication Health Monitoring
- [ ] Check `Replica_IO_Running` (or `Slave_IO_Running`) status
- [ ] Check `Replica_SQL_Running` (or `Slave_SQL_Running`) status
- [ ] Alert if replication stops during cleanup
- [ ] Log relay log position and size (optional)
- [ ] Track `Relay_Log_Space` growth

#### 2.4 Replication Velocity (Optional)
- [ ] Calculate relay log application rate (bytes/sec)
- [ ] Measure time to catch up after cleanup completes
- [ ] Compare replication velocity across cleanup methods

### 3. Table Size and Free Space Metrics

#### 3.1 Table Size Queries
- [ ] Implement function to query `information_schema.TABLES`:
  - [ ] Extract `DATA_LENGTH` (data size in bytes)
  - [ ] Extract `INDEX_LENGTH` (index size in bytes)
  - [ ] Extract `DATA_FREE` (free space inside table file)
  - [ ] Extract `TABLE_ROWS` (estimated row count)
- [ ] Query for each test table before cleanup
- [ ] Query for each test table after cleanup
- [ ] Calculate size reduction per method

#### 3.2 Exact Row Counts
- [ ] Implement function for exact row count: `SELECT COUNT(*) FROM table`
- [ ] Capture count before cleanup
- [ ] Capture count after cleanup
- [ ] Calculate `rows_deleted = count_before - count_after`
- [ ] Verify deletion accuracy (correct date range)

#### 3.3 Fragmentation Analysis
- [ ] Calculate fragmentation ratio: `DATA_FREE / (DATA_LENGTH + INDEX_LENGTH)`
- [ ] Compare fragmentation across methods:
  - [ ] DROP PARTITION (should have minimal fragmentation)
  - [ ] TRUNCATE TABLE (fresh table, no fragmentation)
  - [ ] Copy-to-new-table (fresh table, no fragmentation)
  - [ ] Batch DELETE (high fragmentation expected)
- [ ] Log fragmentation metrics per method

#### 3.4 Disk Space Recovery
- [ ] Calculate actual space freed: `(DATA_LENGTH + INDEX_LENGTH)_before - (DATA_LENGTH + INDEX_LENGTH)_after`
- [ ] Compare to expected space from deleted rows
- [ ] Identify methods that don't release space to OS (batch DELETE)
- [ ] Document OPTIMIZE TABLE requirement for batch DELETE

### 4. Binary Log (Binlog) Metrics

#### 4.1 Binlog Size Tracking
- [ ] Implement function to list binlogs: `SHOW BINARY LOGS`
- [ ] Capture binlog list and sizes before cleanup
- [ ] Capture binlog list and sizes after cleanup
- [ ] Calculate binlog growth during cleanup
- [ ] Identify which binlog file was active during cleanup

#### 4.2 Binlog Growth by Method
- [ ] Track total bytes written to binlog per cleanup method
- [ ] Compare binlog sizes:
  - [ ] DROP PARTITION (minimal binlog entry)
  - [ ] TRUNCATE TABLE (small binlog entry)
  - [ ] Copy-to-new-table (large: logs all INSERT + DDL)
  - [ ] Batch DELETE (large: logs all DELETE statements)
- [ ] Calculate binlog growth rate during cleanup (bytes/sec)

#### 4.3 Filesystem Binlog Size (Optional)
- [ ] If filesystem access available, check actual binlog file sizes
- [ ] Compare MySQL reported size vs actual file size
- [ ] Track binlog rotation during cleanup

### 5. Throughput and Performance Metrics

#### 5.1 Delete Throughput (Primary Metric)
- [ ] Capture exact start timestamp (before cleanup SQL execution)
- [ ] Capture exact end timestamp (after cleanup SQL completion)
- [ ] Calculate duration in seconds: `duration = end_ts - start_ts`
- [ ] Calculate total rows deleted (from row counts)
- [ ] Calculate primary metric: `rows_deleted_per_second = rows_deleted / duration`
- [ ] Log throughput for comparison across methods

#### 5.2 Batch-Level Throughput (for DELETE method only)
- [ ] For each DELETE batch:
  - [ ] Record batch start time
  - [ ] Record batch end time
  - [ ] Record rows affected (from ROW_COUNT() or affected_rows)
  - [ ] Calculate batch duration
  - [ ] Calculate batch throughput: `rows_in_batch / batch_duration`
- [ ] Log per-batch metrics to separate file or section
- [ ] Calculate statistics:
  - [ ] Average batch throughput
  - [ ] Minimum/maximum batch throughput
  - [ ] Throughput trend (first vs last batches)

#### 5.3 Concurrent Workload Throughput
- [ ] If db-traffic.sh running, capture its statistics:
  - [ ] INSERT rate before cleanup
  - [ ] INSERT rate during cleanup
  - [ ] INSERT rate after cleanup
  - [ ] Calculate throughput degradation percentage
- [ ] Measure impact on traffic operations per second

### 6. Query Latency Measurement

#### 6.1 Sample Query Execution Time
- [ ] Define representative queries:
  - [ ] SELECT recent data: `SELECT * FROM table WHERE ts >= NOW() - INTERVAL 5 MINUTE LIMIT 10`
  - [ ] UPDATE recent data: `UPDATE table SET data = data + 1 WHERE ts >= NOW() - INTERVAL 10 MINUTE LIMIT 10`
- [ ] Implement timing wrapper:
  - [ ] Capture timestamp before query execution
  - [ ] Execute query
  - [ ] Capture timestamp after query execution
  - [ ] Calculate latency in milliseconds

#### 6.2 Latency Baseline (Before Cleanup)
- [ ] Run sample queries 10 times before cleanup
- [ ] Calculate average latency
- [ ] Calculate p95 latency
- [ ] Store baseline metrics

#### 6.3 Latency During Cleanup
- [ ] Run sample queries every 5-10 seconds during cleanup
- [ ] Log each query execution time with timestamp
- [ ] Track query failures (timeouts, errors)
- [ ] Build latency time series

#### 6.4 Latency After Cleanup
- [ ] Run sample queries 10 times after cleanup completes
- [ ] Calculate average latency
- [ ] Calculate p95 latency
- [ ] Compare to baseline

#### 6.5 Latency Analysis
- [ ] Calculate maximum latency spike during cleanup
- [ ] Calculate average latency increase percentage
- [ ] Identify queries that timed out
- [ ] Compare latency impact across cleanup methods

### 7. Lock Contention and Conflict Metrics

#### 7.1 Lock Wait Statistics
- [ ] Query `performance_schema.table_lock_waits_summary_by_table` (if enabled)
- [ ] Query current locks: `SELECT * FROM performance_schema.data_locks` during cleanup
- [ ] Track number of lock waits during cleanup
- [ ] Identify blocking vs blocked transactions

#### 7.2 Deadlock Detection
- [ ] Monitor for deadlocks during cleanup
- [ ] Parse `SHOW ENGINE INNODB STATUS` for deadlock section
- [ ] Log deadlock occurrences
- [ ] Identify which methods cause deadlocks with concurrent traffic

#### 7.3 Metadata Locks (MDL)
- [ ] Query `performance_schema.metadata_locks` during TRUNCATE/RENAME
- [ ] Measure MDL wait time for concurrent queries
- [ ] Identify tables blocked by DDL operations

### 8. Performance Schema Metrics (Optional)

#### 8.1 Statement Digest Statistics
- [ ] Enable `performance_schema` if not already enabled
- [ ] Query `events_statements_summary_by_digest` before/after cleanup
- [ ] Filter for cleanup-related statements (DELETE, ALTER TABLE, etc.)
- [ ] Extract:
  - [ ] Execution count
  - [ ] Total execution time
  - [ ] Rows affected
  - [ ] Average rows per execution
- [ ] Calculate aggregate throughput from performance_schema

#### 8.2 Table I/O Statistics
- [ ] Query `table_io_waits_summary_by_table` for cleanup tables
- [ ] Track read vs write operations
- [ ] Measure I/O wait time increase

### 9. Metrics Storage and Logging

#### 9.1 Log File Structure
- [ ] Create `task03/results/` directory if not exists
- [ ] Define log filename format: `<method>_<timestamp>_metrics.log` or `.csv`
- [ ] Design log format (choose one):
  - [ ] Option A: CSV format for easy parsing
  - [ ] Option B: JSON format for structured data
  - [ ] Option C: Custom text format with sections

#### 9.2 Metrics Log Content - Summary Section
- [ ] Method metadata:
  - [ ] Method name (partition_drop, truncate, copy, batch_delete_<size>)
  - [ ] Target table name
  - [ ] Start timestamp (ISO 8601 format)
  - [ ] End timestamp
  - [ ] Duration (seconds)
- [ ] Row statistics:
  - [ ] Rows before cleanup
  - [ ] Rows after cleanup
  - [ ] Rows deleted
  - [ ] Expected rows to delete (for validation)
- [ ] Throughput:
  - [ ] rows_deleted_per_second (primary metric)
- [ ] Test configuration:
  - [ ] Concurrent traffic enabled (yes/no)
  - [ ] Traffic rate if enabled (ops/sec)
  - [ ] Workload mix if enabled

#### 9.3 Metrics Log Content - Detailed Sections
- [ ] InnoDB section:
  - [ ] Rows deleted/inserted/updated/read (before/after/delta)
  - [ ] Lock time and lock waits (before/after/delta)
  - [ ] History list length (before/after/max during)
  - [ ] Buffer pool metrics
- [ ] Replication section:
  - [ ] Lag before/after/max/average
  - [ ] Replication status (running/stopped)
  - [ ] Relay log space
- [ ] Table size section:
  - [ ] DATA_LENGTH before/after/delta
  - [ ] INDEX_LENGTH before/after/delta
  - [ ] DATA_FREE before/after
  - [ ] Fragmentation ratio
  - [ ] Space actually freed
- [ ] Binlog section:
  - [ ] Binlog files before/after
  - [ ] Total binlog size growth
  - [ ] Growth rate (bytes/sec)
- [ ] Latency section:
  - [ ] Baseline average/p95
  - [ ] During cleanup average/p95/max
  - [ ] After cleanup average/p95
  - [ ] Query timeout count

#### 9.4 Batch Metrics Log (for batch DELETE only)
- [ ] Create separate or appended section for per-batch data:
  - [ ] batch_id (sequence number)
  - [ ] timestamp
  - [ ] rows_in_batch (affected rows)
  - [ ] batch_duration_sec
  - [ ] batch_throughput (rows/sec)
  - [ ] current_replication_lag_sec (if sampled)
- [ ] Calculate batch statistics:
  - [ ] Total batches executed
  - [ ] Average batch throughput
  - [ ] Batch throughput trend (degradation over time?)

### 10. Metrics Collection Functions (Implementation)

#### 10.1 Helper Functions in db-cleanup.sh
- [ ] `get_timestamp()` - return current timestamp in nanoseconds
- [ ] `get_status_var(var_name)` - query SHOW GLOBAL STATUS
- [ ] `get_innodb_metric(metric_name)` - query information_schema.INNODB_METRICS
- [ ] `get_table_info(db, table)` - query information_schema.TABLES
- [ ] `get_row_count(db, table)` - SELECT COUNT(*) from table
- [ ] `get_replication_lag()` - query SHOW REPLICA STATUS on replica
- [ ] `get_binlog_list()` - SHOW BINARY LOGS and parse output
- [ ] `get_history_list_length()` - parse SHOW ENGINE INNODB STATUS or query INNODB_METRICS
- [ ] `measure_query_latency(query)` - execute query and return execution time

#### 10.2 Metrics Snapshot Function
- [ ] `capture_metrics_snapshot(label)` - capture all metrics at a point in time:
  - [ ] InnoDB status variables
  - [ ] Table sizes and row counts
  - [ ] Replication status
  - [ ] Binlog state
  - [ ] Timestamp and label
  - [ ] Return or store snapshot data structure

#### 10.3 Metrics Diff Function
- [ ] `calculate_metrics_diff(snapshot_before, snapshot_after)` - compute deltas:
  - [ ] Row operation differences
  - [ ] Lock time differences
  - [ ] Size differences
  - [ ] Binlog growth
  - [ ] Replication lag change

#### 10.4 Metrics Logging Function
- [ ] `log_metrics(method_name, snapshot_before, snapshot_after, duration)`:
  - [ ] Create or append to log file
  - [ ] Write summary section
  - [ ] Write detailed metrics sections
  - [ ] Format timestamps and numbers
  - [ ] Close log file

### 11. Integration with Cleanup Methods

#### 11.1 Instrumentation Wrapper
- [ ] For each cleanup method, wrap execution:
  ```bash
  # Before
  snapshot_before=$(capture_metrics_snapshot "before_cleanup")
  start_ts=$(get_timestamp)
  
  # Execute cleanup
  run_cleanup_method
  
  # After
  end_ts=$(get_timestamp)
  snapshot_after=$(capture_metrics_snapshot "after_cleanup")
  
  # Log
  duration=$(calculate_duration $start_ts $end_ts)
  log_metrics "method_name" "$snapshot_before" "$snapshot_after" "$duration"
  ```

#### 11.2 Periodic Metrics During Cleanup (Long-Running)
- [ ] For methods that take >30 seconds:
  - [ ] Start background metrics collection loop
  - [ ] Every 10 seconds:
    - [ ] Capture replication lag
    - [ ] Capture history list length
    - [ ] Optionally measure query latency
  - [ ] Store time series data
  - [ ] Stop loop when cleanup completes

#### 11.3 Batch DELETE Instrumentation
- [ ] Add per-batch metrics collection to batch delete loop:
  ```bash
  batch_id=0
  while true; do
    batch_start=$(get_timestamp)
    result=$(DELETE FROM table WHERE ... LIMIT batch_size)
    batch_end=$(get_timestamp)
    rows_affected=$(get_affected_rows)
    
    log_batch_metrics $batch_id $rows_affected $batch_start $batch_end
    
    [[ $rows_affected -eq 0 ]] && break
    batch_id=$((batch_id + 1))
  done
  ```

### 12. Results Directory and File Organization

#### 12.1 Directory Structure
- [ ] Create `task03/results/` directory
- [ ] Create subdirectories (optional):
  - [ ] `results/partition/` for partition drop results
  - [ ] `results/truncate/` for truncate results
  - [ ] `results/copy/` for copy method results
  - [ ] `results/batch/` for batch delete results
- [ ] Add .gitignore for results (optional: don't commit large logs)

#### 12.2 Filename Convention
- [ ] Define naming pattern: `<method>_<date>_<time>_metrics.{csv|json|log}`
- [ ] Example: `batch_delete_5000_20251120_153045_metrics.csv`
- [ ] Include method parameters in filename (e.g., batch size)

#### 12.3 Summary Report File
- [ ] Create consolidated summary: `results/summary.csv`
- [ ] One row per test run with key metrics:
  - [ ] timestamp, method, table, rows_deleted, duration, throughput
  - [ ] replication_lag_max, space_freed, binlog_growth
- [ ] Easy to load into spreadsheet for comparison

### 13. Validation and Testing

#### 13.1 Metrics Collection Testing
- [ ] Test each helper function independently:
  - [ ] Verify get_status_var returns correct value
  - [ ] Verify get_table_info parses information_schema correctly
  - [ ] Verify get_replication_lag connects to replica
  - [ ] Verify timestamp functions return nanosecond precision
- [ ] Test snapshot capture with known table state
- [ ] Test metrics diff calculation accuracy

#### 13.2 Integration Testing
- [ ] Run simple cleanup (DELETE 100 rows) with full metrics:
  - [ ] Verify log file created
  - [ ] Verify all metrics sections present
  - [ ] Verify calculations correct (rows deleted, duration, throughput)
- [ ] Run cleanup with concurrent traffic:
  - [ ] Start db-traffic.sh
  - [ ] Run cleanup with metrics
  - [ ] Verify replication lag captured
  - [ ] Verify latency measurements recorded
  - [ ] Stop traffic

#### 13.3 All Methods Testing
- [ ] Run each cleanup method once with metrics enabled:
  - [ ] DROP PARTITION
  - [ ] TRUNCATE TABLE
  - [ ] Copy-to-new-table
  - [ ] Batch DELETE (small batch, e.g., 1000)
- [ ] Verify metrics differences make sense:
  - [ ] DROP PARTITION: instant, minimal binlog
  - [ ] TRUNCATE: fast, small binlog
  - [ ] Copy: slower, large binlog
  - [ ] Batch DELETE: slowest, large binlog, per-batch logs

### 14. Documentation

#### 14.1 Metrics Documentation
- [ ] Document all collected metrics in `metrics.md`:
  - [ ] Metric name
  - [ ] Source (status variable, information_schema, etc.)
  - [ ] Unit (rows/sec, seconds, bytes, etc.)
  - [ ] Interpretation
  - [ ] Comparison across methods
- [ ] Create metrics dictionary/glossary

#### 14.2 Log Format Documentation
- [ ] Document log file format and structure
- [ ] Provide example log files for each method
- [ ] Explain how to parse and analyze logs
- [ ] Provide example queries/scripts to extract metrics

#### 14.3 Usage Documentation
- [ ] Update task03/README.md with metrics collection info (deferred to Phase 7)
- [ ] Document how to enable/disable specific metrics
- [ ] Document how to interpret results
- [ ] Provide troubleshooting guide for metrics collection

---

## Definition of Done (DoD)

- [ ] All MySQL status metrics (InnoDB rows, locks, history list) collected before/after cleanup
- [ ] Replication metrics (lag, status) collected from replica before/after cleanup
- [ ] Table size metrics (DATA_LENGTH, INDEX_LENGTH, DATA_FREE, row counts) collected before/after
- [ ] Binlog size and growth tracked for each cleanup method
- [ ] Delete throughput calculated: `rows_deleted_per_second` for all methods
- [ ] For batch DELETE: per-batch metrics logged with throughput trend
- [ ] Query latency measured before, during, and after cleanup
- [ ] All metrics logged to structured file in `task03/results/`
- [ ] Helper functions implemented in db-cleanup.sh for metrics collection
- [ ] Metrics collection tested with all four cleanup methods
- [ ] Results directory structure created and documented
- [ ] Summary metrics file can be generated for comparison
- [ ] Concurrent traffic impact on metrics validated (run with db-traffic.sh)
- [ ] Documentation created explaining metrics and log format
- [ ] Phase 4 implementation summary document created

---

## Notes and Considerations

### Metrics Collection Performance Impact
- Collecting metrics has overhead; minimize queries during cleanup execution
- Use snapshots before/after rather than continuous polling (except for long-running cleanups)
- For replication lag time series, 10-second intervals are sufficient

### Replica Connection Handling
- Ensure replica connection doesn't interfere with cleanup performance
- Use separate connection to replica (not master)
- Handle replica connection failures gracefully

### Precision and Accuracy
- Use nanosecond timestamps (`date +%s.%N`) for accurate duration measurement
- Take multiple samples for latency measurement (variance can be high)
- Replication lag can fluctuate; track maximum and average

### Comparison Fairness
- Always run from same initial state (same row count, same data distribution)
- Run all methods with and without concurrent traffic for fair comparison
- Consider running each method multiple times and averaging results

### Storage and Retention
- Metrics logs can grow large (especially batch DELETE with per-batch data)
- Consider log rotation or cleanup policy
- Compress old results or store in database for analysis

### Data Privacy
- Don't log actual table data (only metadata and counts)
- Be careful with connection strings in logs (don't log passwords)

---

## Integration Points

### Phase 3 (Load Simulation)
- db-traffic.sh provides concurrent workload for metrics testing
- Traffic statistics complement cleanup metrics
- Combined analysis shows real-world impact

### Phase 5 (Cleanup Methods)
- Each cleanup method will be instrumented with Phase 4 metrics
- Metrics guide method selection and optimization
- Batch size tuning based on throughput metrics

### Phase 6 (Orchestration)
- db-cleanup.sh will use Phase 4 metrics collection functions
- Orchestration script will manage metrics for all methods
- Automated comparison report generation

### Phase 7 (Documentation)
- Metrics guide final recommendations
- Results included in project documentation
- Usage examples show how to interpret metrics

---

## Success Metrics for Phase 4

Phase 4 is successful when:

1. All key metrics can be collected automatically
2. Metrics accurately reflect cleanup performance
3. Comparison between methods is possible
4. Replication impact is measurable
5. Concurrent workload impact is measurable
6. Results are logged in parseable format
7. No significant performance overhead from metrics collection
8. Documentation enables understanding and interpretation
9. Ready to support Phase 5 and 6 implementation
