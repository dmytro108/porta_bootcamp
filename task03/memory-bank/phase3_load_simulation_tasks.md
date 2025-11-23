# Phase 3 – Load Simulation: Task Checklist

This checklist breaks down Phase 3 into concrete, trackable tasks for implementing background workload simulation.

---

## Prerequisites

- [x] Phase 1 completed: Database schema created with all four tables
- [x] Phase 2 completed: `db-load.sh` functional and tables populated with test data
- [x] `.env` in `task01/compose/` defines MySQL connection parameters
- [x] `run-in-container.sh` wrapper available for container execution
- [x] MySQL master-replica replication is healthy and operational

---

## Phase 3 Tasks – Load Simulation Implementation

### 1. Requirements Analysis and Design

- [x] Review cleanup methods to understand concurrency requirements
- [x] Define target workload characteristics:
  - [x] Write rate (INSERT operations per second)
  - [x] Read rate (SELECT queries per second)
  - [x] Update rate (UPDATE operations per second)
- [x] Determine workload mix ratios (e.g., 70% writes, 20% reads, 10% updates)
- [x] Design query patterns that represent realistic application behavior
- [x] Decide on configurable parameters (rows per second, table selection, operation mix)

### 2. Script Skeleton – `db-traffic.sh`

- [x] Create `task03/db-traffic.sh` file with executable permissions
- [x] Add shebang and set bash strict mode (`set -euo pipefail`)
- [x] Implement environment variable loading:
  - [x] Support direct environment variables (from run-in-container.sh)
  - [x] Fall back to sourcing .env file if needed
  - [x] Validate required variables (DB connection params, database name)
- [x] Implement CLI argument parsing:
  - [x] `--rows-per-second N` (insertion rate, default: 10)
  - [x] `--tables TABLE1,TABLE2,...` (target tables, default: all four)
  - [x] `--workload-mix write:read:update` (e.g., "70:20:10")
  - [x] `--duration SECONDS` (optional: run for fixed duration vs infinite)
  - [x] `--verbose` (detailed logging)
  - [x] `-h, --help` (usage information)
- [x] Add usage/help function with examples

### 3. Database Connection and Validation

- [x] Implement MySQL connection helper function
- [x] Test database connectivity on startup
- [x] Verify that target database exists
- [x] Verify that all specified tables exist
- [x] Display initial configuration summary (workload parameters, target tables)

### 4. Data Generation for Inserts

- [x] Implement function to generate random `name` (10-character string A-Z)
- [x] Implement function to generate random `data` (integer 0-10,000,000)
- [x] Use current timestamp (`NOW()`) for `ts` field
- [x] Create multi-row INSERT statement builder (batch inserts for efficiency)
- [x] Decide batch size for inserts (e.g., 10 rows per INSERT statement)

### 5. Write Workload Implementation

- [x] Implement continuous INSERT loop
- [x] Generate INSERT statements with current timestamp
- [x] Execute INSERTs against all selected tables in round-robin fashion
- [x] Track number of inserts performed
- [x] Implement rate limiting to achieve target rows-per-second:
  - [x] Calculate sleep interval based on desired rate
  - [x] Use `sleep` or `usleep` for timing control
- [x] Handle INSERT errors gracefully (log but continue)
- [x] Count successful vs failed inserts

### 6. Read Workload Implementation

- [x] Design representative SELECT queries:
  - [x] Recent data: `SELECT * FROM table WHERE ts >= NOW() - INTERVAL 5 MINUTE ORDER BY ts DESC LIMIT 10`
  - [x] Random range: `SELECT * FROM table WHERE ts BETWEEN <random_start> AND <random_end> LIMIT 100`
  - [x] Aggregate query: `SELECT COUNT(*), AVG(data) FROM table WHERE ts >= NOW() - INTERVAL 1 HOUR`
- [x] Implement SELECT query generator with random parameters
- [x] Execute SELECT queries against selected tables
- [x] Measure query execution time (optional: for latency tracking) - NOT IMPLEMENTED (deferred to Phase 4)
- [x] Track number of reads performed

### 7. Update Workload Implementation

- [x] Design UPDATE queries for recent data:
  - [x] Update by ID range: `UPDATE table SET data = data + 1 WHERE id BETWEEN <id1> AND <id2>`
  - [x] Update by timestamp: `UPDATE table SET name = <random> WHERE ts >= NOW() - INTERVAL 10 MINUTE LIMIT 10`
- [x] Implement UPDATE query generator
- [x] Execute UPDATEs against selected tables
- [x] Track number of updates and rows affected
- [x] Handle update conflicts/locks gracefully

### 8. Workload Orchestration

- [x] Implement main loop that runs until interrupted (SIGINT/SIGTERM)
- [x] Distribute operations based on workload mix:
  - [x] Calculate operation probabilities from mix ratios
  - [x] Randomly select operation type based on probabilities
  - [x] Execute corresponding operation (INSERT/SELECT/UPDATE)
- [x] Implement overall rate limiting to achieve target operations per second
- [x] Track operation counts by type
- [x] Calculate and maintain target inter-operation delays

### 9. Signal Handling and Graceful Shutdown

- [x] Register signal handlers for SIGINT (Ctrl+C) and SIGTERM
- [x] Implement cleanup function:
  - [x] Print summary statistics on exit
  - [x] Close database connections cleanly
  - [x] Log final operation counts
- [x] Ensure script exits cleanly without orphaned processes

### 10. Logging and Statistics

- [x] Implement periodic statistics reporting (every N seconds):
  - [x] Current timestamp
  - [x] Operations performed since last report (by type)
  - [x] Current operation rate (ops/sec)
  - [x] Total operations since start
- [x] Log to stdout with timestamps
- [ ] Optional: Write detailed operation log to file - NOT IMPLEMENTED (deferred)
- [x] Track and report:
  - [x] Total inserts, reads, updates
  - [x] Failed operations (errors)
  - [x] Runtime duration

### 11. Performance Optimization

- [x] Use batched operations where possible (multi-row INSERTs)
- [x] Minimize shell overhead (avoid excessive process spawning)
- [ ] Consider using connection pooling or persistent connections - NOT IMPLEMENTED (using simple mysql exec)
- [x] Implement efficient rate limiting (avoid busy-waiting)
- [ ] Profile script to identify bottlenecks - NOT NEEDED (performance is adequate)

### 12. Testing and Validation

- [x] Test with single table, low rate (e.g., 1 row/sec)
- [x] Test with all four tables, moderate rate (e.g., 10 rows/sec)
- [x] Test with high rate to verify rate limiting works (e.g., 100 rows/sec)
- [x] Test different workload mixes (write-only, read-only, mixed)
- [x] Test duration-limited mode vs continuous mode
- [x] Verify graceful shutdown on Ctrl+C
- [x] Verify statistics reporting accuracy
- [ ] Test concurrent execution with cleanup operations: **Note: Deferred to Phase 5/6 integration testing**
  - [ ] Start db-traffic.sh in background
  - [ ] Run simple cleanup test (e.g., DELETE LIMIT 100)
  - [ ] Verify both continue running without errors
  - [ ] Check that traffic continues during cleanup

### 13. Integration with Container Environment

- [x] Test execution via `run-in-container.sh`
- [x] Verify environment variables passed correctly
- [x] Test running in background: `run-in-container.sh db-traffic.sh &`
- [x] Verify signal handling works in container environment
- [x] Document how to start, monitor, and stop the traffic simulator

### 14. Documentation

- [x] Add comments explaining key functions and logic
- [x] Document all CLI options in help text
- [x] Create usage examples in script header
- [x] Document expected behavior and performance characteristics
- [ ] Add troubleshooting section for common issues **Note: Deferred to Phase 7 (main README)**
- [ ] Update task03 main README **Note: Deferred to Phase 7 (Documentation)**

---

## Definition of Done (DoD)

- [x] `task03/db-traffic.sh` exists and is executable
- [x] Script sources environment correctly (via variables or .env file)
- [x] Script accepts all planned CLI arguments and validates them
- [x] Running `./run-in-container.sh db-traffic.sh` starts background load simulation
- [x] Script generates continuous INSERT traffic at configurable rate
- [x] Script optionally generates SELECT and UPDATE queries based on workload mix
- [x] Rate limiting works correctly (achieves target ops/sec within 10% tolerance)
- [x] Script handles Ctrl+C gracefully and prints statistics summary
- [x] Script runs indefinitely without memory leaks or performance degradation
- [x] Statistics are logged periodically (e.g., every 10 seconds)
- [x] Script can target all four tables or a subset as specified
- [ ] Concurrent execution with cleanup scripts works without conflicts **Note: Deferred to Phase 5/6 integration testing**
- [x] Script exits cleanly with status code 0 on normal shutdown
- [x] Help text explains all options and provides usage examples
- [x] Script has been tested at various load levels (1, 10, 50, 100 ops/sec)
- [x] Phase 3 implementation summary document created

---

## Notes and Considerations

### Rate Limiting Strategy
- For precise rate control, calculate target inter-operation delay: `delay = 1.0 / ops_per_second`
- Use `sleep` with fractional seconds (e.g., `sleep 0.1` for 10 ops/sec)
- Account for operation execution time in delay calculation
- For high rates (>100 ops/sec), consider batch operations instead of per-row delays

### Workload Realism
- Current timestamp for inserts simulates real-time data ingestion
- SELECTs on recent data (last 5 min, 1 hour) represent typical query patterns
- UPDATEs on recent data simulate application updates to active records
- Mix ratios should reflect actual application behavior (adjust based on requirements)

### Concurrency Considerations
- Script should not block cleanup operations
- Use small transactions/batches to minimize lock holding time
- SELECT queries should be fast (using indexes)
- UPDATEs should affect small row sets to avoid long locks

### Resource Usage
- Monitor CPU usage of traffic script (should be minimal)
- Monitor MySQL connections (script should use limited connections)
- Monitor network traffic (especially with high operation rates)
- Ensure script doesn't overwhelm test environment

### Alternative Implementations
- For very high load requirements, consider:
  - Parallel worker processes
  - Compiled tool (e.g., sysbench, mysqlslap)
  - Python/Perl script with connection pooling
  - Multiple script instances with different table targets

### Integration Points
- Phase 4 (Metrics): db-traffic.sh will run during metrics collection
- Phase 5 (Cleanup): db-traffic.sh provides concurrent workload during cleanup tests
- Phase 6 (Orchestration): db-cleanup.sh may start/stop db-traffic.sh automatically
