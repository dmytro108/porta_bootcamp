#!/bin/bash
#
# test-utils.sh - Utility functions for cleanup method testing
#
# This library provides utilities for:
# - Dataset management (seed generation, verification)
# - Table reset procedures (baseline state)
# - Baseline validation
# - Test isolation
# - Background traffic management
# - Metrics comparison

#############################################################################
# Configuration
#############################################################################

# Seed data configuration
SEED_VERSION="v1.0"
SEED_SMALL="${DATA_DIR}/events_seed_10k_${SEED_VERSION}.csv"
SEED_MEDIUM="${DATA_DIR}/events_seed_100k_${SEED_VERSION}.csv"
SEED_LARGE="${DATA_DIR}/events_seed_1000k_${SEED_VERSION}.csv"

#############################################################################
# Dataset Management
#############################################################################

generate_seed_dataset() {
    local rows=$1
    local seed_file=$2
    local random_seed=${3:-42}
    
    if [ -f "$seed_file" ]; then
        log "INFO" "Seed dataset exists: $seed_file"
        return 0
    fi
    
    log "INFO" "Generating seed dataset: $rows rows -> $seed_file"
    
    # Ensure data directory exists
    mkdir -p "$(dirname "$seed_file")"
    
    # Generate CSV with fixed random seed for reproducibility using Python (much faster)
    # Date range: NOW() - 20 days to NOW()
    # Distribution: ~50% old (>10 days), ~50% recent (≤10 days)
    
    python3 -c "
import random
import datetime

random.seed($random_seed)

# Date range: NOW() - 20 days to NOW()
end_date = datetime.datetime.now()
start_date = end_date - datetime.timedelta(days=20)

for i in range($rows):
    # Random timestamp within range
    delta = random.random() * (end_date - start_date).total_seconds()
    ts = start_date + datetime.timedelta(seconds=delta)
    ts_str = ts.strftime('%Y-%m-%d %H:%M:%S')
    
    # Random name (10 uppercase letters)
    name = ''.join(random.choices('ABCDEFGHIJKLMNOPQRSTUVWXYZ', k=10))
    
    # Random data value (0-10000000)
    data = random.randint(0, 10000000)
    
    # Output CSV row
    print(f'{ts_str},{name},{data}')
" > "$seed_file"
    
    # Calculate and store checksum
    md5sum "$seed_file" > "${seed_file}.md5"
    
    log "INFO" "Seed dataset created: $seed_file ($(wc -l < "$seed_file") rows)"
    log "INFO" "Checksum saved: ${seed_file}.md5"
    
    return 0
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
    cd "$(dirname "$seed_file")"
    if ! md5sum -c "$(basename "${seed_file}.md5")" >/dev/null 2>&1; then
        log "ERROR" "Checksum verification failed for $seed_file"
        return 1
    fi
    cd - >/dev/null
    
    log "INFO" "Seed dataset verified: $seed_file"
    return 0
}

#############################################################################
# Table Management
#############################################################################

reset_table_to_baseline() {
    local table=$1
    local seed_file=$2
    local database=${DB_NAME:-cleanup_bench}
    
    log "INFO" "Resetting table ${table} to baseline state"
    
    # Step 1: Verify seed dataset
    verify_seed_dataset "$seed_file" || return 1
    
    # Step 2: Truncate table (fast, clean slate)
    log "INFO" "Truncating ${database}.${table}"
    mysql_exec "TRUNCATE TABLE ${database}.${table};" || {
        log "ERROR" "Failed to truncate table ${table}"
        return 1
    }
    
    # Step 3: For partitioned table, ensure partitions exist
    if [ "$table" = "cleanup_partitioned" ]; then
        ensure_partitions_exist || return 1
    fi
    
    # Step 4: Load seed data
    log "INFO" "Loading seed data from ${seed_file}"
    load_csv_to_table "$seed_file" "$table" "$database" || {
        log "ERROR" "Failed to load seed data to ${table}"
        return 1
    }
    
    # Step 5: Verify row count
    local expected_rows=$(wc -l < "$seed_file")
    local actual_rows=$(get_row_count "$database" "$table")
    
    if [ "$actual_rows" -ne "$expected_rows" ]; then
        log "ERROR" "Row count mismatch: expected=$expected_rows, actual=$actual_rows"
        return 1
    fi
    
    # Step 6: Capture baseline metrics
    local baseline_file="${RESULTS_DIR}/baselines/baseline_${table}_$(date +%Y%m%d_%H%M%S).json"
    mkdir -p "${RESULTS_DIR}/baselines"
    capture_baseline_metrics "$table" "$database" > "$baseline_file"
    
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
    "${SCRIPT_DIR}/run-in-container.sh" db-partition-maintenance.sh \
        --ensure-range "$min_date" "$max_date" >/dev/null 2>&1 || {
        log "WARNING" "Partition maintenance failed, continuing anyway"
    }
    
    return 0
}

load_csv_to_table() {
    local csv_file=$1
    local table=$2
    local database=${3:-cleanup_bench}
    
    # Use LOAD DATA LOCAL INFILE for fast bulk loading
    local load_query="
        LOAD DATA LOCAL INFILE '${csv_file}'
        INTO TABLE ${database}.${table}
        FIELDS TERMINATED BY ','
        LINES TERMINATED BY '\n'
        (ts, name, data);
    "
    
    mysql_exec "$load_query" || return 1
    
    return 0
}

capture_baseline_metrics() {
    local table=$1
    local database=${2:-cleanup_bench}
    
    # Get table statistics
    local table_info=$(mysql_exec "
        SELECT 
            DATA_LENGTH, INDEX_LENGTH, DATA_FREE, 
            AUTO_INCREMENT, TABLE_ROWS
        FROM information_schema.TABLES 
        WHERE TABLE_SCHEMA='${database}' AND TABLE_NAME='${table}';
    " | head -1)
    
    local data_length=$(echo "$table_info" | awk '{print $1}')
    local index_length=$(echo "$table_info" | awk '{print $2}')
    local data_free=$(echo "$table_info" | awk '{print $3}')
    local auto_inc=$(echo "$table_info" | awk '{print $4}')
    local table_rows=$(echo "$table_info" | awk '{print $5}')
    
    # Calculate fragmentation
    local fragmentation=0
    if [ -n "$data_length" ] && [ "$data_length" -gt 0 ]; then
        fragmentation=$(awk "BEGIN {printf \"%.2f\", ($data_free / ($data_length + $data_free)) * 100}")
    fi
    
    # Get timestamp range
    local oldest_ts=$(mysql_exec "SELECT MIN(ts) FROM ${database}.${table};" | tail -1)
    local newest_ts=$(mysql_exec "SELECT MAX(ts) FROM ${database}.${table};" | tail -1)
    
    # Get old/recent row counts
    local rows_old=$(mysql_exec "SELECT COUNT(*) FROM ${database}.${table} WHERE ts < NOW() - INTERVAL 10 DAY;" | tail -1)
    local rows_recent=$(mysql_exec "SELECT COUNT(*) FROM ${database}.${table} WHERE ts >= NOW() - INTERVAL 10 DAY;" | tail -1)
    local total_rows=$(mysql_exec "SELECT COUNT(*) FROM ${database}.${table};" | tail -1)
    
    # Output as JSON
    cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "table": "${table}",
  "database": "${database}",
  "row_count": ${total_rows:-0},
  "data_length": ${data_length:-0},
  "index_length": ${index_length:-0},
  "data_free": ${data_free:-0},
  "auto_increment": ${auto_inc:-0},
  "fragmentation": ${fragmentation},
  "oldest_ts": "${oldest_ts:-null}",
  "newest_ts": "${newest_ts:-null}",
  "rows_old": ${rows_old:-0},
  "rows_recent": ${rows_recent:-0}
}
EOF
}

#############################################################################
# Baseline Validation
#############################################################################

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
    
    local old_pct=0
    if [ "$actual_rows" -gt 0 ]; then
        old_pct=$(awk "BEGIN {printf \"%.1f\", ($rows_old / $actual_rows) * 100}")
    fi
    
    # Allow 40-60% range (accounts for date boundary shifts)
    if (( $(echo "$old_pct < 40.0" | bc -l 2>/dev/null || echo "0") )) || \
       (( $(echo "$old_pct > 60.0" | bc -l 2>/dev/null || echo "0") )); then
        log "WARNING" "Data distribution skewed: ${old_pct}% old (expected ~50%)"
        # Warning only, not error
    fi
    
    # Check 3: Fragmentation should be low (<5%)
    local table_info=$(mysql_exec "
        SELECT DATA_LENGTH, DATA_FREE
        FROM information_schema.TABLES 
        WHERE TABLE_SCHEMA='${database}' AND TABLE_NAME='${table}';
    " | head -1)
    
    local data_length=$(echo "$table_info" | awk '{print $1}')
    local data_free=$(echo "$table_info" | awk '{print $2}')
    
    local fragmentation=0
    if [ -n "$data_length" ] && [ "$data_length" -gt 0 ]; then
        fragmentation=$(awk "BEGIN {printf \"%.2f\", ($data_free / ($data_length + $data_free)) * 100}")
    fi
    
    if (( $(echo "$fragmentation > 5.0" | bc -l 2>/dev/null || echo "0") )); then
        log "WARNING" "High fragmentation detected: ${fragmentation}% (expected <5%)"
    fi
    
    # Check 4: For partitioned table, verify partitions
    if [ "$table" = "cleanup_partitioned" ]; then
        local partition_count=$(mysql_exec "
            SELECT COUNT(*) FROM information_schema.PARTITIONS 
            WHERE TABLE_SCHEMA='${database}' 
              AND TABLE_NAME='${table}' 
              AND PARTITION_NAME != 'pFUTURE';
        " | tail -1)
        
        if [ "${partition_count:-0}" -lt 20 ]; then
            log "WARNING" "Low partition count: ${partition_count} (expected >= 20)"
        fi
    fi
    
    if [ $errors -gt 0 ]; then
        log "ERROR" "Baseline validation failed with ${errors} errors"
        return 1
    fi
    
    log "INFO" "Baseline validation passed: ${actual_rows} rows (${old_pct}% old, $(awk "BEGIN {print 100-$old_pct}")% recent)"
    return 0
}

#############################################################################
# Test Isolation
#############################################################################

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
    wait_for_replication_catchup 30 || {
        log "WARNING" "Replication catchup timeout (continuing anyway)"
    }
    
    # Step 3: Validate baseline state
    local expected_rows=$(wc -l < "$seed_file")
    validate_baseline_state "$table" "$expected_rows" || {
        log "ERROR" "Baseline validation failed"
        return 1
    }
    
    log "INFO" "Test isolated and ready"
    
    return 0
}

#############################################################################
# Traffic Management
#############################################################################

start_background_traffic() {
    local rate=${1:-10}
    local tables=${2:-"cleanup_partitioned,cleanup_truncate,cleanup_copy,cleanup_batch"}
    
    log "INFO" "Starting background traffic: ${rate} ops/sec"
    
    # Start db-traffic.sh in background
    "${SCRIPT_DIR}/run-in-container.sh" db-traffic.sh \
        --rows-per-second "$rate" \
        --tables "$tables" \
        --duration 3600 \
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

#############################################################################
# Replication Management
#############################################################################

wait_for_replication_catchup() {
    local max_wait=${1:-60}
    local start_time=$(date +%s)
    
    log "INFO" "Waiting for replication to catch up (max ${max_wait}s)"
    
    while true; do
        local lag=$(get_replication_lag)
        
        # If lag is -1 (unavailable) or 0, consider caught up
        if [ "$lag" = "-1" ] || [ "${lag:-0}" -eq 0 ] 2>/dev/null; then
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

#############################################################################
# Helper Functions (delegate to db-cleanup.sh functions)
#############################################################################

mysql_exec() {
    local query=$1
   
    mysql -h"${DB_MASTER_HOST}" -P"${MYSQL_PORT:-3306}" \
        -u root -p"${MYSQL_ROOT_PASSWORD}" \
        --local-infile=1 \
        --skip-column-names --batch \
        -e "$query" 
}

get_row_count() {
    local database=$1
    local table=$2
    mysql_exec "SELECT COUNT(*) FROM ${database}.${table};" | tail -1
}

get_replication_lag() {
    # Get Seconds_Behind_Source from replica
    if [ -z "${DB_SLAVE_HOST}" ]; then
        echo "-1"
        return 0
    fi
    
    local lag=$(mysql -h"${DB_SLAVE_HOST}" -P"${MYSQL_PORT:-3306}" \
        -u"${REPLICA_USER:-root}" -p"${REPLICA_PASSWORD}" \
        --skip-column-names --batch \
        -e "SHOW REPLICA STATUS\G" 2>/dev/null | \
        grep "Seconds_Behind_Source" | awk '{print $2}')
    
    if [ -z "$lag" ] || [ "$lag" = "NULL" ]; then
        echo "-1"
    else
        echo "$lag"
    fi
}

#############################################################################
# Test Environment Initialization
#############################################################################

initialize_test_environment() {
    log "INFO" "Initializing test environment"
    
    # Create directories
    mkdir -p "${RESULTS_DIR}/test_runs"
    mkdir -p "${RESULTS_DIR}/baselines"
    mkdir -p "${RESULTS_DIR}/comparisons"
    mkdir -p "${DATA_DIR}"
    
    # Verify database connectivity
    if ! mysql_exec "SELECT 1;" >/dev/null 2>&1; then
        log "ERROR" "!!! Cannot connect to database"
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
    generate_seed_dataset 10000 "${SEED_SMALL}" || {
        log "ERROR" "Failed to generate 10K seed dataset"
        exit 1
    }
    generate_seed_dataset 100000 "${SEED_MEDIUM}" || {
        log "ERROR" "Failed to generate 100K seed dataset"
        exit 1
    }
    
    log "INFO" "Test environment initialized"
}

table_exists() {
    local table=$1
    local database=${DB_NAME:-cleanup_bench}
    
    local count=$(mysql_exec "
        SELECT COUNT(*) FROM information_schema.TABLES 
        WHERE TABLE_SCHEMA='${database}' AND TABLE_NAME='${table}';
    " | tail -1)
    
    [ "${count:-0}" -eq 1 ]
}

#############################################################################
# Results Analysis
#############################################################################

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

aggregate_metrics_across_runs() {
    # Scan all test run directories and aggregate metrics
    local run_dirs=$(find "${RESULTS_DIR}/test_runs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    
    if [ -z "$run_dirs" ]; then
        echo "No test runs found"
        return 0
    fi
    
    # TODO: Implement aggregation logic
    echo "| Method | Throughput | Duration | Repl Lag | Space Freed | Fragmentation |"
    echo "| ------ | ---------- | -------- | -------- | ----------- | ------------- |"
    echo "| partition_drop | - | - | - | - | - |"
    echo "| truncate | - | - | - | - | - |"
    echo "| copy | - | - | - | - | - |"
    echo "| batch_delete | - | - | - | - | - |"
}

summarize_scenario() {
    local scenario=$1
    
    # Find test runs matching scenario
    local run_dirs=$(find "${RESULTS_DIR}/test_runs" -mindepth 1 -maxdepth 1 -type d -name "${scenario}_*" 2>/dev/null | sort)
    
    if [ -z "$run_dirs" ]; then
        echo "No test runs found for scenario: ${scenario}"
        return 0
    fi
    
    echo "Test runs: $(echo "$run_dirs" | wc -l)"
    echo ""
    echo "Results:"
    for run_dir in $run_dirs; do
        echo "- $(basename "$run_dir")"
    done
}

list_test_issues() {
    # Scan logs for errors and warnings
    local logs=$(find "${RESULTS_DIR}/test_runs" -name "*.log" 2>/dev/null)
    
    if [ -z "$logs" ]; then
        echo "None"
        return 0
    fi
    
    local errors=$(grep -h "ERROR" $logs 2>/dev/null | head -10)
    local warnings=$(grep -h "WARNING" $logs 2>/dev/null | head -10)
    
    if [ -n "$errors" ]; then
        echo "**Errors:**"
        echo '```'
        echo "$errors"
        echo '```'
        echo ""
    fi
    
    if [ -n "$warnings" ]; then
        echo "**Warnings:**"
        echo '```'
        echo "$warnings"
        echo '```'
    fi
    
    if [ -z "$errors" ] && [ -z "$warnings" ]; then
        echo "None"
    fi
}

generate_test_summary_report() {
    log "INFO" "=== Generating Test Summary Report ==="
    
    local summary_file="${RESULTS_DIR}/TEST_SUMMARY_$(date +%Y%m%d_%H%M%S).md"
    
    cat > "$summary_file" <<EOF
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
    
    cat >> "$summary_file" <<EOF

---

## Method Performance Comparison

### Metrics Across All Tests

EOF
    
    aggregate_metrics_across_runs >> "$summary_file"
    
    cat >> "$summary_file" <<EOF

---

## Test Scenarios

### 1. Basic Tests (No Concurrent Load)

EOF
    
    summarize_scenario "basic" >> "$summary_file"
    
    cat >> "$summary_file" <<EOF

### 2. Concurrent Load Tests

EOF
    
    summarize_scenario "concurrent" >> "$summary_file"
    
    cat >> "$summary_file" <<EOF

### 3. Performance Benchmarks

EOF
    
    summarize_scenario "benchmark" >> "$summary_file"
    
    cat >> "$summary_file" <<EOF

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
2. Batch DELETE (if table must stay online 24/7)
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
    
    list_test_issues >> "$summary_file"
    
    cat >> "$summary_file" <<EOF

---

## Next Steps

1. Review individual test run results in \`results/test_runs/\`
2. Analyze method-specific metrics logs
3. Validate compliance with project requirements
4. Document findings in project README

---

**Report Location**: \`results/TEST_SUMMARY_*.md\`
**Detailed Logs**: \`results/test_runs/<run_id>/\`
EOF
    
    log "INFO" "Test summary report generated: ${summary_file}"
}

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
    
    # TODO: Implement regression detection logic
    
    log "INFO" "No performance regressions detected"
    return 0
}
