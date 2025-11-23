#!/bin/bash

#############################################################################
# MySQL Cleanup Benchmark - Main Orchestrator
#
# This script orchestrates the cleanup benchmark process by coordinating
# multiple cleanup methods with comprehensive metrics collection.
#
# Usage:
#   ./db-cleanup.sh [options]
#
# Options:
#   --method METHOD        Cleanup method: partition_drop, truncate, copy, batch_delete
#   --table TABLE          Target table name
#   --batch-size N         Batch size for DELETE method (default: 5000)
#   --test-metrics         Run metrics collection test
#   --verbose              Enable detailed logging
#   -h, --help             Show this help message
#
#############################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"
LIB_DIR="${SCRIPT_DIR}/lib"

# Default values
DATABASE="cleanup_bench"
METHOD=""
TABLE=""
BATCH_SIZE=5000
BATCH_DELAY=0.1
RETENTION_DAYS=10
DRY_RUN=false
VERBOSE=false
TEST_MODE=false

# MySQL connection parameters (will be loaded from environment)
MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
CLEANUP_USER="${CLEANUP_USER:-root}"
CLEANUP_PASSW="${CLEANUP_PASSW:-${MYSQL_ROOT_PASSWORD:-}}"
DB_SLAVE_HOST="${DB_SLAVE_HOST:-db_slave}"

#############################################################################
# Load Modular Libraries
#############################################################################

# Source helper functions
if [[ -f "${LIB_DIR}/helpers.sh" ]]; then
    # shellcheck disable=SC1091
    source "${LIB_DIR}/helpers.sh"
else
    echo "ERROR: helpers.sh not found in ${LIB_DIR}" >&2
    exit 1
fi

# Source metrics functions
if [[ -f "${LIB_DIR}/metrics.sh" ]]; then
    # shellcheck disable=SC1091
    source "${LIB_DIR}/metrics.sh"
else
    log_error "metrics.sh not found in ${LIB_DIR}"
    exit 1
fi

# Source cleanup methods
if [[ -f "${LIB_DIR}/cleanup-methods.sh" ]]; then
    # shellcheck disable=SC1091
    source "${LIB_DIR}/cleanup-methods.sh"
else
    log_error "cleanup-methods.sh not found in ${LIB_DIR}"
    exit 1
fi

#############################################################################
# Test Mode
#############################################################################

test_metrics() {
    log "=== Running Metrics Collection Test ==="
    
    # Use cleanup_batch table for testing
    local test_table="cleanup_batch"
    
    log "Testing metrics collection on table: $test_table"
    
    # Test 1: Basic helper functions
    log ""
    log "Test 1: Basic Helper Functions"
    log "------------------------------"
    
    log "Current timestamp: $(get_timestamp)"
    
    local row_count
    row_count=$(get_row_count "$DATABASE" "$test_table" "$CLEANUP_USER" "$CLEANUP_PASSW" "$MYSQL_HOST")
    log "Row count in $test_table: $row_count"
    
    local table_info
    table_info=$(get_table_info "$DATABASE" "$test_table" "$CLEANUP_USER" "$CLEANUP_PASSW" "$MYSQL_HOST")
    log "Table info: $table_info"
    
    # Test 2: InnoDB metrics
    log ""
    log "Test 2: InnoDB Metrics"
    log "----------------------"
    
    local hll
    hll=$(get_history_list_length "$MYSQL_HOST")
    log "History list length: $hll"
    
    local lock_metrics
    lock_metrics=$(get_lock_metrics "$MYSQL_HOST")
    log "Lock metrics (time waits): $lock_metrics"
    
    local row_ops
    row_ops=$(get_innodb_row_operations "$MYSQL_HOST")
    log "Row operations (del ins upd read): $row_ops"
    
    # Test 3: Replication metrics
    log ""
    log "Test 3: Replication Metrics"
    log "---------------------------"
    
    local repl_lag
    repl_lag=$(get_replication_lag "$DB_SLAVE_HOST")
    log "Replication lag: $repl_lag seconds"
    
    local repl_status
    repl_status=$(get_replication_status "$DB_SLAVE_HOST")
    log "Replication status (IO SQL lag): $repl_status"
    
    # Test 4: Binlog metrics
    log ""
    log "Test 4: Binlog Metrics"
    log "----------------------"
    
    local binlog_size
    binlog_size=$(get_binlog_size "$MYSQL_HOST")
    log "Total binlog size: $binlog_size bytes"
    
    local active_binlog
    active_binlog=$(get_active_binlog "$MYSQL_HOST")
    log "Active binlog: $active_binlog"
    
    # Test 5: Full snapshot
    log ""
    log "Test 5: Metrics Snapshot"
    log "------------------------"
    
    local snapshot_before
    snapshot_before=$(capture_metrics_snapshot "test_before" "$test_table" "$DATABASE" "$MYSQL_HOST")
    log "Captured snapshot (before):"
    echo "$snapshot_before" | head -5
    
    # Make a small change (delete a few rows)
    log ""
    log "Deleting 10 rows for testing..."
    mysql_query "DELETE FROM \`$DATABASE\`.\`$test_table\` WHERE ts < NOW() - INTERVAL 15 DAY LIMIT 10" "$CLEANUP_USER" "$CLEANUP_PASSW" "$MYSQL_HOST" "$DATABASE"
    
    sleep 1
    
    local snapshot_after
    snapshot_after=$(capture_metrics_snapshot "test_after" "$test_table" "$DATABASE" "$MYSQL_HOST")
    log "Captured snapshot (after):"
    echo "$snapshot_after" | head -5
    
    # Test 6: Metrics diff
    log ""
    log "Test 6: Metrics Diff Calculation"
    log "---------------------------------"
    
    local diff
    diff=$(calculate_metrics_diff "$snapshot_before" "$snapshot_after")
    log "Calculated diff:"
    echo "$diff"
    
    # Test 7: Metrics logging
    log ""
    log "Test 7: Metrics Logging"
    log "-----------------------"
    
    log_metrics "test_delete" "$test_table" "$snapshot_before" "$snapshot_after" "1.5"
    
    log ""
    log "=== Test Complete ==="
    log "Check $RESULTS_DIR for generated log files"
}

#############################################################################
# Help and Main
#############################################################################

#############################################################################
# Help and Main
#############################################################################

show_help() {
    cat <<-EOF
		Usage: $0 [options]
		
		MySQL Cleanup Benchmark - Cleanup Methods with Metrics Collection
		
		Options:
		  --method METHOD          Cleanup method: partition_drop, truncate, copy, batch_delete, all
		  --table TABLE            Target table name (optional, uses default per method)
		  --retention-days N       Days of data to retain (default: 10)
		  --batch-size N           Batch size for DELETE method (default: 5000)
		  --batch-delay N          Seconds between batches (default: 0.1)
		  --dry-run                Preview actions without executing (not yet implemented)
		  --test-metrics           Run metrics collection test
		  --verbose                Enable detailed logging
		  -h, --help               Show this help message
		
		Cleanup Methods:
		  partition_drop    Drop partitions containing old data (fastest, requires partitioned table)
		  truncate          Truncate entire table (WARNING: removes ALL data, not selective)
		  copy              Copy recent data to new table, swap and drop old
		  batch_delete      Delete in batches (slowest, but keeps table online)
		  all               Run all methods sequentially for comparison
		
		Examples:
		  # Test metrics collection
		  $0 --test-metrics --verbose
		  
		  # Run partition drop cleanup (10 days retention)
		  $0 --method partition_drop
		  
		  # Run truncate cleanup (removes ALL data)
		  $0 --method truncate
		  
		  # Run copy cleanup with custom retention
		  $0 --method copy --retention-days 7
		  
		  # Run batch delete with custom batch size
		  $0 --method batch_delete --batch-size 10000
		  
		  # Run all methods for comparison
		  $0 --method all
		  
		  # Run with concurrent load (in another terminal)
		  # Terminal 1: ./run-in-container.sh db-traffic.sh --rows-per-second 20 &
		  # Terminal 2: ./run-in-container.sh db-cleanup.sh --method batch_delete
		
	EOF
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --method)
                METHOD="$2"
                shift 2
                ;;
            --table)
                TABLE="$2"
                shift 2
                ;;
            --retention-days)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            --batch-size)
                BATCH_SIZE="$2"
                shift 2
                ;;
            --batch-delay)
                BATCH_DELAY="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --test-metrics)
                TEST_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
        
    # Create results directory if it doesn't exist
    mkdir -p "$RESULTS_DIR"
    
    # Run test mode if requested
    if [[ "$TEST_MODE" == "true" ]]; then
        test_metrics
        exit 0
    fi
    
    # Run cleanup methods
    if [[ -n "$METHOD" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY RUN mode - no changes will be made"
            log "This feature is not yet fully implemented"
        fi
        
        case "$METHOD" in
            partition_drop|partition)
                local target_table=${TABLE:-cleanup_partitioned}
                run_partition_drop_cleanup "$target_table" "$RETENTION_DAYS"
                ;;
            truncate)
                local target_table=${TABLE:-cleanup_truncate}
                log "WARNING: TRUNCATE removes ALL data (not selective)"
                run_truncate_cleanup "$target_table"
                ;;
            copy)
                local target_table=${TABLE:-cleanup_copy}
                run_copy_cleanup "$target_table" "$RETENTION_DAYS"
                ;;
            batch_delete|batch)
                local target_table=${TABLE:-cleanup_batch}
                run_batch_delete_cleanup "$target_table" "$RETENTION_DAYS" "$BATCH_SIZE" "$BATCH_DELAY"
                ;;
            all)
                run_all_methods "$RETENTION_DAYS" "$BATCH_SIZE"
                ;;
            *)
                log_error "Unknown method: $METHOD"
                log_error "Valid methods: partition_drop, truncate, copy, batch_delete, all"
                exit 1
                ;;
        esac
        exit $?
    fi
    
    # Show help if no options provided
    show_help
}

main "$@"