# Phase 5 Implementation Tasks - Detailed Checklist

**Status**: Not Started  
**Target Completion**: November 21-22, 2025  
**Estimated Effort**: 12-16 hours  

---

## Stage 1: TRUNCATE TABLE Method ⏳

### 1.1 Core Implementation
- [ ] Open `task03/db-cleanup.sh` in editor
- [ ] Implement `execute_truncate_cleanup()` function
  - [ ] Add function signature with parameters (table name)
  - [ ] Add SQL: `TRUNCATE TABLE database.table;`
  - [ ] Add mysql_exec() call
  - [ ] Add error handling
  - [ ] Add logging statements
- [ ] Test function independently with test data

### 1.2 Metrics Integration
- [ ] Implement `run_truncate_cleanup()` wrapper function
  - [ ] Add pre-cleanup snapshot capture
  - [ ] Add timestamp recording (start)
  - [ ] Call `execute_truncate_cleanup()`
  - [ ] Add timestamp recording (end)
  - [ ] Add post-cleanup snapshot capture
  - [ ] Add duration calculation
  - [ ] Add metrics logging call
- [ ] Test wrapper with metrics collection

### 1.3 Testing
- [ ] Test 1: Basic functionality
  - [ ] Load 10K rows to cleanup_truncate
  - [ ] Run TRUNCATE cleanup
  - [ ] Verify table empty (0 rows)
  - [ ] Verify metrics log created
  - [ ] Verify duration < 5 seconds
  - [ ] Verify rows_deleted = 10000
- [ ] Test 2: With concurrent load
  - [ ] Load 10K rows
  - [ ] Start db-traffic.sh
  - [ ] Run TRUNCATE cleanup
  - [ ] Stop traffic
  - [ ] Verify no errors
  - [ ] Verify metrics captured

### 1.4 Documentation
- [ ] Add TRUNCATE method section to README.md
- [ ] Document characteristics
- [ ] Document when to use / not use
- [ ] Add usage examples

**Stage 1 Complete**: ☐ NOT STARTED

---

## Stage 2: DROP PARTITION Method ❌ NOT STARTED

### 2.1 Partition Identification
- [ ] Implement `identify_old_partitions()` function
  - [ ] Add function signature (table, retention_days)
  - [ ] Add TO_DAYS() cutoff calculation
  - [ ] Add SQL query to information_schema.PARTITIONS
  - [ ] Add pFUTURE exclusion logic
  - [ ] Add partition list formatting (comma-separated)
  - [ ] Add logging
- [ ] Test partition identification independently
  - [ ] Verify correct partitions identified
  - [ ] Verify pFUTURE excluded
  - [ ] Verify empty result when no old partitions

### 2.2 Core Implementation
- [ ] Implement `execute_partition_drop_cleanup()` function
  - [ ] Call identify_old_partitions()
  - [ ] Handle empty partition list (no-op)
  - [ ] Build ALTER TABLE DROP PARTITION SQL
  - [ ] Execute SQL via mysql_exec()
  - [ ] Add error handling
  - [ ] Add logging
- [ ] Test function with test partitions

### 2.3 Metrics Integration
- [ ] Implement `run_partition_drop_cleanup()` wrapper
  - [ ] Same pattern as TRUNCATE wrapper
  - [ ] Add partition count logging
  - [ ] Method name: "partition_drop"
- [ ] Test with metrics

### 2.4 Testing
- [ ] Test 1: Basic functionality
  - [ ] Load 10K rows to cleanup_partitioned (20 day span)
  - [ ] Verify partitions exist
  - [ ] Run dry-run to preview
  - [ ] Run partition drop
  - [ ] Verify old partitions dropped
  - [ ] Verify row count reduced
  - [ ] Verify metrics log
- [ ] Test 2: No partitions to drop
  - [ ] Run partition drop twice
  - [ ] Verify second run reports no partitions
  - [ ] Verify no errors
- [ ] Test 3: Partition maintenance still works
  - [ ] Run db-partition-maintenance.sh
  - [ ] Verify new partition created

### 2.5 Documentation
- [ ] Add DROP PARTITION section to README.md
- [ ] Document partition identification logic
- [ ] Document TO_DAYS() calculation
- [ ] Document characteristics and use cases

**Stage 2 Complete**: ☐ NOT STARTED

---

## Stage 3: Copy-to-New-Table Method ❌ NOT STARTED

### 3.1 Core Implementation
- [ ] Implement `execute_copy_cleanup()` function
  - [ ] Step 1: CREATE TABLE new LIKE original
    - [ ] Add SQL statement
    - [ ] Execute via mysql_exec()
    - [ ] Add error handling
  - [ ] Step 2: INSERT INTO new SELECT * FROM original WHERE ts >= cutoff
    - [ ] Add SQL statement with retention filter
    - [ ] Execute via mysql_exec()
    - [ ] Add error handling
    - [ ] Add cleanup on error (drop temp table)
  - [ ] Step 3: RENAME TABLE (atomic swap)
    - [ ] Add RENAME SQL (original→old, new→original)
    - [ ] Execute via mysql_exec()
    - [ ] Add error handling
  - [ ] Step 4: DROP TABLE old
    - [ ] Add DROP SQL
    - [ ] Execute via mysql_exec()
    - [ ] Treat failure as warning (non-critical)
  - [ ] Add logging for each step
- [ ] Test function with small dataset

### 3.2 Metrics Integration
- [ ] Implement `run_copy_cleanup()` wrapper
  - [ ] Snapshot BEFORE CREATE (original state)
  - [ ] Snapshot AFTER DROP (final state)
  - [ ] Optional: log intermediate step durations
- [ ] Test with metrics

### 3.3 Testing
- [ ] Test 1: Basic functionality
  - [ ] Load 10K rows (20 day span)
  - [ ] Run copy cleanup (retain 10 days)
  - [ ] Verify cleanup_copy has ~5K rows
  - [ ] Verify cleanup_copy_old doesn't exist
  - [ ] Verify cleanup_copy_new doesn't exist
  - [ ] Verify metrics: ~5K deleted, space freed, 0% fragmentation
- [ ] Test 2: Error recovery
  - [ ] Simulate failure (disk full, etc.)
  - [ ] Verify temp table cleaned up
  - [ ] Verify original table unchanged
- [ ] Test 3: With concurrent writes
  - [ ] Start db-traffic.sh
  - [ ] Run copy cleanup
  - [ ] Stop traffic
  - [ ] Document data loss warning

### 3.4 Documentation
- [ ] Add Copy-to-New-Table section to README.md
- [ ] Document 4-step process
- [ ] **Critical warning**: Data written during copy is LOST
- [ ] Document RENAME lock impact
- [ ] Document disk space requirement (2x table size)
- [ ] Document use cases and limitations

**Stage 3 Complete**: ☐ NOT STARTED

---

## Stage 4: Batch DELETE Method ❌ NOT STARTED

### 4.1 Core Implementation
- [ ] Implement `execute_batch_delete_cleanup()` function
  - [ ] Add function signature (table, retention, batch_size, batch_delay)
  - [ ] Initialize counters (batch_num, total_deleted)
  - [ ] Create batch log CSV file
    - [ ] Write CSV header
  - [ ] Implement batch loop (while rows_affected > 0)
    - [ ] Record batch start timestamp
    - [ ] Execute DELETE...LIMIT SQL
    - [ ] Get ROW_COUNT()
    - [ ] Record batch end timestamp
    - [ ] Calculate batch duration
    - [ ] Calculate batch throughput
    - [ ] Get current replication lag
    - [ ] Write batch metrics to CSV
    - [ ] Log batch progress
    - [ ] Sleep between batches
  - [ ] Add safety counter (max 10000 batches)
  - [ ] Add final summary logging
- [ ] Test with small dataset (1K rows, batch size 100)

### 4.2 Batch Metrics Analysis
- [ ] Implement `analyze_batch_metrics()` function
  - [ ] Read batch CSV file
  - [ ] Calculate statistics using awk:
    - [ ] Total batches
    - [ ] Total rows deleted
    - [ ] Total duration
    - [ ] Average throughput
    - [ ] Min/max throughput
    - [ ] Throughput degradation %
    - [ ] Max replication lag
  - [ ] Print summary report
- [ ] Test analysis with sample batch log

### 4.3 Metrics Integration
- [ ] Implement `run_batch_delete_cleanup()` wrapper
  - [ ] Overall before/after snapshots
  - [ ] Call execute_batch_delete_cleanup()
  - [ ] Call analyze_batch_metrics()
  - [ ] Log overall + batch metrics
  - [ ] Include batch analysis in summary

### 4.4 Parameter Tuning Tests
- [ ] Test with batch_size=1000
  - [ ] Load 50K rows
  - [ ] Run batch delete
  - [ ] Record throughput, lag, duration
- [ ] Test with batch_size=5000
  - [ ] Load 50K rows
  - [ ] Run batch delete
  - [ ] Record throughput, lag, duration
- [ ] Test with batch_size=10000
  - [ ] Load 50K rows
  - [ ] Run batch delete
  - [ ] Record throughput, lag, duration
- [ ] Compare results and document findings

### 4.5 Comprehensive Testing
- [ ] Test 1: Basic functionality
  - [ ] Load 10K rows
  - [ ] Run batch delete (batch_size=5000)
  - [ ] Verify ~5K rows deleted
  - [ ] Verify batch log created
  - [ ] Verify metrics log created
  - [ ] Verify fragmentation increased
- [ ] Test 2: With concurrent load
  - [ ] Start db-traffic.sh
  - [ ] Run batch delete
  - [ ] Stop traffic
  - [ ] Verify no deadlocks
  - [ ] Verify metrics captured
- [ ] Test 3: Throughput degradation
  - [ ] Load 100K rows
  - [ ] Run batch delete
  - [ ] Analyze batch log
  - [ ] Verify degradation trend (first vs last batch)
- [ ] Test 4: OPTIMIZE TABLE (optional)
  - [ ] Run batch delete
  - [ ] Check fragmentation (should be high)
  - [ ] Run OPTIMIZE TABLE
  - [ ] Check fragmentation (should be 0%)

### 4.6 Documentation
- [ ] Add Batch DELETE section to README.md
- [ ] Document batch size selection guidelines
- [ ] Document batch delay tuning
- [ ] Document throughput degradation
- [ ] Document fragmentation impact
- [ ] Document post-cleanup OPTIMIZE TABLE recommendation
- [ ] Add OPTIMIZE TABLE example

**Stage 4 Complete**: ☐ NOT STARTED

---

## Stage 5: CLI Integration ❌ NOT STARTED

### 5.1 Argument Parsing
- [ ] Add new command-line options to db-cleanup.sh
  - [ ] `--method <name>` (truncate|partition_drop|copy|batch_delete|all)
  - [ ] `--table <name>` (optional override)
  - [ ] `--retention-days <n>` (default: 10)
  - [ ] `--batch-size <n>` (default: 5000)
  - [ ] `--batch-delay <n>` (default: 0.1)
  - [ ] `--dry-run` (preview mode)
- [ ] Update help text with all options
- [ ] Add option validation

### 5.2 Method Dispatch
- [ ] Implement `run_cleanup()` dispatcher function
  - [ ] Case statement for each method
  - [ ] Call appropriate run_*_cleanup() function
  - [ ] Handle "all" method specially
  - [ ] Error for unknown method
- [ ] Test each method via CLI

### 5.3 All Methods Sequential Execution
- [ ] Implement `run_all_methods()` function
  - [ ] Define reload_table() helper
  - [ ] Execute partition drop with reload
  - [ ] Execute truncate with reload
  - [ ] Execute copy with reload
  - [ ] Execute batch delete with reload
  - [ ] Log completion summary
- [ ] Test all methods execution

### 5.4 Dry-Run Mode
- [ ] Add dry-run flag to each execute_*_cleanup() function
- [ ] In dry-run mode:
  - [ ] Print SQL that would be executed
  - [ ] Don't execute mysql_exec()
  - [ ] Log "dry-run" in output
- [ ] Test dry-run for each method

### 5.5 CLI Testing
- [ ] Test: `--method truncate`
- [ ] Test: `--method partition_drop --retention-days 7`
- [ ] Test: `--method copy --table cleanup_copy`
- [ ] Test: `--method batch_delete --batch-size 10000`
- [ ] Test: `--method all`
- [ ] Test: `--dry-run` for each method
- [ ] Test: `--help`

**Stage 5 Complete**: ☐ NOT STARTED

---

## Stage 6: Testing & Validation ❌ NOT STARTED

### 6.1 Integration Test Suite
- [ ] Create `test-all-methods.sh` script (optional)
  - [ ] Test TRUNCATE
  - [ ] Test DROP PARTITION
  - [ ] Test Copy
  - [ ] Test Batch DELETE
  - [ ] Verify all results
- [ ] Run integration tests
- [ ] Document any issues found

### 6.2 Concurrent Load Tests
- [ ] Create `test-with-load.sh` script (optional)
  - [ ] Start db-traffic.sh
  - [ ] Run cleanup method
  - [ ] Stop traffic
  - [ ] Verify results
- [ ] Test each method with concurrent load
- [ ] Document impact on query latency

### 6.3 Performance Benchmarks
- [ ] Create `benchmark-all.sh` script (optional)
- [ ] Run benchmarks with 10K rows
  - [ ] Collect metrics for all methods
  - [ ] Compare results
- [ ] Run benchmarks with 100K rows
  - [ ] Collect metrics for all methods
  - [ ] Compare results
- [ ] Optional: Run with 1M rows if time permits
- [ ] Document baseline performance characteristics

### 6.4 Results Validation
- [ ] Verify all metrics logs created correctly
- [ ] Verify batch logs for batch delete
- [ ] Verify metric values are sensible
  - [ ] Duration > 0
  - [ ] Throughput calculated correctly
  - [ ] Row counts accurate
  - [ ] Space freed logical
- [ ] Compare methods side-by-side
- [ ] Document findings

**Stage 6 Complete**: ☐ NOT STARTED

---

## Stage 7: Documentation ❌ NOT STARTED

### 7.1 Update README.md
- [ ] Add "Cleanup Methods" section
  - [ ] Method 1: DROP PARTITION
    - [ ] Description
    - [ ] Characteristics
    - [ ] SQL pattern
    - [ ] Usage example
    - [ ] When to use
  - [ ] Method 2: TRUNCATE TABLE
    - [ ] Description
    - [ ] Characteristics
    - [ ] SQL pattern
    - [ ] Usage example
    - [ ] When to use
    - [ ] Warning about removing all data
  - [ ] Method 3: Copy-to-New-Table
    - [ ] Description
    - [ ] Characteristics
    - [ ] SQL pattern (4 steps)
    - [ ] Usage example
    - [ ] When to use
    - [ ] Critical warnings
  - [ ] Method 4: Batch DELETE
    - [ ] Description
    - [ ] Characteristics
    - [ ] SQL pattern
    - [ ] Usage example
    - [ ] When to use
    - [ ] Tuning guidelines
    - [ ] Post-cleanup OPTIMIZE TABLE

### 7.2 Usage Examples Section
- [ ] Add "Usage Examples" section to README
  - [ ] Run single method examples
  - [ ] Custom parameters examples
  - [ ] Run all methods example
  - [ ] Dry-run example
  - [ ] With concurrent load example

### 7.3 Results Interpretation Guide
- [ ] Add "Interpreting Results" section
  - [ ] Metrics logs location
  - [ ] Key metrics explanation
    - [ ] rows_deleted_per_second
    - [ ] Replication lag
    - [ ] Space freed
    - [ ] Fragmentation
  - [ ] Expected values for each method
  - [ ] Method selection decision tree

### 7.4 Implementation Summary
- [ ] Create `phase5_implementation_summary.md`
  - [ ] Overview
  - [ ] Implementation details for each method
  - [ ] Test results
  - [ ] Performance benchmarks
  - [ ] Lessons learned
  - [ ] Known limitations
  - [ ] Success criteria verification

**Stage 7 Complete**: ☐ NOT STARTED

---

## Final Checklist

### All Methods Implemented
- [ ] TRUNCATE method working
- [ ] DROP PARTITION method working
- [ ] Copy-to-New-Table method working
- [ ] Batch DELETE method working

### Metrics Integration
- [ ] Each method wrapped with metrics collection
- [ ] Metrics logs created correctly
- [ ] Batch metrics (for batch delete) working
- [ ] All metrics sensible and accurate

### CLI Complete
- [ ] All options implemented
- [ ] Method dispatch working
- [ ] Dry-run mode working
- [ ] Help text accurate

### Testing Complete
- [ ] All methods tested individually
- [ ] All methods tested with concurrent load
- [ ] Integration tests passed
- [ ] Performance benchmarks collected

### Documentation Complete
- [ ] README.md updated comprehensively
- [ ] Usage examples provided
- [ ] Results interpretation guide written
- [ ] Implementation summary created

### Ready for Phase 6
- [ ] All cleanup methods working
- [ ] Results logs in task03/results/
- [ ] Can compare methods objectively
- [ ] Documentation complete

---

## Progress Tracking

**Overall Progress**: 0% (0/7 stages)

| Stage | Task                  | Status      | Time Spent | Notes |
| ----- | --------------------- | ----------- | ---------- | ----- |
| 1     | TRUNCATE method       | Not Started | -          | -     |
| 2     | DROP PARTITION method | Not Started | -          | -     |
| 3     | Copy-to-New-Table     | Not Started | -          | -     |
| 4     | Batch DELETE method   | Not Started | -          | -     |
| 5     | CLI Integration       | Not Started | -          | -     |
| 6     | Testing & Validation  | Not Started | -          | -     |
| 7     | Documentation         | Not Started | -          | -     |

---

## Notes & Issues

### Implementation Notes
(To be filled during implementation)

### Issues Encountered
(To be filled during implementation)

### Optimization Ideas
(To be filled during implementation)

---

**Last Updated**: November 20, 2025 (Created)  
**Status**: Ready to Begin Implementation  
**Next Action**: Start Stage 1 - TRUNCATE Method
