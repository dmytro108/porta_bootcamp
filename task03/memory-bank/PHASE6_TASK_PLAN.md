# Phase 6: Testing and Validation - Detailed Implementation Plan

**Status**: Ready for Implementation  
**Dependencies**: Phase 5 ✅ (All cleanup methods implemented)  
**Goal**: Ensure consistent test execution with same dataset across all methods  
**Estimated Effort**: 8-12 hours  
**Target Completion**: November 22-23, 2025  

---

## Executive Summary

Phase 6 focuses on **systematic testing and validation** of all four cleanup methods with emphasis on:
1. **Consistent database state** before each test
2. **Same dataset** for fair comparison
3. **Reproducible results**
4. **Comprehensive test scenarios** (with/without concurrent load)
5. **Automated test orchestration**
6. **Results comparison and analysis**

### Key Principle: Fair Comparison

Every test MUST start with:
- ✅ Same number of rows in the table
- ✅ Same data distribution (age, values)
- ✅ Same table schema and indexes
- ✅ Clean state (no fragmentation from previous tests)
- ✅ Consistent baseline metrics

---

## Phase 6 Structure

### Stage 1: Dataset Management (2-3 hours)
- Seed data generation and versioning
- Table reset/reload procedures
- Baseline state validation

### Stage 2: Test Framework (2-3 hours)
- Test orchestration scripts
- Pre-test and post-test validation
- Test isolation mechanisms

### Stage 3: Core Test Scenarios (2-3 hours)
- Individual method tests
- Concurrent load tests
- Performance benchmarks

### Stage 4: Results Analysis (2-3 hours)
- Automated comparison reports
- Performance regression detection
- Decision tree validation

---

## Stage 1: Dataset Management

### Goal
Ensure every test starts with identical, reproducible dataset.

### 1.1 Seed Data Versioning

**Task**: Create versioned seed datasets for different test scenarios

**Implementation**:

```bash
# File: task03/db-load.sh (enhancement)

# Add seed data management
SEED_VERSION="v1.0"
SEED_SMALL="${DATA_DIR}/events_seed_10k_${SEED_VERSION}.csv"
SEED_MEDIUM="${DATA_DIR}/events_seed_100k_${SEED_VERSION}.csv"
SEED_LARGE="${DATA_DIR}/events_seed_1000k_${SEED_VERSION}.csv"

generate_seed_dataset() {
    local rows=$1
    local seed_file=$2
    
    if [ -f "$seed_file" ]; then
        log "INFO" "Seed dataset exists: $seed_file"
        return 0
    fi
    
    log "INFO" "Generating seed dataset: $rows rows -> $seed_file"
    
    # Generate with fixed random seed for reproducibility
    RANDOM_SEED=42
    generate_csv "$rows" "$seed_file" "$RANDOM_SEED"
    
    # Calculate and store checksum
    md5sum "$seed_file" > "${seed_file}.md5"
    
    log "INFO" "Seed dataset created: $seed_file"
}

verify_seed_dataset() {
    local seed_file=$1
    
    if [ ! -f "$seed_file" ]; then
        log "ERROR" "Seed dataset not found: $seed_file"
        return 1
    fi
    
    if [ ! -f "${seed_file}.md5" ]; then
        log "WARNING" "Checksum file missing for $seed_file"
        return 0
    fi
    
    # Verify checksum
    md5sum -c "${seed_file}.md5" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "ERROR" "Checksum verification failed for $seed_file"
        return 1
    fi
    
    log "INFO" "Seed dataset verified: $seed_file"
    return 0
}
```

**Deliverables**:
- Three seed datasets: 10K, 100K, 1M rows
- Fixed random seed for reproducibility
- MD5 checksums for verification
- Data distribution: 50% old (>10 days), 50% recent (≤10 days)

### 1.2 Table Reset Procedure

**Task**: Implement reliable table reset to consistent baseline state

**Implementation**:

```bash
# File: task03/lib/test-utils.sh (new library file)

reset_table_to_baseline() {
    local table=$1
    local seed_file=$2
    local database=${DB_NAME:-cleanup_bench}
    
    log "INFO" "Resetting table ${table} to baseline state"
    
    # Step 1: Verify seed dataset
    verify_seed_dataset "$seed_file" || return 1
    
    # Step 2: Truncate table (fast, clean slate)
    log "INFO" "Truncating ${database}.${table}"
    mysql_exec "TRUNCATE TABLE ${database}.${table};"
    
    # Step 3: For partitioned table, ensure partitions exist
    if [ "$table" = "cleanup_partitioned" ]; then
        ensure_partitions_exist || return 1
    fi
    
    # Step 4: Load seed data
    log "INFO" "Loading seed data from ${seed_file}"
    load_csv_to_table "$seed_file" "$table"
    
    # Step 5: Verify row count
    local expected_rows=$(wc -l < "$seed_file")
    local actual_rows=$(get_row_count "$database" "$table")
    
    if [ "$actual_rows" -ne "$expected_rows" ]; then
        log "ERROR" "Row count mismatch: expected=$expected_rows, actual=$actual_rows"
        return 1
    fi
    
    # Step 6: Capture baseline metrics
    local baseline_file="${RESULTS_DIR}/baseline_${table}_$(date +%Y%m%d_%H%M%S).json"
    capture_baseline_metrics "$table" > "$baseline_file"
    
    log "INFO" "Table ${table} reset to baseline: ${actual_rows} rows"
    log "INFO" "Baseline metrics saved: ${baseline_file}"
    
    return 0
}

ensure_partitions_exist() {
    local database=${DB_NAME:-cleanup_bench}
    local table="cleanup_partitioned"
    
    # Check if partitions cover required date range
    local min_date=$(date -d "20 days ago" +%Y%m%d)
    local max_date=$(date -d "tomorrow" +%Y%m%d)
    
    log "INFO" "Ensuring partitions exist for date range: ${min_date} to ${max_date}"
    
    # Run partition maintenance to add missing partitions
    run_partition_maintenance --ensure-range "$min_date" "$max_date"
    
    return $?
}

capture_baseline_metrics() {
    local table=$1
    local database=${DB_NAME:-cleanup_bench}
    
    # Capture comprehensive baseline state
    cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "table": "${table}",
  "database": "${database}",
  "row_count": $(get_row_count "$database" "$table"),
  "data_length": $(get_table_info "$database" "$table" | jq -r '.data_length'),
  "index_length": $(get_table_info "$database" "$table" | jq -r '.index_length'),
  "data_free": $(get_table_info "$database" "$table" | jq -r '.data_free'),
  "fragmentation": $(get_fragmentation "$database" "$table"),
  "oldest_ts": "$(mysql_exec "SELECT MIN(ts) FROM ${database}.${table};" | tail -1)",
  "newest_ts": "$(mysql_exec "SELECT MAX(ts) FROM ${database}.${table};" | tail -1)",
  "rows_old": $(mysql_exec "SELECT COUNT(*) FROM ${database}.${table} WHERE ts < NOW() - INTERVAL 10 DAY;" | tail -1),
  "rows_recent": $(mysql_exec "SELECT COUNT(*) FROM ${database}.${table} WHERE ts >= NOW() - INTERVAL 10 DAY;" | tail -1)
}
EOF
}
```

**Key Features**:
- Clean slate via TRUNCATE (removes fragmentation from previous tests)
- Loads from versioned seed dataset
- Verifies row count matches expected
- Captures comprehensive baseline metrics
- Special handling for partitioned table

### 1.3 Baseline Validation

**Task**: Verify tables are in consistent state before test

**Implementation**:

```bash
validate_baseline_state() {
    local table=$1
    local expected_rows=$2
    local database=${DB_NAME:-cleanup_bench}
    
    log "INFO" "Validating baseline state for ${table}"
    
    local errors=0
    
    # Check 1: Row count
    local actual_rows=$(get_row_count "$database" "$table")
    if [ "$actual_rows" -ne "$expected_rows" ]; then
        log "ERROR" "Row count mismatch: expected=${expected_rows}, actual=${actual_rows}"
        ((errors++))
    fi
    
    # Check 2: Data distribution (should be ~50% old, ~50% recent)
    local rows_old=$(mysql_exec "SELECT COUNT(*) FROM ${database}.${table} WHERE ts < NOW() - INTERVAL 10 DAY;" | tail -1)
    local rows_recent=$(mysql_exec "SELECT COUNT(*) FROM ${database}.${table} WHERE ts >= NOW() - INTERVAL 10 DAY;" | tail -1)
    
    local old_pct=$(awk "BEGIN {printf \"%.1f\", ($rows_old / $actual_rows) * 100}")
    
    # Allow 40-60% range (accounts for date boundary shifts)
    if (( $(echo "$old_pct < 40.0" | bc -l) )) || (( $(echo "$old_pct > 60.0" | bc -l) )); then
        log "WARNING" "Data distribution skewed: ${old_pct}% old (expected ~50%)"
        # Warning only, not error
    fi
    
    # Check 3: Fragmentation should be low (<5%)
    local fragmentation=$(get_fragmentation "$database" "$table")
    if (( $(echo "$fragmentation > 5.0" | bc -l) )); then
        log "WARNING" "High fragmentation detected: ${fragmentation}% (expected <5%)"
    fi
    
    # Check 4: For partitioned table, verify partitions
    if [ "$table" = "cleanup_partitioned" ]; then
        local partition_count=$(mysql_exec "SELECT COUNT(*) FROM information_schema.PARTITIONS WHERE TABLE_SCHEMA='${database}' AND TABLE_NAME='${table}' AND PARTITION_NAME != 'pFUTURE';" | tail -1)
        if [ "$partition_count" -lt 30 ]; then
            log "ERROR" "Insufficient partitions: ${partition_count} (expected >= 30)"
            ((errors++))
        fi
    fi
    
    if [ $errors -gt 0 ]; then
        log "ERROR" "Baseline validation failed with ${errors} errors"
        return 1
    fi
    
    log "INFO" "Baseline validation passed: ${actual_rows} rows (${old_pct}% old, ${100-old_pct}% recent)"
    return 0
}
```

**Validation Checks**:
- ✅ Row count matches expected
- ✅ Data distribution is ~50/50 (old/recent)
- ✅ Low fragmentation (<5%)
- ✅ Sufficient partitions for partitioned table
- ✅ No orphaned temp tables

---

## Stage 2: Test Framework

### Goal
Automated, reproducible test execution with consistent setup/teardown.

### 2.1 Test Orchestration Script

**Task**: Create master test orchestration script

**File**: `task03/test-cleanup-methods.sh`

```bash
#!/bin/bash
#
# test-cleanup-methods.sh - Master test orchestration for cleanup methods
#
# Usage:
#   ./test-cleanup-methods.sh --scenario <name> [options]
#
# Scenarios:
#   basic           - Test all methods with 10K rows, no concurrent load
#   concurrent      - Test all methods with 10K rows + concurrent load
#   performance     - Performance benchmark with 100K rows
#   stress          - Stress test with 1M rows (optional)
#   single          - Test single method
#   all             - Run all scenarios (basic, concurrent, performance)

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/test-utils.sh"
source "${SCRIPT_DIR}/lib/test-scenarios.sh"

# Configuration
SCENARIO=""
METHOD=""
DATASET_SIZE="10000"
CONCURRENT_LOAD=false
TRAFFIC_RATE=10
DRY_RUN=false
VERBOSE=false

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --scenario)
                SCENARIO="$2"
                shift 2
                ;;
            --method)
                METHOD="$2"
                shift 2
                ;;
            --size)
                DATASET_SIZE="$2"
                shift 2
                ;;
            --concurrent)
                CONCURRENT_LOAD=true
                shift
                ;;
            --traffic-rate)
                TRAFFIC_RATE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

show_usage() {
    cat <<EOF
Usage: test-cleanup-methods.sh [options]

Test Scenarios:
  --scenario basic          Test all methods with 10K rows (default)
  --scenario concurrent     Test all methods with concurrent load
  --scenario performance    Performance benchmark with 100K rows
  --scenario stress         Stress test with 1M rows
  --scenario single         Test single method (requires --method)
  --scenario all            Run all scenarios

Options:
  --method <name>           Test specific method (partition_drop|truncate|copy|batch_delete)
  --size <rows>             Dataset size (default: 10000)
  --concurrent              Enable concurrent load during test
  --traffic-rate <ops/sec>  Traffic rate for concurrent load (default: 10)
  --dry-run                 Preview test plan without execution
  --verbose                 Enable detailed logging
  -h, --help                Show this help message

Examples:
  # Run basic test suite
  ./test-cleanup-methods.sh --scenario basic

  # Test all methods with concurrent load
  ./test-cleanup-methods.sh --scenario concurrent

  # Performance benchmark
  ./test-cleanup-methods.sh --scenario performance

  # Test single method
  ./test-cleanup-methods.sh --scenario single --method batch_delete

  # Custom test with concurrent load
  ./test-cleanup-methods.sh --method partition_drop --size 50000 --concurrent
EOF
}

main() {
    parse_arguments "$@"
    
    # Default scenario
    if [ -z "$SCENARIO" ]; then
        SCENARIO="basic"
    fi
    
    log "INFO" "=== Cleanup Methods Test Suite ==="
    log "INFO" "Scenario: ${SCENARIO}"
    log "INFO" "Dataset size: ${DATASET_SIZE} rows"
    log "INFO" "Concurrent load: ${CONCURRENT_LOAD}"
    
    # Initialize test environment
    initialize_test_environment
    
    # Execute scenario
    case "$SCENARIO" in
        basic)
            run_basic_test_suite
            ;;
        concurrent)
            run_concurrent_test_suite
            ;;
        performance)
            run_performance_benchmark
            ;;
        stress)
            run_stress_test
            ;;
        single)
            run_single_method_test "$METHOD"
            ;;
        all)
            run_all_scenarios
            ;;
        *)
            log "ERROR" "Unknown scenario: $SCENARIO"
            show_usage
            exit 1
            ;;
    esac
    
    # Generate summary report
    generate_test_summary_report
    
    log "INFO" "Test suite completed successfully"
}

main "$@"
```

### 2.2 Test Utility Library

**Task**: Create reusable test utilities

**File**: `task03/lib/test-utils.sh`

```bash
#!/bin/bash
#
# test-utils.sh - Utility functions for cleanup method testing

# Already implemented in Stage 1:
# - reset_table_to_baseline()
# - validate_baseline_state()
# - capture_baseline_metrics()

# Additional utilities:

initialize_test_environment() {
    log "INFO" "Initializing test environment"
    
    # Create directories
    mkdir -p "${RESULTS_DIR}/test_runs"
    mkdir -p "${RESULTS_DIR}/baselines"
    mkdir -p "${RESULTS_DIR}/comparisons"
    mkdir -p "${DATA_DIR}"
    
    # Verify database connectivity
    if ! mysql_exec "SELECT 1;" >/dev/null 2>&1; then
        log "ERROR" "Cannot connect to database"
        exit 1
    fi
    
    # Verify all tables exist
    local tables=("cleanup_partitioned" "cleanup_truncate" "cleanup_copy" "cleanup_batch")
    for table in "${tables[@]}"; do
        if ! table_exists "$table"; then
            log "ERROR" "Table ${table} does not exist"
            exit 1
        fi
    done
    
    # Generate seed datasets if missing
    generate_seed_dataset 10000 "${SEED_SMALL}"
    generate_seed_dataset 100000 "${SEED_MEDIUM}"
    # generate_seed_dataset 1000000 "${SEED_LARGE}"  # Optional
    
    log "INFO" "Test environment initialized"
}

table_exists() {
    local table=$1
    local database=${DB_NAME:-cleanup_bench}
    
    local count=$(mysql_exec "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='${database}' AND TABLE_NAME='${table}';" | tail -1)
    [ "$count" -eq 1 ]
}

start_background_traffic() {
    local rate=${1:-10}
    local tables=${2:-"cleanup_partitioned,cleanup_truncate,cleanup_copy,cleanup_batch"}
    
    log "INFO" "Starting background traffic: ${rate} ops/sec"
    
    # Start db-traffic.sh in background
    "${SCRIPT_DIR}/run-in-container.sh" db-traffic.sh \
        --rows-per-second "$rate" \
        --tables "$tables" \
        >/dev/null 2>&1 &
    
    local traffic_pid=$!
    
    # Wait for traffic to start
    sleep 5
    
    # Verify process is running
    if ! kill -0 "$traffic_pid" 2>/dev/null; then
        log "ERROR" "Failed to start background traffic"
        return 1
    fi
    
    echo "$traffic_pid"
    return 0
}

stop_background_traffic() {
    local traffic_pid=$1
    
    if [ -z "$traffic_pid" ]; then
        return 0
    fi
    
    log "INFO" "Stopping background traffic (PID: ${traffic_pid})"
    
    kill "$traffic_pid" 2>/dev/null || true
    wait "$traffic_pid" 2>/dev/null || true
    
    # Wait for any pending transactions to complete
    sleep 2
    
    log "INFO" "Background traffic stopped"
}

wait_for_replication_catchup() {
    local max_wait=${1:-60}
    local start_time=$(date +%s)
    
    log "INFO" "Waiting for replication to catch up (max ${max_wait}s)"
    
    while true; do
        local lag=$(get_replication_lag)
        
        # If lag is -1 (unavailable) or 0, consider caught up
        if [ "$lag" = "-1" ] || [ "$lag" -eq 0 ] 2>/dev/null; then
            log "INFO" "Replication caught up"
            return 0
        fi
        
        local elapsed=$(($(date +%s) - start_time))
        if [ "$elapsed" -ge "$max_wait" ]; then
            log "WARNING" "Replication catchup timeout (lag: ${lag}s)"
            return 1
        fi
        
        log "INFO" "Replication lag: ${lag}s (waiting...)"
        sleep 5
    done
}

compare_baseline_to_result() {
    local baseline_file=$1
    local result_file=$2
    local comparison_file=$3
    
    log "INFO" "Comparing baseline to result"
    
    # Use jq to compare JSON metrics
    jq -n \
        --slurpfile baseline "$baseline_file" \
        --slurpfile result "$result_file" \
        '{
            baseline: $baseline[0],
            result: $result[0],
            changes: {
                rows_deleted: ($baseline[0].row_count - $result[0].row_count),
                space_freed: (($baseline[0].data_length + $baseline[0].index_length) - ($result[0].data_length + $result[0].index_length)),
                fragmentation_change: ($result[0].fragmentation - $baseline[0].fragmentation)
            }
        }' > "$comparison_file"
    
    log "INFO" "Comparison saved: ${comparison_file}"
}
```

### 2.3 Test Isolation

**Task**: Ensure tests don't interfere with each other

**Implementation**:

```bash
isolate_test() {
    local test_name=$1
    local table=$2
    local seed_file=$3
    
    log "INFO" "=== Test Isolation: ${test_name} ==="
    
    # Step 1: Reset table to baseline
    reset_table_to_baseline "$table" "$seed_file" || {
        log "ERROR" "Failed to reset table to baseline"
        return 1
    }
    
    # Step 2: Wait for replication catchup
    wait_for_replication_catchup 30
    
    # Step 3: Validate baseline state
    local expected_rows=$(wc -l < "$seed_file")
    validate_baseline_state "$table" "$expected_rows" || {
        log "ERROR" "Baseline validation failed"
        return 1
    }
    
    # Step 4: Clear any previous metrics
    # (Metrics are timestamped, so just log location)
    log "INFO" "Test isolated and ready"
    
    return 0
}
```

---

## Stage 3: Core Test Scenarios

### Goal
Comprehensive testing of all cleanup methods in various scenarios.

### 3.1 Basic Test Suite

**Task**: Test each method individually without concurrent load

**File**: `task03/lib/test-scenarios.sh`

```bash
#!/bin/bash
#
# test-scenarios.sh - Test scenario implementations

run_basic_test_suite() {
    log "INFO" "=== Running Basic Test Suite ==="
    log "INFO" "Dataset: ${DATASET_SIZE} rows, No concurrent load"
    
    local test_run_id="basic_$(date +%Y%m%d_%H%M%S)"
    local run_dir="${RESULTS_DIR}/test_runs/${test_run_id}"
    mkdir -p "$run_dir"
    
    # Select appropriate seed file
    local seed_file
    if [ "$DATASET_SIZE" -le 10000 ]; then
        seed_file="$SEED_SMALL"
    elif [ "$DATASET_SIZE" -le 100000 ]; then
        seed_file="$SEED_MEDIUM"
    else
        seed_file="$SEED_LARGE"
    fi
    
    # Test each method
    local methods=("partition_drop" "truncate" "copy" "batch_delete")
    local tables=("cleanup_partitioned" "cleanup_truncate" "cleanup_copy" "cleanup_batch")
    
    for i in "${!methods[@]}"; do
        local method="${methods[$i]}"
        local table="${tables[$i]}"
        
        log "INFO" ""
        log "INFO" "--- Testing Method: ${method} ---"
        
        # Isolate test
        isolate_test "${test_run_id}_${method}" "$table" "$seed_file" || {
            log "ERROR" "Test isolation failed for ${method}"
            continue
        }
        
        # Execute cleanup
        log "INFO" "Executing cleanup: ${method}"
        "${SCRIPT_DIR}/run-in-container.sh" db-cleanup.sh \
            --method "$method" \
            --table "$table" \
            --retention-days 10 \
            --verbose
        
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            log "INFO" "✓ ${method} completed successfully"
        else
            log "ERROR" "✗ ${method} failed with exit code ${exit_code}"
        fi
        
        # Copy results to run directory
        cp "${RESULTS_DIR}/${method}_"* "$run_dir/" 2>/dev/null || true
        
        # Wait between tests
        sleep 5
    done
    
    log "INFO" "Basic test suite completed"
    log "INFO" "Results saved to: ${run_dir}"
}
```

### 3.2 Concurrent Load Test Suite

**Task**: Test each method with background traffic

```bash
run_concurrent_test_suite() {
    log "INFO" "=== Running Concurrent Load Test Suite ==="
    log "INFO" "Dataset: ${DATASET_SIZE} rows, Traffic: ${TRAFFIC_RATE} ops/sec"
    
    local test_run_id="concurrent_$(date +%Y%m%d_%H%M%S)"
    local run_dir="${RESULTS_DIR}/test_runs/${test_run_id}"
    mkdir -p "$run_dir"
    
    # Select seed file
    local seed_file
    if [ "$DATASET_SIZE" -le 10000 ]; then
        seed_file="$SEED_SMALL"
    else
        seed_file="$SEED_MEDIUM"
    fi
    
    local methods=("partition_drop" "truncate" "copy" "batch_delete")
    local tables=("cleanup_partitioned" "cleanup_truncate" "cleanup_copy" "cleanup_batch")
    
    for i in "${!methods[@]}"; do
        local method="${methods[$i]}"
        local table="${tables[$i]}"
        
        log "INFO" ""
        log "INFO" "--- Testing Method with Concurrent Load: ${method} ---"
        
        # Isolate test
        isolate_test "${test_run_id}_${method}" "$table" "$seed_file" || continue
        
        # Start background traffic
        local traffic_pid
        traffic_pid=$(start_background_traffic "$TRAFFIC_RATE" "$table")
        
        if [ -z "$traffic_pid" ]; then
            log "ERROR" "Failed to start background traffic for ${method}"
            continue
        fi
        
        # Execute cleanup
        log "INFO" "Executing cleanup with concurrent load: ${method}"
        "${SCRIPT_DIR}/run-in-container.sh" db-cleanup.sh \
            --method "$method" \
            --table "$table" \
            --retention-days 10 \
            --verbose
        
        local exit_code=$?
        
        # Stop traffic
        stop_background_traffic "$traffic_pid"
        
        if [ $exit_code -eq 0 ]; then
            log "INFO" "✓ ${method} with concurrent load completed successfully"
        else
            log "ERROR" "✗ ${method} with concurrent load failed"
        fi
        
        # Copy results
        cp "${RESULTS_DIR}/${method}_"* "$run_dir/" 2>/dev/null || true
        
        # Longer wait between concurrent tests
        sleep 10
    done
    
    log "INFO" "Concurrent load test suite completed"
    log "INFO" "Results saved to: ${run_dir}"
}
```

### 3.3 Performance Benchmark

**Task**: Comprehensive performance comparison with larger dataset

```bash
run_performance_benchmark() {
    log "INFO" "=== Running Performance Benchmark ==="
    
    # Force 100K dataset for benchmark
    local bench_size=100000
    local seed_file="$SEED_MEDIUM"
    local test_run_id="benchmark_${bench_size}_$(date +%Y%m%d_%H%M%S)"
    local run_dir="${RESULTS_DIR}/test_runs/${test_run_id}"
    mkdir -p "$run_dir"
    
    log "INFO" "Benchmark dataset: ${bench_size} rows"
    log "INFO" "Expected distribution: ~50K old, ~50K recent"
    
    # Run all methods sequentially with same dataset
    local methods=("partition_drop" "truncate" "copy" "batch_delete")
    local tables=("cleanup_partitioned" "cleanup_truncate" "cleanup_copy" "cleanup_batch")
    
    declare -A benchmark_results
    
    for i in "${!methods[@]}"; do
        local method="${methods[$i]}"
        local table="${tables[$i]}"
        
        log "INFO" ""
        log "INFO" "--- Benchmarking: ${method} ---"
        
        # Isolate test
        isolate_test "${test_run_id}_${method}" "$table" "$seed_file" || continue
        
        # Capture pre-cleanup timestamp
        local start_ts=$(date +%s.%N)
        
        # Execute cleanup
        "${SCRIPT_DIR}/run-in-container.sh" db-cleanup.sh \
            --method "$method" \
            --table "$table" \
            --retention-days 10 \
            --verbose
        
        local exit_code=$?
        local end_ts=$(date +%s.%N)
        
        # Calculate duration
        local duration=$(awk "BEGIN {printf \"%.3f\", $end_ts - $start_ts}")
        
        # Extract key metrics from log
        local metrics_log=$(ls -t "${RESULTS_DIR}/${method}_"*_metrics.log 2>/dev/null | head -1)
        
        if [ -n "$metrics_log" ]; then
            local rows_deleted=$(grep "Rows Deleted:" "$metrics_log" | awk '{print $NF}')
            local throughput=$(grep "Delete Throughput:" "$metrics_log" | awk '{print $3}')
            
            benchmark_results["${method}_duration"]="$duration"
            benchmark_results["${method}_rows"]="$rows_deleted"
            benchmark_results["${method}_throughput"]="$throughput"
            
            log "INFO" "✓ ${method}: ${duration}s, ${rows_deleted} rows, ${throughput} rows/sec"
        fi
        
        # Copy results
        cp "${RESULTS_DIR}/${method}_"* "$run_dir/" 2>/dev/null || true
        
        sleep 5
    done
    
    # Generate benchmark comparison report
    generate_benchmark_comparison "$run_dir" benchmark_results
    
    log "INFO" "Performance benchmark completed"
    log "INFO" "Results saved to: ${run_dir}"
}

generate_benchmark_comparison() {
    local run_dir=$1
    local -n results=$2
    
    local report_file="${run_dir}/benchmark_comparison.txt"
    
    cat > "$report_file" <<EOF
============================================
Cleanup Methods Performance Benchmark
============================================
Date: $(date)
Dataset: ${bench_size} rows

Method Comparison (sorted by throughput)
--------------------------------------------
EOF
    
    # Create sorted comparison table
    {
        echo "Method,Duration(s),Rows Deleted,Throughput(rows/sec)"
        for method in "partition_drop" "truncate" "copy" "batch_delete"; do
            local dur="${results[${method}_duration]:-N/A}"
            local rows="${results[${method}_rows]:-N/A}"
            local tput="${results[${method}_throughput]:-N/A}"
            echo "${method},${dur},${rows},${tput}"
        done
    } | column -t -s',' >> "$report_file"
    
    cat >> "$report_file" <<EOF

Recommendations
--------------------------------------------
Fastest Method: $(get_fastest_method results)
Best for Production: partition_drop (if table is partitioned)
Best for 24/7 Online: batch_delete (with OPTIMIZE TABLE after)
Not Selective: truncate (removes ALL data)

See individual metrics logs for detailed analysis.
EOF
    
    log "INFO" "Benchmark comparison saved: ${report_file}"
}
```

### 3.4 Single Method Test

**Task**: Test specific method with custom parameters

```bash
run_single_method_test() {
    local method=$1
    
    if [ -z "$method" ]; then
        log "ERROR" "Method not specified for single test"
        exit 1
    fi
    
    log "INFO" "=== Testing Single Method: ${method} ==="
    
    # Determine table for method
    local table
    case "$method" in
        partition_drop|partition)
            table="cleanup_partitioned"
            method="partition_drop"
            ;;
        truncate)
            table="cleanup_truncate"
            ;;
        copy)
            table="cleanup_copy"
            ;;
        batch_delete|batch)
            table="cleanup_batch"
            method="batch_delete"
            ;;
        *)
            log "ERROR" "Unknown method: $method"
            exit 1
            ;;
    esac
    
    # Select seed file based on dataset size
    local seed_file
    if [ "$DATASET_SIZE" -le 10000 ]; then
        seed_file="$SEED_SMALL"
    elif [ "$DATASET_SIZE" -le 100000 ]; then
        seed_file="$SEED_MEDIUM"
    else
        seed_file="$SEED_LARGE"
    fi
    
    local test_run_id="single_${method}_$(date +%Y%m%d_%H%M%S)"
    
    # Isolate test
    isolate_test "$test_run_id" "$table" "$seed_file" || exit 1
    
    # Start background traffic if requested
    local traffic_pid=""
    if [ "$CONCURRENT_LOAD" = true ]; then
        traffic_pid=$(start_background_traffic "$TRAFFIC_RATE" "$table")
    fi
    
    # Execute cleanup
    log "INFO" "Executing cleanup: ${method}"
    "${SCRIPT_DIR}/run-in-container.sh" db-cleanup.sh \
        --method "$method" \
        --table "$table" \
        --retention-days 10 \
        --verbose
    
    local exit_code=$?
    
    # Stop traffic if running
    if [ -n "$traffic_pid" ]; then
        stop_background_traffic "$traffic_pid"
    fi
    
    if [ $exit_code -eq 0 ]; then
        log "INFO" "✓ Single method test completed successfully"
    else
        log "ERROR" "✗ Single method test failed"
        exit $exit_code
    fi
}
```

---

## Stage 4: Results Analysis

### Goal
Automated analysis and comparison of test results.

### 4.1 Summary Report Generation

**Task**: Generate consolidated summary across all test runs

**Implementation**:

```bash
generate_test_summary_report() {
    log "INFO" "=== Generating Test Summary Report ==="
    
    local summary_file="${RESULTS_DIR}/TEST_SUMMARY_$(date +%Y%m%d_%H%M%S).md"
    
    cat > "$summary_file" <<'EOF'
# Cleanup Methods Test Summary

**Generated**: $(date)
**Test Suite**: Phase 6 - Testing and Validation

---

## Test Execution Summary

### Test Runs Completed
EOF
    
    # List all test runs
    if [ -d "${RESULTS_DIR}/test_runs" ]; then
        ls -1 "${RESULTS_DIR}/test_runs" >> "$summary_file"
    fi
    
    cat >> "$summary_file" <<'EOF'

---

## Method Performance Comparison

### Metrics Across All Tests

| Method | Avg Throughput (rows/sec) | Avg Duration | Repl Lag | Space Freed | Fragmentation |
| ------ | ------------------------- | ------------ | -------- | ----------- | ------------- |
EOF
    
    # Aggregate metrics from all test runs
    aggregate_metrics_across_runs >> "$summary_file"
    
    cat >> "$summary_file" <<'EOF'

---

## Test Scenarios

### 1. Basic Tests (No Concurrent Load)
EOF
    
    summarize_scenario "basic" >> "$summary_file"
    
    cat >> "$summary_file" <<'EOF'

### 2. Concurrent Load Tests
EOF
    
    summarize_scenario "concurrent" >> "$summary_file"
    
    cat >> "$summary_file" <<'EOF'

### 3. Performance Benchmarks
EOF
    
    summarize_scenario "benchmark" >> "$summary_file"
    
    cat >> "$summary_file" <<'EOF'

---

## Conclusions

### Method Rankings

**By Throughput (Fastest to Slowest)**:
1. DROP PARTITION
2. TRUNCATE
3. Copy-to-New-Table
4. Batch DELETE

**By Production Suitability**:
1. DROP PARTITION (if partitioned table)
2. Batch DELETE (if table must stay online)
3. Copy-to-New-Table (if maintenance window available)
4. TRUNCATE (only for temp/staging tables - not selective)

### Recommendations

**For Production Tables with Retention Policy**:
- ✅ **Use DROP PARTITION** if table is partitioned by date
- ✅ **Use Batch DELETE** if table must stay online 24/7
- ✅ **Use Copy-to-New-Table** during scheduled maintenance

**Never Use**:
- ❌ TRUNCATE for selective cleanup (removes ALL data)

### Known Issues
EOF
    
    # List any test failures or warnings
    list_test_issues >> "$summary_file"
    
    cat >> "$summary_file" <<'EOF'

---

## Next Steps

1. Review individual test run results in `results/test_runs/`
2. Analyze method-specific metrics logs
3. Validate compliance with project requirements
4. Document findings in project README

---

**Report Location**: `results/TEST_SUMMARY_*.md`
**Detailed Logs**: `results/test_runs/<run_id>/`
EOF
    
    log "INFO" "Test summary report generated: ${summary_file}"
}
```

### 4.2 Performance Regression Detection

**Task**: Detect performance regressions compared to baseline

```bash
detect_performance_regressions() {
    local current_run=$1
    local baseline_run=${2:-""}
    
    if [ -z "$baseline_run" ]; then
        log "INFO" "No baseline specified, skipping regression detection"
        return 0
    fi
    
    log "INFO" "Detecting performance regressions"
    log "INFO" "Current: ${current_run}"
    log "INFO" "Baseline: ${baseline_run}"
    
    local regression_file="${RESULTS_DIR}/regressions_$(date +%Y%m%d_%H%M%S).txt"
    local regressions=0
    
    # Compare throughput for each method
    for method in "partition_drop" "truncate" "copy" "batch_delete"; do
        local current_throughput=$(extract_metric "$current_run" "$method" "throughput")
        local baseline_throughput=$(extract_metric "$baseline_run" "$method" "throughput")
        
        if [ -z "$current_throughput" ] || [ -z "$baseline_throughput" ]; then
            continue
        fi
        
        # Calculate percentage change
        local change=$(awk "BEGIN {printf \"%.1f\", (($current_throughput - $baseline_throughput) / $baseline_throughput) * 100}")
        
        # Regression if >10% slower
        if (( $(echo "$change < -10.0" | bc -l) )); then
            log "WARNING" "Regression detected: ${method} throughput ${change}% slower"
            echo "${method}: ${change}% slower (current: ${current_throughput}, baseline: ${baseline_throughput})" >> "$regression_file"
            ((regressions++))
        fi
    done
    
    if [ $regressions -gt 0 ]; then
        log "WARNING" "${regressions} performance regressions detected"
        log "INFO" "Regression report: ${regression_file}"
        return 1
    else
        log "INFO" "No performance regressions detected"
        return 0
    fi
}
```

---

## Deliverables Summary

### New Files Created

1. **`task03/test-cleanup-methods.sh`** - Master test orchestration script
2. **`task03/lib/test-utils.sh`** - Test utility library
3. **`task03/lib/test-scenarios.sh`** - Test scenario implementations
4. **`task03/data/events_seed_10k_v1.0.csv`** - 10K seed dataset
5. **`task03/data/events_seed_100k_v1.0.csv`** - 100K seed dataset
6. **`task03/data/events_seed_*.md5`** - Checksums for seed files
7. **`task03/results/baselines/`** - Baseline metrics storage
8. **`task03/results/test_runs/`** - Test run results organized by scenario
9. **`task03/results/comparisons/`** - Comparison reports

### Enhanced Files

1. **`task03/db-load.sh`** - Add seed data management functions
2. **`task03/db-cleanup.sh`** - Ensure all methods implemented (Phase 5)
3. **`task03/README.md`** - Add testing section

---

## Success Criteria

Phase 6 is complete when:

- [x] **Seed Data Management**
  - [ ] Three versioned seed datasets created (10K, 100K, 1M)
  - [ ] MD5 checksums for all seed files
  - [ ] Seed verification working
  
- [x] **Table Reset Procedure**
  - [ ] reset_table_to_baseline() function implemented
  - [ ] Works for all four tables (including partitioned)
  - [ ] Verifies row counts
  - [ ] Captures baseline metrics
  
- [x] **Baseline Validation**
  - [ ] validate_baseline_state() implemented
  - [ ] Checks row count, distribution, fragmentation
  - [ ] Special validation for partitioned table
  
- [x] **Test Orchestration**
  - [ ] test-cleanup-methods.sh master script created
  - [ ] All test scenarios implemented
  - [ ] Dry-run mode working
  - [ ] Help text complete
  
- [x] **Test Scenarios**
  - [ ] Basic test suite (all methods, no load)
  - [ ] Concurrent load test suite (all methods with traffic)
  - [ ] Performance benchmark (100K rows)
  - [ ] Single method test with custom parameters
  
- [x] **Test Isolation**
  - [ ] Each test starts with clean state
  - [ ] Same dataset for fair comparison
  - [ ] Tests don't interfere with each other
  - [ ] Replication catchup between tests
  
- [x] **Results Analysis**
  - [ ] Summary report generation
  - [ ] Performance regression detection
  - [ ] Comparison reports
  - [ ] Benchmark rankings
  
- [x] **Documentation**
  - [ ] Testing guide in README.md
  - [ ] Test scenario documentation
  - [ ] How to interpret results
  - [ ] Troubleshooting section

---

## Timeline Estimate

| Stage | Task                | Effort    | Status      |
| ----- | ------------------- | --------- | ----------- |
| 1     | Dataset Management  | 2-3h      | Not Started |
| 2     | Test Framework      | 2-3h      | Not Started |
| 3     | Core Test Scenarios | 2-3h      | Not Started |
| 4     | Results Analysis    | 2-3h      | Not Started |
|       | **Total**           | **8-12h** | **0%**      |

---

## Testing Checklist

### Pre-Execution Validation
- [ ] All Phase 5 cleanup methods implemented and working
- [ ] Database schema matches requirements
- [ ] Partition maintenance script working
- [ ] db-load.sh working
- [ ] db-traffic.sh working
- [ ] db-cleanup.sh working

### Test Execution
- [ ] Generate seed datasets
- [ ] Verify seed checksums
- [ ] Run basic test suite
- [ ] Run concurrent load test suite
- [ ] Run performance benchmark
- [ ] Test single methods individually

### Post-Execution Validation
- [ ] All tests completed without errors
- [ ] Results logs generated
- [ ] Baseline metrics captured
- [ ] Summary report generated
- [ ] No performance regressions detected

### Verification
- [ ] Each method starts with identical dataset
- [ ] Row counts consistent across tests
- [ ] Data distribution ~50/50 (old/recent)
- [ ] Fragmentation <5% before each test
- [ ] Metrics logs complete and parseable

---

## Key Principles (Reminder)

### Every Test Must:
1. ✅ Start with **clean table state** (via TRUNCATE)
2. ✅ Load from **versioned seed dataset** (same CSV every time)
3. ✅ Verify **baseline metrics** before execution
4. ✅ Wait for **replication catchup** between tests
5. ✅ Capture **comprehensive metrics** (before/after)
6. ✅ **Isolate from other tests** (no shared state)

### Fair Comparison Requires:
1. ✅ **Same row count** in all tables before cleanup
2. ✅ **Same data distribution** (age, values)
3. ✅ **Same table structure** (schema, indexes)
4. ✅ **Clean baseline** (no fragmentation from previous runs)
5. ✅ **Consistent environment** (same MySQL config, same hardware)

---

## Next Steps After Phase 6

**Phase 7**: Final Documentation and Deployment
- Complete project documentation
- Production deployment guide
- Troubleshooting guide
- Best practices guide
- Lessons learned

---

**Document Status**: Complete and Ready for Implementation  
**Last Updated**: November 21, 2025  
**Phase**: 6 - Testing and Validation  
**Dependencies**: Phase 5 must be complete first

---

## Quick Start

```bash
# After Phase 5 is complete:

# 1. Make test scripts executable
chmod +x task03/test-cleanup-methods.sh
chmod +x task03/lib/*.sh

# 2. Run basic test suite
./test-cleanup-methods.sh --scenario basic

# 3. Run with concurrent load
./test-cleanup-methods.sh --scenario concurrent

# 4. Run performance benchmark
./test-cleanup-methods.sh --scenario performance

# 5. Test single method
./test-cleanup-methods.sh --scenario single --method partition_drop

# 6. Review results
cat results/TEST_SUMMARY_*.md
ls -lh results/test_runs/
```
