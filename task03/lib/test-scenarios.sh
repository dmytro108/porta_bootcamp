#!/bin/bash
#
# test-scenarios.sh - Test scenario implementations
#
# Implements test scenarios:
# - Basic test suite (no concurrent load)
# - Concurrent load test suite
# - Performance benchmark
# - Single method test

#############################################################################
# Basic Test Suite
#############################################################################

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

#############################################################################
# Concurrent Load Test Suite
#############################################################################

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
        isolate_test "${test_run_id}_${method}" "$table" "$seed_file" || {
            log "ERROR" "Test isolation failed for ${method}"
            continue
        }
        
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

#############################################################################
# Performance Benchmark
#############################################################################

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
        isolate_test "${test_run_id}_${method}" "$table" "$seed_file" || {
            log "ERROR" "Test isolation failed for ${method}"
            continue
        }
        
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
        
        if [ -n "$metrics_log" ] && [ -f "$metrics_log" ]; then
            local rows_deleted=$(grep "Rows Deleted:" "$metrics_log" | awk '{print $NF}' | head -1)
            local throughput=$(grep "Delete Throughput:" "$metrics_log" | awk '{print $3}' | head -1)
            
            benchmark_results["${method}_duration"]="${duration:-0}"
            benchmark_results["${method}_rows"]="${rows_deleted:-0}"
            benchmark_results["${method}_throughput"]="${throughput:-0}"
            
            log "INFO" "✓ ${method}: ${duration}s, ${rows_deleted} rows, ${throughput} rows/sec"
        else
            log "WARNING" "Metrics log not found for ${method}"
            benchmark_results["${method}_duration"]="${duration:-0}"
            benchmark_results["${method}_rows"]="0"
            benchmark_results["${method}_throughput"]="0"
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
    shift
    local -n results=$1
    
    local report_file="${run_dir}/benchmark_comparison.txt"
    
    cat > "$report_file" <<EOF
============================================
Cleanup Methods Performance Benchmark
============================================
Date: $(date)
Dataset: 100000 rows

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

get_fastest_method() {
    local -n results=$1
    
    local max_throughput=0
    local fastest_method="unknown"
    
    for method in "partition_drop" "truncate" "copy" "batch_delete"; do
        local tput="${results[${method}_throughput]:-0}"
        
        # Compare throughput (handle floating point)
        if (( $(echo "$tput > $max_throughput" | bc -l 2>/dev/null || echo "0") )); then
            max_throughput="$tput"
            fastest_method="$method"
        fi
    done
    
    echo "$fastest_method"
}

#############################################################################
# Single Method Test
#############################################################################

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
    local run_dir="${RESULTS_DIR}/test_runs/${test_run_id}"
    mkdir -p "$run_dir"
    
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
    
    # Copy results
    cp "${RESULTS_DIR}/${method}_"* "$run_dir/" 2>/dev/null || true
    
    if [ $exit_code -eq 0 ]; then
        log "INFO" "✓ Single method test completed successfully"
        log "INFO" "Results saved to: ${run_dir}"
    else
        log "ERROR" "✗ Single method test failed"
        exit $exit_code
    fi
}

#############################################################################
# Run All Scenarios
#############################################################################

run_all_scenarios() {
    log "INFO" "=== Running All Test Scenarios ==="
    
    # Run basic suite
    DATASET_SIZE=10000
    run_basic_test_suite
    
    sleep 10
    
    # Run concurrent suite
    DATASET_SIZE=10000
    run_concurrent_test_suite
    
    sleep 10
    
    # Run performance benchmark
    run_performance_benchmark
    
    log "INFO" "All test scenarios completed"
}
