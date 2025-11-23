# Phase 3 Implementation Plan – Load Simulation

## Overview

Phase 3 implements the background workload simulator (`db-traffic.sh`) that generates realistic database traffic while cleanup operations are running. This simulates production-like conditions where cleanup must occur while the application continues to insert, read, and update data.

---

## Goals

1. **Realistic Workload**: Emulate continuous application activity during cleanup tests
2. **Configurable Load**: Support various traffic patterns and intensities
3. **Concurrent Safety**: Run alongside cleanup operations without causing failures
4. **Measurable Impact**: Enable measurement of cleanup impact on application latency and throughput
5. **Flexible Testing**: Support different workload mixes (write-heavy, read-heavy, balanced)

---

## Deliverable: `db-traffic.sh`

### Primary Responsibilities

1. Generate continuous INSERT operations with current timestamps
2. Execute SELECT queries to measure read latency during cleanup
3. Perform UPDATE operations to test lock contention
4. Run at configurable rate (operations per second)
5. Target all four test tables or a configurable subset
6. Report statistics periodically
7. Handle graceful shutdown on interrupt signals

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      db-traffic.sh                          │
├─────────────────────────────────────────────────────────────┤
│  Initialization                                             │
│  • Parse CLI arguments                                      │
│  • Load environment (.env or variables)                     │
│  • Validate database connectivity                           │
│  • Calculate operation timing (from target ops/sec)         │
├─────────────────────────────────────────────────────────────┤
│  Main Loop (until interrupted)                              │
│  ┌───────────────────────────────────────────────────────┐ │
│  │ 1. Select operation type based on workload mix        │ │
│  │    (write: INSERT, read: SELECT, update: UPDATE)      │ │
│  │                                                        │ │
│  │ 2. Generate appropriate SQL statement                 │ │
│  │    • INSERT: current timestamp + random data          │ │
│  │    • SELECT: recent data (last 5 min, 1 hour)         │ │
│  │    • UPDATE: modify recent records                    │ │
│  │                                                        │ │
│  │ 3. Execute SQL against target table(s)                │ │
│  │                                                        │ │
│  │ 4. Track statistics (success/failure counts)          │ │
│  │                                                        │ │
│  │ 5. Sleep for calculated interval (rate limiting)      │ │
│  │                                                        │ │
│  │ 6. Every N seconds: print statistics report           │ │
│  └───────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│  Signal Handlers                                            │
│  • SIGINT/SIGTERM → graceful shutdown                       │
│  • Print final statistics summary                           │
│  • Exit cleanly                                             │
└─────────────────────────────────────────────────────────────┘
```

### Command-Line Interface

```bash
./db-traffic.sh [OPTIONS]

Options:
  --rows-per-second N          Target operations per second (default: 10)
  --tables TABLE1,TABLE2,...   Comma-separated table list (default: all four)
  --workload-mix W:R:U         Ratio of write:read:update (default: 70:20:10)
  --duration SECONDS           Run for fixed duration (default: infinite)
  --verbose                    Enable detailed logging
  -h, --help                   Show usage information

Examples:
  # Default: 10 ops/sec, all tables, 70:20:10 mix
  ./run-in-container.sh db-traffic.sh

  # High write load, 50 ops/sec
  ./run-in-container.sh db-traffic.sh --rows-per-second 50 --workload-mix 90:10:0

  # Read-heavy workload on specific tables
  ./run-in-container.sh db-traffic.sh --tables cleanup_batch,cleanup_copy --workload-mix 20:70:10

  # Run for 5 minutes then exit
  ./run-in-container.sh db-traffic.sh --duration 300

  # Background execution during cleanup
  ./run-in-container.sh db-traffic.sh &
  TRAFFIC_PID=$!
  ./run-in-container.sh db-cleanup.sh --method batch
  kill $TRAFFIC_PID
```

---

## Workload Characteristics

### 1. Write Operations (INSERTs)

**Purpose**: Simulate continuous data ingestion

**Query Pattern**:
```sql
INSERT INTO <table> (ts, name, data) VALUES
  (NOW(), '<random_name>', <random_data>),
  (NOW(), '<random_name>', <random_data>),
  ...
  (NOW(), '<random_name>', <random_data>);
```

**Characteristics**:
- Batch size: 10 rows per INSERT (configurable)
- Timestamp: Always `NOW()` (represents real-time data)
- Name: Random 10-character string (A-Z)
- Data: Random integer (0 to 10,000,000)
- Target: Round-robin across selected tables

**Impact on Tests**:
- Increases table size during cleanup
- Tests cleanup behavior with concurrent writes
- Measures replication lag from ongoing inserts + cleanup
- Validates no data loss from cleanup operations

### 2. Read Operations (SELECTs)

**Purpose**: Measure query latency impact during cleanup

**Query Patterns**:

1. **Recent Data Query** (most common):
```sql
SELECT * FROM <table>
WHERE ts >= NOW() - INTERVAL 5 MINUTE
ORDER BY ts DESC
LIMIT 10;
```

2. **Time Range Query**:
```sql
SELECT * FROM <table>
WHERE ts BETWEEN '<random_start>' AND '<random_end>'
LIMIT 100;
```

3. **Aggregate Query**:
```sql
SELECT COUNT(*), AVG(data), MIN(ts), MAX(ts)
FROM <table>
WHERE ts >= NOW() - INTERVAL 1 HOUR;
```

**Characteristics**:
- Use index-optimized queries (ts column is indexed)
- Focus on recent data (last 5 min to 1 hour)
- Small result sets (10-100 rows typical)
- Mix of point queries and range scans

**Impact on Tests**:
- Reveals table-level lock contention during cleanup
- Measures latency increase from cleanup methods
- Tests MDL (metadata lock) behavior during TRUNCATE/RENAME
- Validates index performance during DELETE operations

### 3. Update Operations (UPDATEs)

**Purpose**: Test lock contention and conflict handling

**Query Patterns**:

1. **ID Range Update**:
```sql
UPDATE <table>
SET data = data + 1
WHERE id BETWEEN <recent_id_start> AND <recent_id_start + 10>;
```

2. **Time-Based Update**:
```sql
UPDATE <table>
SET name = '<random_name>'
WHERE ts >= NOW() - INTERVAL 10 MINUTE
LIMIT 10;
```

**Characteristics**:
- Small batch sizes (10 rows)
- Target recent data only
- Simple updates (avoid complex logic)
- Track rows affected

**Impact on Tests**:
- Tests row-level locking during batch DELETE
- Reveals deadlock potential
- Measures update throughput degradation
- Shows replication lag from UPDATE + DELETE combination

### 4. Workload Mix Ratios

**Default Mix: 70:20:10 (Write:Read:Update)**
- Simulates write-heavy OLTP application
- Most operations are inserts (data ingestion)
- Regular reads for application queries
- Occasional updates for data corrections

**Read-Heavy Mix: 20:70:10**
- Simulates reporting/analytics workload
- Focus on query latency measurement
- Tests SELECT performance during cleanup

**Write-Only Mix: 100:0:0**
- Pure ingestion test
- Maximum replication lag scenario
- Fastest table growth rate

**Balanced Mix: 50:30:20**
- Simulates complex application
- Tests all concurrency aspects
- More realistic lock contention

---

## Rate Limiting Strategy

### Target Operations Per Second

The script must achieve consistent operation rate regardless of:
- Query execution time
- Database response time
- Network latency
- System load

### Implementation Approach

1. **Calculate Inter-Operation Delay**:
```bash
target_ops_per_sec=10
delay=$(awk "BEGIN {print 1.0 / $target_ops_per_sec}")
# delay = 0.1 seconds for 10 ops/sec
```

2. **Track Actual Execution Time**:
```bash
start_time=$(date +%s.%N)
# Execute operation
end_time=$(date +%s.%N)
exec_time=$(awk "BEGIN {print $end_time - $start_time}")
```

3. **Adjust Sleep Duration**:
```bash
sleep_time=$(awk "BEGIN {print $delay - $exec_time}")
if (( $(awk "BEGIN {print ($sleep_time > 0)}") )); then
  sleep $sleep_time
fi
```

4. **Handle Overload**:
- If execution time > target delay, skip sleep
- Log warning if sustained overload detected
- Optionally reduce target rate automatically

### Rate Ranges

- **Low Rate (1-10 ops/sec)**: Stable, minimal resource usage
- **Medium Rate (10-50 ops/sec)**: Typical test scenario
- **High Rate (50-100 ops/sec)**: Stress test, may require batching
- **Very High Rate (>100 ops/sec)**: Consider parallel workers or compiled tools

---

## Statistics and Reporting

### Periodic Reports (Every 10 Seconds)

```
[2025-11-20 15:30:00] Stats: INSERTs=70 (7.0/s), SELECTs=20 (2.0/s), UPDATEs=10 (1.0/s), Errors=0
[2025-11-20 15:30:10] Stats: INSERTs=65 (6.5/s), SELECTs=23 (2.3/s), UPDATEs=12 (1.2/s), Errors=0
[2025-11-20 15:30:20] Stats: INSERTs=72 (7.2/s), SELECTs=18 (1.8/s), UPDATEs=10 (1.0/s), Errors=0
```

### Final Summary (On Exit)

```
=== Traffic Simulation Summary ===
Runtime:           125 seconds
Total Operations:  1250
  - INSERTs:       875 (70.0%)
  - SELECTs:       250 (20.0%)
  - UPDATEs:       125 (10.0%)
Errors:            0
Average Rate:      10.0 ops/sec
Tables Affected:   cleanup_partitioned, cleanup_truncate, cleanup_copy, cleanup_batch
```

### Tracked Metrics

1. **Operation Counts** (by type)
2. **Success vs Error Counts**
3. **Actual Rate** (ops/sec achieved)
4. **Runtime Duration**
5. **Per-Table Statistics** (optional)
6. **Query Latency** (optional, if --verbose)

---

## Integration with Cleanup Testing

### Typical Test Workflow

1. **Setup**:
```bash
# Ensure tables are populated
./run-in-container.sh db-load.sh --rows 100000

# Verify initial state
./run-in-container.sh mysql -e "SELECT COUNT(*) FROM cleanup_bench.cleanup_batch"
```

2. **Start Background Traffic**:
```bash
# Start traffic simulator in background
./run-in-container.sh db-traffic.sh --rows-per-second 20 &
TRAFFIC_PID=$!

# Give it a few seconds to start
sleep 5
```

3. **Run Cleanup Test**:
```bash
# Execute cleanup with traffic running
./run-in-container.sh db-cleanup.sh --method batch --batch-size 5000
```

4. **Monitor Concurrency**:
```bash
# In another terminal, watch replication lag
while true; do
  ./run-in-container.sh mysql -e "SHOW REPLICA STATUS\G" | grep Seconds_Behind
  sleep 2
done
```

5. **Stop Traffic**:
```bash
# Stop traffic simulator
kill $TRAFFIC_PID

# Or use container command
docker exec -it db_master pkill -SIGTERM -f db-traffic.sh
```

6. **Analyze Results**:
```bash
# Check final state
./run-in-container.sh mysql -e "SELECT COUNT(*) FROM cleanup_bench.cleanup_batch"

# Review cleanup metrics (from Phase 4)
cat task03/results/batch_delete_*.log
```

### Concurrency Scenarios to Test

1. **No Traffic** (baseline):
   - Run cleanup without db-traffic.sh
   - Establishes baseline performance

2. **Low Concurrent Load**:
   - db-traffic.sh at 5-10 ops/sec
   - Minimal contention expected

3. **Moderate Concurrent Load**:
   - db-traffic.sh at 20-50 ops/sec
   - Realistic production simulation

4. **High Concurrent Load**:
   - db-traffic.sh at 100+ ops/sec
   - Stress test scenario

5. **Write-Heavy Load**:
   - 90:10:0 mix during cleanup
   - Maximum replication lag test

6. **Read-Heavy Load**:
   - 10:80:10 mix during cleanup
   - Query latency impact measurement

---

## Error Handling and Resilience

### Expected Errors

1. **Lock Timeouts**:
   - SELECTs may timeout during TRUNCATE TABLE
   - UPDATEs may conflict with batch DELETE
   - **Handling**: Log error, continue with next operation

2. **Deadlocks**:
   - Rare but possible with concurrent UPDATEs/DELETEs
   - **Handling**: Retry operation once, then skip

3. **Connection Failures**:
   - Network issues, MySQL restart
   - **Handling**: Attempt reconnection (up to 3 times), then exit

4. **Partition Errors**:
   - INSERT to dropped partition
   - **Handling**: Specific to partitioned table, log and continue

### Resilience Features

- **Error Counter**: Track but don't stop on individual failures
- **Error Threshold**: Exit if error rate exceeds 10% of operations
- **Reconnection Logic**: Attempt reconnect on connection loss
- **Graceful Degradation**: Reduce rate if sustained overload detected

---

## Performance Considerations

### Script Performance

**Target**: Script overhead < 5% of operation time

**Optimizations**:
1. **Batch INSERTs**: 10 rows per statement (not 1)
2. **Minimize Subshells**: Use bash built-ins where possible
3. **Reduce Logging**: Avoid logging every operation
4. **Persistent Connection**: Reuse MySQL connection (consider using mysql --batch mode)
5. **Efficient RNG**: Use bash $RANDOM (fast) instead of /dev/urandom

### Database Performance

**Expected Resource Usage**:
- **CPU**: Minimal on database server (<5% for 50 ops/sec)
- **Memory**: Negligible (small transactions)
- **Disk I/O**: Proportional to insert rate
- **Network**: ~1-5 KB per operation

**Scaling Limits**:
- **Single Script**: Up to 100 ops/sec
- **Multiple Scripts**: Parallel instances for higher load
- **Alternative Tools**: Use sysbench/mysqlslap for >1000 ops/sec

---

## Testing and Validation Plan

### Unit Tests (Script Components)

1. **Argument Parsing**:
   - Test all CLI options
   - Test invalid arguments (should show error)
   - Test help output

2. **Rate Calculation**:
   - Verify delay calculation accuracy
   - Test with various rates (1, 10, 50, 100 ops/sec)

3. **SQL Generation**:
   - Verify INSERT syntax correctness
   - Verify SELECT query validity
   - Verify UPDATE query validity

4. **Statistics Tracking**:
   - Verify counters increment correctly
   - Verify rate calculation accuracy

### Integration Tests

1. **Basic Functionality**:
```bash
# Test runs for 30 seconds without error
timeout 30 ./run-in-container.sh db-traffic.sh --rows-per-second 5
```

2. **Rate Accuracy**:
```bash
# Run for 10 seconds at 10 ops/sec, expect ~100 operations
./run-in-container.sh db-traffic.sh --rows-per-second 10 --duration 10
# Check database: should have ~100 new rows
```

3. **Concurrent Cleanup**:
```bash
# Start traffic, run DELETE, verify no errors
./run-in-container.sh db-traffic.sh &
TRAFFIC_PID=$!
sleep 5
./run-in-container.sh mysql -e "DELETE FROM cleanup_bench.cleanup_batch WHERE ts < NOW() - INTERVAL 10 DAY LIMIT 1000"
kill $TRAFFIC_PID
```

4. **Signal Handling**:
```bash
# Start script, send SIGINT, verify clean exit
./run-in-container.sh db-traffic.sh &
TRAFFIC_PID=$!
sleep 5
kill -SIGINT $TRAFFIC_PID
wait $TRAFFIC_PID
# Should exit with status 0
```

5. **Different Workload Mixes**:
```bash
# Test write-only
./run-in-container.sh db-traffic.sh --workload-mix 100:0:0 --duration 10

# Test read-heavy
./run-in-container.sh db-traffic.sh --workload-mix 20:70:10 --duration 10
```

### Validation Criteria

- [ ] Script runs continuously for 5+ minutes without errors
- [ ] Actual operation rate within 10% of target rate
- [ ] Statistics reports accurate counts
- [ ] Graceful shutdown on Ctrl+C
- [ ] No memory leaks (stable memory usage over time)
- [ ] Concurrent execution with cleanup works
- [ ] All workload mixes execute correctly
- [ ] Error handling prevents script crashes

---

## Dependencies and Prerequisites

### Required Tools

- `bash` (version 4+)
- `mysql` client
- `awk` (for floating-point math)
- `date` (with nanosecond precision: `date +%s.%N`)

### MySQL Configuration

- `max_connections`: Ensure sufficient connections (script uses 1-2)
- `connect_timeout`: Should allow quick reconnection
- `lock_wait_timeout`: Reasonable value (10-30 seconds) to avoid hung queries

### Environment Variables (from .env)

- `DB_MASTER_HOST`
- `DB_MASTER_PORT`
- `DB_MASTER_USER`
- `DB_MASTER_PASS`
- `DB_NAME` (cleanup_bench)

---

## Future Enhancements (Optional)

1. **Latency Measurement**:
   - Measure and log query execution time
   - Report percentiles (p50, p95, p99)
   - Compare latency before/during/after cleanup

2. **Multiple Workers**:
   - Spawn multiple parallel processes
   - Aggregate statistics from all workers
   - Useful for very high load scenarios

3. **Realistic Data Patterns**:
   - Time-based patterns (higher load during "business hours")
   - Seasonal variations
   - Burst traffic patterns

4. **Advanced Workloads**:
   - Multi-table JOINs
   - Subqueries
   - Stored procedure calls
   - Transaction-based operations

5. **Monitoring Integration**:
   - Export metrics to Prometheus
   - Send statistics to time-series database
   - Real-time dashboard

6. **Configuration File**:
   - Support YAML/JSON config for complex scenarios
   - Predefined workload profiles

---

## Success Criteria

Phase 3 is complete when:

1. ✅ `db-traffic.sh` script created and executable
2. ✅ Script accepts all planned CLI arguments
3. ✅ Script generates INSERT, SELECT, UPDATE operations
4. ✅ Rate limiting achieves target ops/sec accurately
5. ✅ Workload mix ratios implemented correctly
6. ✅ Statistics reporting works (periodic and final)
7. ✅ Graceful shutdown on signals
8. ✅ Integration with container environment (run-in-container.sh)
9. ✅ Concurrent execution with cleanup validated
10. ✅ All test scenarios pass
11. ✅ Phase 3 implementation summary created
12. ✅ Ready to support Phase 4 (metrics) and Phase 5/6 (cleanup tests)

---

## Timeline Estimate

- **Design and Planning**: 1-2 hours
- **Core Implementation**: 4-6 hours
  - Argument parsing, environment setup: 1 hour
  - SQL generation and execution: 2 hours
  - Rate limiting and statistics: 1-2 hours
  - Signal handling and cleanup: 1 hour
- **Testing and Debugging**: 2-3 hours
- **Documentation**: 1 hour
- **Total**: 8-12 hours

---

## References

- Phase 1: Environment and schema (completed)
- Phase 2: Data loading (completed)
- Phase 4: Metrics collection (depends on Phase 3)
- Phase 5: Cleanup methods (will use Phase 3 for concurrency testing)
- `implementation_load_simulation.md`: Original requirements
