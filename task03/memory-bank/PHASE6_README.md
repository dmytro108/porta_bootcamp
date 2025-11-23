# Phase 6: Testing and Validation - README

**Status**: Ready for Implementation  
**Created**: November 21, 2025  
**Dependencies**: Phase 5 (All cleanup methods implemented)  

---

## Overview

Phase 6 focuses on **systematic testing and validation** of all four cleanup methods with emphasis on ensuring every test starts with a **consistent database state** and works on the **same dataset** for fair comparison.

---

## Key Principle: Consistent Test Execution

Every test MUST start with:
- ✅ **Same number of rows** in the table
- ✅ **Same data distribution** (50% old, 50% recent)
- ✅ **Same table schema** and indexes
- ✅ **Clean state** (no fragmentation from previous tests)
- ✅ **Verified baseline metrics**

---

## Documents

### Main Implementation Plan
**File**: `PHASE6_TASK_PLAN.md`

**Contents**:
- Complete implementation plan with all stages
- Dataset management (seed data, versioning, checksums)
- Table reset procedures
- Baseline validation
- Test framework architecture
- Test scenarios (basic, concurrent, performance, stress)
- Results analysis and reporting
- Performance regression detection

**Read this first** for complete implementation details.

---

## Phase 6 Structure

### Stage 1: Dataset Management (2-3 hours)
**Goal**: Create versioned, reproducible seed datasets

**Key Tasks**:
- Generate three seed datasets (10K, 100K, 1M rows)
- Use fixed random seed for reproducibility
- Create MD5 checksums for verification
- Implement seed dataset validation

**Deliverables**:
- `data/events_seed_10k_v1.0.csv`
- `data/events_seed_100k_v1.0.csv`
- `data/events_seed_1000k_v1.0.csv` (optional)
- `data/events_seed_*.md5` (checksums)

---

### Stage 2: Test Framework (2-3 hours)
**Goal**: Build automated test orchestration

**Key Tasks**:
- Create master test orchestration script
- Implement test utility library
- Implement test isolation mechanism
- Create table reset procedures
- Implement baseline validation

**Deliverables**:
- `test-cleanup-methods.sh` (master script)
- `lib/test-utils.sh` (utilities)
- `lib/test-scenarios.sh` (scenarios)

---

### Stage 3: Core Test Scenarios (2-3 hours)
**Goal**: Implement comprehensive test scenarios

**Test Scenarios**:
1. **Basic Test Suite**: All methods, no concurrent load
2. **Concurrent Load Test**: All methods with db-traffic.sh running
3. **Performance Benchmark**: 100K rows, detailed metrics
4. **Stress Test**: 1M rows (optional)
5. **Single Method Test**: Custom parameters

**Deliverables**:
- All test scenarios implemented
- Test runs organized in `results/test_runs/`
- Per-scenario result directories

---

### Stage 4: Results Analysis (2-3 hours)
**Goal**: Automated analysis and comparison

**Key Tasks**:
- Generate summary reports
- Create comparison tables
- Detect performance regressions
- Rank methods by performance
- Validate compliance with requirements

**Deliverables**:
- `results/TEST_SUMMARY_*.md`
- `results/comparisons/`
- Benchmark comparison reports

---

## Quick Start Guide

### Prerequisites Check
```bash
# Verify Phase 5 is complete
./run-in-container.sh db-cleanup.sh --help

# Should show all four methods:
# - partition_drop
# - truncate
# - copy
# - batch_delete
```

### Stage 1: Create Seed Datasets
```bash
# Enhance db-load.sh with seed management
# (see PHASE6_TASK_PLAN.md Section 1.1)

# Generate seed datasets
./run-in-container.sh db-load.sh --generate-seed 10000
./run-in-container.sh db-load.sh --generate-seed 100000

# Verify checksums
md5sum -c data/events_seed_10k_v1.0.csv.md5
```

### Stage 2: Create Test Framework
```bash
# Create directory structure
mkdir -p lib
mkdir -p results/test_runs
mkdir -p results/baselines
mkdir -p results/comparisons

# Create test utilities
# (implement lib/test-utils.sh - see PHASE6_TASK_PLAN.md Section 2.2)

# Create test scenarios
# (implement lib/test-scenarios.sh - see PHASE6_TASK_PLAN.md Section 3)
```

### Stage 3: Run Test Scenarios
```bash
# Make test script executable
chmod +x test-cleanup-methods.sh

# Run basic test suite (no concurrent load)
./test-cleanup-methods.sh --scenario basic

# Run concurrent load test suite
./test-cleanup-methods.sh --scenario concurrent

# Run performance benchmark
./test-cleanup-methods.sh --scenario performance

# Test single method
./test-cleanup-methods.sh --scenario single --method partition_drop
```

### Stage 4: Analyze Results
```bash
# View summary report
cat results/TEST_SUMMARY_*.md

# View test run results
ls -lh results/test_runs/

# View specific test run
cat results/test_runs/basic_*/partition_drop_*_metrics.log
```

---

## Key Implementation Details

### Table Reset Procedure

Every test starts by resetting the table to baseline:

```bash
reset_table_to_baseline() {
    # 1. Truncate table (clean slate)
    # 2. Load from versioned seed dataset
    # 3. Verify row count matches expected
    # 4. Capture baseline metrics
    # 5. Validate baseline state
}
```

**Critical**: This ensures:
- No fragmentation from previous tests
- Exact same data in every test
- Reproducible results

### Baseline Validation

Before each test execution:

```bash
validate_baseline_state() {
    # Check 1: Row count matches expected
    # Check 2: Data distribution ~50/50 (old/recent)
    # Check 3: Fragmentation <5%
    # Check 4: Partitions exist (for partitioned table)
}
```

**All checks must pass** before test proceeds.

### Test Isolation

Each test is isolated:

```bash
isolate_test() {
    # 1. Reset table to baseline
    # 2. Wait for replication catchup
    # 3. Validate baseline state
    # 4. Ready for test execution
}
```

**Prevents**: Tests interfering with each other.

---

## Test Scenarios

### 1. Basic Test Suite
**Purpose**: Verify all methods work correctly without external pressure

**Configuration**:
- Dataset: 10K rows (from seed file)
- Concurrent load: None
- Methods: All four (partition_drop, truncate, copy, batch_delete)

**Expected Results**:
- All methods complete successfully
- Metrics captured for each method
- No errors or warnings

### 2. Concurrent Load Test Suite
**Purpose**: Test methods under realistic load conditions

**Configuration**:
- Dataset: 10K rows
- Concurrent load: db-traffic.sh at 10 ops/sec
- Methods: All four

**Expected Results**:
- All methods complete successfully
- Increased replication lag observed
- Query latency impact measured
- No deadlocks or errors

### 3. Performance Benchmark
**Purpose**: Comprehensive performance comparison

**Configuration**:
- Dataset: 100K rows (larger for meaningful metrics)
- Concurrent load: None (for clean metrics)
- Methods: All four

**Metrics Collected**:
- Throughput (rows/sec)
- Duration
- Replication lag
- Space freed
- Fragmentation

**Deliverables**:
- Comparison table (ranked by throughput)
- Detailed metrics logs
- Recommendations

### 4. Single Method Test
**Purpose**: Deep dive into specific method with custom parameters

**Configuration**:
- Dataset: Configurable (default 10K)
- Concurrent load: Optional
- Method: User-specified

**Use Cases**:
- Testing specific batch sizes
- Testing different retention periods
- Debugging method-specific issues

---

## Results Analysis

### Summary Report Contents

1. **Test Execution Summary**
   - List of all test runs
   - Test scenarios executed
   - Success/failure status

2. **Method Performance Comparison**
   - Throughput comparison table
   - Duration comparison
   - Replication lag comparison
   - Space recovery comparison

3. **Test Scenarios**
   - Basic test results
   - Concurrent load test results
   - Performance benchmark results

4. **Conclusions**
   - Method rankings
   - Production recommendations
   - Known issues
   - Next steps

### Performance Regression Detection

Compares current test run to baseline:
- Detects >10% slowdown in throughput
- Generates regression report
- Alerts if regressions detected

---

## Success Criteria

Phase 6 complete when:

- [x] **Dataset Management**: Seed datasets created and verified
- [x] **Table Reset**: Reliable reset procedure implemented
- [x] **Baseline Validation**: All validation checks implemented
- [x] **Test Framework**: Master script and utilities created
- [x] **Test Scenarios**: All scenarios implemented and working
- [x] **Test Isolation**: Each test starts with clean state
- [x] **Results Analysis**: Summary reports and comparisons generated
- [x] **Documentation**: Testing guide complete

---

## Timeline

| Stage | Task                | Effort    |
| ----- | ------------------- | --------- |
| 1     | Dataset Management  | 2-3h      |
| 2     | Test Framework      | 2-3h      |
| 3     | Core Test Scenarios | 2-3h      |
| 4     | Results Analysis    | 2-3h      |
|       | **Total**           | **8-12h** |

**Recommended Schedule**:
- **Day 1** (3-4h): Stages 1-2 (Dataset + Framework)
- **Day 2** (3-4h): Stage 3 (Test Scenarios)
- **Day 3** (2-3h): Stage 4 (Results Analysis + Documentation)

---

## Related Documents

- **PHASE6_TASK_PLAN.md**: Complete implementation plan (READ THIS FIRST)
- **phase5_implementation_summary.md**: Phase 5 status (prerequisites)
- **REQUIREMENT_COMPLIANCE.md**: Which methods meet requirements
- **implementation.md**: Overall project structure

---

## Common Issues and Solutions

### Issue: Seed dataset checksum mismatch
**Solution**: Regenerate seed with --force-regenerate flag

### Issue: Baseline validation fails (fragmentation >5%)
**Solution**: Run OPTIMIZE TABLE before reset

### Issue: Replication lag doesn't catch up
**Solution**: Increase wait timeout, check replica status

### Issue: Row count mismatch after load
**Solution**: Verify seed file integrity, check for loading errors

### Issue: Tests interfere with each other
**Solution**: Ensure reset_table_to_baseline() is called before each test

---

## Contact and Support

For questions or issues:
1. Review PHASE6_TASK_PLAN.md for detailed implementation
2. Check existing test results in results/test_runs/
3. Verify Phase 5 cleanup methods are working
4. Check database connectivity and table structure

---

**Document**: Phase 6 Testing and Validation README  
**Version**: 1.0  
**Status**: Ready for Implementation  
**Last Updated**: November 21, 2025
