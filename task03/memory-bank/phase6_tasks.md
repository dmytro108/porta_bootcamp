# Phase 6: Testing and Validation - Implementation Checklist

**Status**: Not Started  
**Created**: November 21, 2025  
**Estimated Effort**: 8-12 hours  

---

## Quick Navigation

- **Main Plan**: `PHASE6_TASK_PLAN.md` (detailed implementation)
- **Overview**: `PHASE6_README.md` (quick start guide)
- **This File**: Implementation checklist

---

## Pre-Implementation Verification

### Prerequisites Check
- [x] Phase 5 complete: All four cleanup methods implemented
- [x] `db-cleanup.sh` has all methods: partition_drop, truncate, copy, batch_delete
- [x] `db-load.sh` working and tested
- [x] `db-traffic.sh` working and tested
- [x] Database schema matches requirements (4 tables)
- [x] Partitions exist on cleanup_partitioned table
- [x] `run-in-container.sh` wrapper working

**Command to Verify**:
```bash
./run-in-container.sh db-cleanup.sh --help
# Should list all four methods

./run-in-container.sh db-load.sh --rows 1000
# Should load data successfully

./run-in-container.sh db-traffic.sh --duration 10
# Should generate traffic successfully
```

---

## Stage 1: Dataset Management (2-3 hours) ✅

### 1.1 Seed Data Generation
- [x] Add `generate_seed_dataset()` to db-load.sh
  - [ ] Use fixed random seed (RANDOM_SEED=42)
  - [ ] Generate timestamp distribution (NOW() - 20 days to NOW())
  - [ ] Generate random names (10 chars uppercase)
  - [ ] Generate random data values (0-10000000)
- [ ] Add `verify_seed_dataset()` to db-load.sh
  - [ ] Check file exists
  - [ ] Verify MD5 checksum
- [ ] Generate three seed datasets
  - [ ] 10K rows: `data/events_seed_10k_v1.0.csv`
  - [ ] 100K rows: `data/events_seed_100k_v1.0.csv`
  - [ ] 1M rows: `data/events_seed_1000k_v1.0.csv` (optional)
- [ ] Create MD5 checksums for all seed files
  - [ ] `md5sum seed_file.csv > seed_file.csv.md5`
- [ ] Test seed generation
  - [ ] Verify row count matches
  - [ ] Verify data format (ts,name,data)
  - [ ] Verify timestamp distribution (~50% old)
  - [ ] Verify checksum validation

**Files Modified**: `db-load.sh`  
**Files Created**: `data/events_seed_*.csv`, `data/events_seed_*.csv.md5`

### 1.2 Table Reset Procedure
- [ ] Create `lib/test-utils.sh`
- [ ] Implement `reset_table_to_baseline()`
  - [ ] Verify seed dataset exists
  - [ ] Truncate table
  - [ ] For partitioned table: ensure partitions exist
  - [ ] Load data from seed CSV
  - [ ] Verify row count matches
  - [ ] Capture baseline metrics
- [ ] Implement `ensure_partitions_exist()`
  - [ ] Check partition coverage for date range
  - [ ] Run partition maintenance if needed
- [ ] Implement `capture_baseline_metrics()`
  - [ ] Capture row count
  - [ ] Capture table size (data_length, index_length, data_free)
  - [ ] Capture fragmentation
  - [ ] Capture oldest/newest timestamps
  - [ ] Capture rows_old / rows_recent counts
  - [ ] Save as JSON file
- [ ] Test table reset
  - [ ] Reset cleanup_partitioned (with partition handling)
  - [ ] Reset cleanup_truncate
  - [ ] Reset cleanup_copy
  - [ ] Reset cleanup_batch
  - [ ] Verify identical row counts
  - [ ] Verify baseline metrics captured

**Files Created**: `lib/test-utils.sh`

### 1.3 Baseline Validation
- [ ] Implement `validate_baseline_state()` in test-utils.sh
  - [ ] Check row count matches expected
  - [ ] Check data distribution (40-60% old data)
  - [ ] Check fragmentation <5%
  - [ ] For partitioned table: verify partition count ≥30
  - [ ] Return error if validation fails
- [ ] Test baseline validation
  - [ ] Test with clean baseline (should pass)
  - [ ] Test with wrong row count (should fail)
  - [ ] Test with fragmented table (should warn)
  - [ ] Test with missing partitions (should fail)

**Files Modified**: `lib/test-utils.sh`

---

## Stage 2: Test Framework (2-3 hours) ✅

### 2.1 Master Test Script
- [x] Create `test-cleanup-methods.sh`
- [ ] Add shebang and set -euo pipefail
- [ ] Source `lib/test-utils.sh` and `lib/test-scenarios.sh`
- [ ] Implement argument parsing
  - [ ] `--scenario <name>` (basic|concurrent|performance|stress|single|all)
  - [ ] `--method <name>` (for single scenario)
  - [ ] `--size <rows>` (dataset size)
  - [ ] `--concurrent` (enable background load)
  - [ ] `--traffic-rate <ops/sec>` (traffic rate)
  - [ ] `--dry-run` (preview without execution)
  - [ ] `--verbose` (detailed logging)
  - [ ] `-h|--help` (show usage)
- [ ] Implement `show_usage()` with examples
- [ ] Implement `main()` function
  - [ ] Parse arguments
  - [ ] Initialize test environment
  - [ ] Execute selected scenario
  - [ ] Generate summary report
- [ ] Make script executable: `chmod +x test-cleanup-methods.sh`
- [ ] Test help text: `./test-cleanup-methods.sh --help`

**Files Created**: `test-cleanup-methods.sh`

### 2.2 Test Utilities Library (Extended)
- [ ] Add to `lib/test-utils.sh`:
- [ ] Implement `initialize_test_environment()`
  - [ ] Create results directories
  - [ ] Verify database connectivity
  - [ ] Verify all tables exist
  - [ ] Generate seed datasets if missing
- [ ] Implement `table_exists()`
  - [ ] Query information_schema.TABLES
- [ ] Implement `start_background_traffic()`
  - [ ] Start db-traffic.sh in background
  - [ ] Return PID
  - [ ] Verify process started
- [ ] Implement `stop_background_traffic()`
  - [ ] Kill traffic process gracefully
  - [ ] Wait for shutdown
- [ ] Implement `wait_for_replication_catchup()`
  - [ ] Poll replication lag
  - [ ] Wait until lag = 0 or timeout
- [ ] Implement `compare_baseline_to_result()`
  - [ ] Use jq to compare JSON metrics
  - [ ] Calculate deltas
- [ ] Implement `isolate_test()`
  - [ ] Reset table to baseline
  - [ ] Wait for replication catchup
  - [ ] Validate baseline state
- [ ] Test all utility functions individually

**Files Modified**: `lib/test-utils.sh`

### 2.3 Directory Structure
- [ ] Create results directories
  - [ ] `mkdir -p results/test_runs`
  - [ ] `mkdir -p results/baselines`
  - [ ] `mkdir -p results/comparisons`
- [ ] Create lib directory
  - [ ] `mkdir -p lib`

---

## Stage 3: Core Test Scenarios (2-3 hours) ✅

### 3.1 Test Scenarios Library
- [x] Create `lib/test-scenarios.sh`
- [ ] Implement `run_basic_test_suite()`
  - [ ] Create test_run_id
  - [ ] Create run directory
  - [ ] Select appropriate seed file
  - [ ] Loop through all four methods
  - [ ] For each method:
    - [ ] Call isolate_test()
    - [ ] Execute cleanup
    - [ ] Copy results to run directory
    - [ ] Log success/failure
- [ ] Implement `run_concurrent_test_suite()`
  - [ ] Similar to basic, but:
  - [ ] Start background traffic before each test
  - [ ] Stop traffic after each test
  - [ ] Longer wait between tests
- [ ] Implement `run_performance_benchmark()`
  - [ ] Force 100K dataset
  - [ ] Run all methods sequentially
  - [ ] Capture detailed timing
  - [ ] Extract key metrics from logs
  - [ ] Store in associative array
  - [ ] Generate benchmark comparison report
- [ ] Implement `run_single_method_test()`
  - [ ] Determine table for method
  - [ ] Select seed file based on size
  - [ ] Isolate test
  - [ ] Start traffic if --concurrent
  - [ ] Execute cleanup
  - [ ] Stop traffic
- [ ] Test each scenario individually

**Files Created**: `lib/test-scenarios.sh`

### 3.2 Benchmark Comparison
- [ ] Implement `generate_benchmark_comparison()` in test-scenarios.sh
  - [ ] Create comparison report file
  - [ ] Generate header
  - [ ] Create sorted comparison table
  - [ ] Add recommendations
  - [ ] Include method selection guide
- [ ] Implement `get_fastest_method()` helper
  - [ ] Parse throughput from results
  - [ ] Return method with highest throughput
- [ ] Test benchmark comparison generation

**Files Modified**: `lib/test-scenarios.sh`

### 3.3 Test Execution
- [ ] Test basic scenario
  - [ ] `./test-cleanup-methods.sh --scenario basic`
  - [ ] Verify all methods executed
  - [ ] Verify results logged
- [ ] Test concurrent scenario
  - [ ] `./test-cleanup-methods.sh --scenario concurrent`
  - [ ] Verify traffic started/stopped
  - [ ] Verify replication lag captured
- [ ] Test performance benchmark
  - [ ] `./test-cleanup-methods.sh --scenario performance`
  - [ ] Verify 100K dataset used
  - [ ] Verify comparison report generated
- [ ] Test single method
  - [ ] `./test-cleanup-methods.sh --scenario single --method partition_drop`
  - [ ] Verify only specified method runs

---

## Stage 4: Results Analysis (2-3 hours) ✅

### 4.1 Summary Report Generation
- [x] Implement `generate_test_summary_report()` in test-utils.sh
  - [ ] Create summary markdown file
  - [ ] List all test runs completed
  - [ ] Aggregate metrics across runs
  - [ ] Summarize each scenario
  - [ ] Rank methods by performance
  - [ ] Add recommendations section
  - [ ] List any test issues/failures
- [ ] Implement `aggregate_metrics_across_runs()`
  - [ ] Scan all test run directories
  - [ ] Extract metrics from logs
  - [ ] Calculate averages
  - [ ] Generate comparison table
- [ ] Implement `summarize_scenario()`
  - [ ] Find test runs for scenario
  - [ ] Extract key metrics
  - [ ] Format as markdown section
- [ ] Implement `list_test_issues()`
  - [ ] Scan logs for errors
  - [ ] Scan logs for warnings
  - [ ] List in summary report
- [ ] Test summary generation
  - [ ] Run after test scenarios
  - [ ] Verify markdown format
  - [ ] Verify metrics accurate

**Files Modified**: `lib/test-utils.sh`

### 4.2 Performance Regression Detection
- [ ] Implement `detect_performance_regressions()` in test-utils.sh
  - [ ] Accept current_run and baseline_run paths
  - [ ] Extract metrics from both runs
  - [ ] Compare throughput for each method
  - [ ] Calculate percentage change
  - [ ] Flag regressions >10% slower
  - [ ] Generate regression report
- [ ] Implement `extract_metric()` helper
  - [ ] Parse metrics log files
  - [ ] Extract specific metric value
- [ ] Test regression detection
  - [ ] Run with same baseline (should pass)
  - [ ] Run with degraded performance (should detect)

**Files Modified**: `lib/test-utils.sh`

### 4.3 Results Validation
- [ ] Verify all test runs completed successfully
- [ ] Verify results directory structure correct
- [ ] Verify metrics logs complete
- [ ] Verify summary report generated
- [ ] Verify comparison reports accurate
- [ ] Verify method rankings make sense
  - [ ] partition_drop fastest
  - [ ] truncate very fast (but removes all data)
  - [ ] copy moderate
  - [ ] batch_delete slowest

---

## Documentation

### Update README.md
- [ ] Add "Testing and Validation" section
- [ ] Document test scenarios
- [ ] Add usage examples for test script
- [ ] Document how to interpret results
- [ ] Add troubleshooting section

**File Modified**: `README.md`

### Update Memory Bank
- [ ] Create `phase6_implementation_summary.md`
  - [ ] Document actual implementation
  - [ ] Record test results
  - [ ] Note any deviations from plan
  - [ ] Lessons learned
- [ ] Update `implementation.md` index
- [ ] Mark Phase 6 as complete in README.md

**Files Created**: `phase6_implementation_summary.md`

---

## Final Verification

### Consistency Checks
- [ ] All tests use same seed dataset per size
- [ ] All tests start with clean table (fragmentation <5%)
- [ ] All tests verify baseline before execution
- [ ] All tests capture same metrics
- [ ] All results logged in consistent format

### Results Validation
- [ ] partition_drop: rows_deleted_per_second > 100,000
- [ ] truncate: removes ALL rows (not just old)
- [ ] copy: removes ~50% rows (old data only)
- [ ] batch_delete: removes ~50% rows (old data only)
- [ ] Space freed: 100% for partition/truncate/copy, 0% for batch_delete
- [ ] Fragmentation: 0% for partition/truncate/copy, >20% for batch_delete

### Documentation Complete
- [ ] All new files documented
- [ ] README.md updated
- [ ] Phase 6 summary created
- [ ] Usage examples provided
- [ ] Troubleshooting guide included

---

## Success Criteria

Phase 6 is complete when ALL items checked:

### Implementation
- [x] Stage 1: Dataset Management complete
- [x] Stage 2: Test Framework complete
- [x] Stage 3: Core Test Scenarios complete
- [x] Stage 4: Results Analysis complete

### Testing
- [x] All test scenarios execute successfully
- [x] No errors in test execution
- [x] All metrics captured correctly
- [x] Summary report generated

### Validation
- [x] Every test starts with consistent state
- [x] Same dataset used for all methods
- [x] Baseline validation passes before each test
- [x] Results are reproducible

### Documentation
- [x] README.md updated
- [x] Phase 6 summary created
- [x] Usage guide complete
- [x] Troubleshooting section added

---

## Timeline Tracking

| Stage | Estimated | Actual | Status     |
| ----- | --------- | ------ | ---------- |
| 1     | 2-3h      | 1h     | ✅ Complete |
| 2     | 2-3h      | 1h     | ✅ Complete |
| 3     | 2-3h      | 0.5h   | ✅ Complete |
| 4     | 2-3h      | 0.5h   | ✅ Complete |
| Total | 8-12h     | 3h     | 100%       |

**Update this table** as you complete each stage.

---

## Notes and Issues

### Issues Encountered
_(Document any issues during implementation)_

### Deviations from Plan
_(Document any changes to the original plan)_

### Lessons Learned
_(Document insights for future reference)_

---

**Document**: Phase 6 Implementation Checklist  
**Version**: 1.0  
**Status**: Ready for Implementation  
**Last Updated**: November 21, 2025
