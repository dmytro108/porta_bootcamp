# Phase 3 Overview – Load Simulation

## Quick Reference

**Phase**: 3 of 7  
**Status**: ✅ Complete  
**Dependencies**: Phase 1 ✅, Phase 2 ✅  
**Blocking**: Phase 4 (Metrics), Phase 5 (Cleanup Methods)  
**Completion Date**: November 20, 2025  

---

## What is Phase 3?

Phase 3 implements **background workload simulation** to create realistic testing conditions for evaluating cleanup methods. The main deliverable is `db-traffic.sh`, a script that continuously generates database operations (INSERT, SELECT, UPDATE) while cleanup procedures run.

### Why is this needed?

In production environments, cleanup operations never run in isolation—they compete with normal application traffic for resources. Without concurrent load, our cleanup benchmarks would be unrealistic and miss critical issues like:

- Lock contention between cleanup DELETE and application UPDATE
- Table-level locks blocking reads during TRUNCATE
- Replication lag from combined cleanup + application writes
- Query latency degradation during cleanup operations

---

## The Big Picture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cleanup Benchmark Flow                       │
└─────────────────────────────────────────────────────────────────┘

Phase 1: Environment Setup
   ↓
   Create database schema with 4 tables
   
Phase 2: Data Loading
   ↓
   Populate tables with 100K rows (20-day span)
   
Phase 3: Load Simulation ← YOU ARE HERE
   ↓
   db-traffic.sh generates ongoing traffic:
   • 10 INSERTs/sec (new data with current timestamp)
   • 2-3 SELECTs/sec (query recent data)
   • 1-2 UPDATEs/sec (modify recent rows)
   
   This runs IN PARALLEL with cleanup operations
   
Phase 4: Metrics Collection
   ↓
   Measure cleanup impact on:
   • Throughput (rows deleted/sec)
   • Replication lag
   • Query latency
   • Lock contention
   
Phase 5: Cleanup Methods
   ↓
   Test 4 cleanup strategies:
   1. DROP PARTITION (instant)
   2. TRUNCATE TABLE (fast but removes all)
   3. Copy-to-new-table (DDL-based)
   4. Batch DELETE (DML-based)
   
Phase 6: Orchestration
   ↓
   Automate full test runs with db-cleanup.sh
   
Phase 7: Documentation
   ↓
   Final README and usage guide
```

---

## What Gets Built

### Primary Deliverable: `db-traffic.sh`

A bash script that:

1. **Connects** to MySQL and validates environment
2. **Generates** continuous operations:
   - INSERT with `ts = NOW()` (simulates data ingestion)
   - SELECT queries (simulates application reads)
   - UPDATE operations (simulates data modifications)
3. **Rate-limits** operations to target ops/sec
4. **Reports** statistics every 10 seconds
5. **Runs indefinitely** until stopped (Ctrl+C)
6. **Handles signals** gracefully

### Example Usage

```bash
# Start background traffic at 20 ops/sec
./run-in-container.sh db-traffic.sh --rows-per-second 20 &
TRAFFIC_PID=$!

# Let traffic run for a bit
sleep 10

# Now run cleanup while traffic continues
./run-in-container.sh db-cleanup.sh --method batch

# Stop traffic
kill $TRAFFIC_PID
```

### Output Example

```
[2025-11-20 15:30:00] Starting traffic simulation: 20 ops/sec, mix 70:20:10
[2025-11-20 15:30:00] Target tables: cleanup_partitioned, cleanup_truncate, cleanup_copy, cleanup_batch
[2025-11-20 15:30:10] Stats: INSERTs=140 (14.0/s), SELECTs=40 (4.0/s), UPDATEs=20 (2.0/s), Errors=0
[2025-11-20 15:30:20] Stats: INSERTs=145 (14.5/s), SELECTs=38 (3.8/s), UPDATEs=17 (1.7/s), Errors=0
^C
[2025-11-20 15:30:25] Shutting down gracefully...

=== Traffic Simulation Summary ===
Runtime:           25 seconds
Total Operations:  500
  - INSERTs:       350 (70.0%)
  - SELECTs:       100 (20.0%)
  - UPDATEs:       50 (10.0%)
Errors:            0
Average Rate:      20.0 ops/sec
```

---

## Key Concepts

### 1. Workload Mix

**What**: The ratio of operation types (write:read:update)

**Default**: 70:20:10
- 70% INSERTs (continuous data ingestion)
- 20% SELECTs (application queries)
- 10% UPDATEs (data modifications)

**Why it matters**:
- Different mixes reveal different bottlenecks
- Write-heavy (90:10:0) maximizes replication lag
- Read-heavy (20:70:10) highlights query latency impact
- Update-heavy (20:20:60) stresses lock contention

### 2. Rate Limiting

**What**: Control operations per second to achieve consistent load

**How**: Calculate sleep interval = 1.0 / target_ops_per_sec

**Example**:
- Target: 10 ops/sec → sleep 0.1 seconds between operations
- Target: 50 ops/sec → sleep 0.02 seconds between operations

**Why it matters**:
- Ensures reproducible test conditions
- Prevents overwhelming the database
- Allows comparison across test runs

### 3. Concurrent Execution

**What**: db-traffic.sh runs WHILE cleanup operations execute

**Diagram**:
```
Timeline:
0s ──────── 10s ──────── 20s ──────── 30s ──────── 40s
     │                              │
     │   db-traffic.sh (ongoing)   │
     ├──────────────────────────────┤
           │                 │
           │  db-cleanup.sh  │
           ├─────────────────┤
```

**Why it matters**:
- Tests real-world scenario (cleanup doesn't pause application)
- Reveals lock contention issues
- Measures cleanup impact on application performance

### 4. Current Timestamps

**What**: All INSERTs use `ts = NOW()` (not historical dates)

**Why it matters**:
- Simulates real-time data ingestion
- New data should NOT be deleted by cleanup (tests correctness)
- Keeps growing the table while cleanup tries to shrink it
- Tests whether cleanup can "keep up" with ingestion rate

---

## How Phase 3 Supports Later Phases

### Phase 4: Metrics Collection

db-traffic.sh provides:
- **Replication lag source**: Continuous writes create lag
- **Query latency baseline**: SELECTs reveal cleanup impact
- **Lock contention**: UPDATEs conflict with batch DELETE
- **Realistic load**: Metrics measured under production-like conditions

### Phase 5: Cleanup Methods Testing

db-traffic.sh enables testing:
- **DROP PARTITION**: Does it block concurrent INSERTs to other partitions?
- **TRUNCATE TABLE**: How long do SELECTs wait for table-level lock?
- **Copy-to-new-table**: Can reads continue on old table during copy?
- **Batch DELETE**: How much does it slow down concurrent UPDATEs?

### Phase 6: Orchestration

db-cleanup.sh will:
- Optionally start db-traffic.sh automatically
- Run cleanup methods while traffic continues
- Stop traffic after cleanup completes
- Include traffic statistics in final report

---

## Design Decisions

### 1. Bash Script (not Python/Perl)

**Pros**:
- Consistent with existing scripts (db-load.sh, db-cleanup.sh)
- No additional dependencies
- Simple enough for the requirements
- Easy to integrate with mysql client

**Cons**:
- Limited to ~100 ops/sec (script overhead)
- Less precise timing than compiled tools
- More verbose than Python

**Decision**: Use bash for consistency and simplicity. For >100 ops/sec, document alternative (sysbench).

### 2. Single Process (not parallel workers)

**Pros**:
- Simpler implementation
- Easier to control and monitor
- Sufficient for 10-50 ops/sec target range

**Cons**:
- Limited scalability
- Single point of failure

**Decision**: Single process for initial implementation. Document multi-worker option as future enhancement.

### 3. Batched INSERTs (10 rows/statement)

**Pros**:
- Reduces round trips to database
- More efficient than single-row inserts
- Achieves higher throughput

**Cons**:
- Slightly more complex SQL generation
- All-or-nothing per batch

**Decision**: Use 10-row batches for efficiency while keeping batch size small enough to avoid long locks.

### 4. Indefinite Runtime (until stopped)

**Pros**:
- Flexible for different cleanup duration needs
- User controls when to stop
- Simulates continuous production load

**Cons**:
- Requires manual stopping
- No automatic timeout

**Decision**: Run indefinitely by default, add optional `--duration` parameter for timed runs.

---

## Testing Strategy

### Component Tests

1. **Rate Accuracy**: Run for 10 seconds, verify ~target*10 operations
2. **Mix Ratios**: Check operation counts match specified mix
3. **SQL Validity**: Verify generated SQL syntax is correct
4. **Signal Handling**: Test Ctrl+C produces clean exit

### Integration Tests

1. **Concurrent DELETE**: Run traffic during batch DELETE, verify both succeed
2. **Concurrent TRUNCATE**: Run traffic during TRUNCATE, verify INSERTs resume after
3. **Partition Drop**: Run traffic during partition drop, verify no errors
4. **Sustained Load**: Run for 5+ minutes, verify stable performance

### Stress Tests

1. **High Rate**: 100 ops/sec, verify script keeps up
2. **Long Duration**: Run for 1+ hour, verify no memory leaks
3. **Error Recovery**: Kill MySQL connection, verify reconnection

---

## Common Issues and Solutions

### Issue: "Can't connect to MySQL"

**Cause**: Script running on host, MySQL in container

**Solution**: Use `./run-in-container.sh db-traffic.sh`

---

### Issue: Rate too slow or inconsistent

**Cause**: Sleep interval doesn't account for query execution time

**Solution**: Adjust sleep = target_delay - actual_exec_time

---

### Issue: "Lock wait timeout exceeded"

**Cause**: UPDATE conflicts with batch DELETE

**Solution**: Expected behavior. Script should log error and continue.

---

### Issue: Replication lag grows unbounded

**Cause**: Traffic + cleanup exceeds replication capacity

**Solution**: Reduce traffic rate or acknowledge as test finding

---

## Phase 3 Checklist Summary

### Must Have (Phase 3 DoD)

- [x] Script created and executable
- [ ] CLI argument parsing (--rows-per-second, --tables, --workload-mix, etc.)
- [ ] INSERT operation generation (current timestamp, random data)
- [ ] SELECT operation generation (recent data queries)
- [ ] UPDATE operation generation (modify recent rows)
- [ ] Rate limiting implementation
- [ ] Statistics tracking and reporting
- [ ] Signal handling (graceful shutdown)
- [ ] Integration with run-in-container.sh
- [ ] Testing under concurrent cleanup
- [ ] Help text and usage examples

### Nice to Have (Future Enhancements)

- [ ] Query latency measurement (p50, p95, p99)
- [ ] Multiple worker processes for high load
- [ ] Configuration file for complex scenarios
- [ ] Advanced query patterns (JOINs, subqueries)
- [ ] Metrics export (Prometheus, etc.)

---

## Timeline

**Estimated Effort**: 8-12 hours

**Breakdown**:
- Planning and design: 1-2 hours ✅ (this document)
- Core implementation: 4-6 hours
- Testing and debugging: 2-3 hours
- Documentation: 1 hour

**Dependencies**:
- Phase 1: Database schema ✅
- Phase 2: Data loading ✅
- Container environment ✅

---

## Next Steps

1. **Read detailed task list**: `phase3_load_simulation_tasks.md`
2. **Read implementation plan**: `phase3_implementation_plan.md`
3. **Start implementation**: Create `db-traffic.sh` skeleton
4. **Test incrementally**: Verify each component works
5. **Integrate**: Test with existing db-load.sh and schema
6. **Document**: Update with lessons learned

---

## Success Criteria

Phase 3 is successful when you can:

1. ✅ Start background traffic: `./run-in-container.sh db-traffic.sh &`
2. ✅ See periodic statistics reports in console
3. ✅ Run cleanup while traffic continues without errors
4. ✅ Stop traffic cleanly with Ctrl+C
5. ✅ Verify new rows inserted (ts = NOW())
6. ✅ Verify target rate achieved (within 10%)
7. ✅ Verify workload mix correct (70:20:10 default)

When these work, Phase 3 is complete and we can proceed to Phase 4 (Metrics).

---

## Questions?

**Q**: Why not use sysbench or mysqlslap?

**A**: Those are excellent tools for high load (1000+ ops/sec), but for our test scenario (10-50 ops/sec) a simple bash script is:
- Easier to customize (specific query patterns)
- Integrated with existing scripts
- Sufficient performance for requirements
- Better for learning and transparency

**Q**: What if cleanup finishes before I stop traffic?

**A**: That's fine! Traffic continues running, keeping the database active. You can:
- Run another cleanup test immediately
- Observe table growth from ongoing inserts
- Stop traffic when done with all tests

**Q**: Can I run multiple traffic scripts in parallel?

**A**: Yes! You can start multiple instances targeting different tables or with different mixes. Just track each PID separately.

**Q**: How do I know if my rate limiting is working?

**A**: Check the periodic statistics. If you target 10 ops/sec, you should see ~100 operations every 10-second report. If actual rate is consistently different, adjust the sleep calculation.

---

## Related Documents

- **Detailed Tasks**: `phase3_load_simulation_tasks.md` - Complete checklist
- **Implementation Plan**: `phase3_implementation_plan.md` - Architecture and design
- **Original Spec**: `implementation_load_simulation.md` - High-level requirements
- **Phase 1 Summary**: `phase1_implementation_summary.md` - Database setup
- **Phase 2 Summary**: `phase2_implementation_summary.md` - Data loading

---

**Last Updated**: 2025-11-20  
**Status**: Ready to implement  
**Assigned To**: [Your name]  
**Review Date**: After implementation complete
