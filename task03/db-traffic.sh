#!/bin/bash

#############################################################################
# db-traffic.sh - Background Load Simulation for MySQL Cleanup Benchmark
#############################################################################
# This script generates continuous database traffic (INSERT, SELECT, UPDATE)
# to simulate realistic production conditions while cleanup operations run.
#
# Usage:
#   ./db-traffic.sh [OPTIONS]
#
# Options:
#   --rows-per-second N    Target operations per second (default: 10)
#   --tables TABLE1,TABLE2 Comma-separated table list (default: all four)
#   --workload-mix W:R:U   Ratio of write:read:update (default: 70:20:10)
#   --batch-size N         Number of rows per INSERT statement (default: 10)
#   --duration SECONDS     Run for fixed duration (default: infinite)
#   --verbose              Enable verbose output
#   -h, --help             Show this help message
#
# Examples:
#   # Default: 10 ops/sec, all tables, 70:20:10 mix
#   ./run-in-container.sh db-traffic.sh
#
#   # High write load, 50 ops/sec
#   ./run-in-container.sh db-traffic.sh --rows-per-second 50 --workload-mix 90:10:0
#
#   # High throughput with large batches
#   ./run-in-container.sh db-traffic.sh --rows-per-second 10000 --batch-size 1000
#
#   # Read-heavy workload on specific tables
#   ./run-in-container.sh db-traffic.sh --tables cleanup_batch,cleanup_copy --workload-mix 20:70:10
#
#   # Run for 5 minutes then exit
#   ./run-in-container.sh db-traffic.sh --duration 300
#
#   # Background execution during cleanup
#   ./run-in-container.sh db-traffic.sh &
#   TRAFFIC_PID=$!
#   ./run-in-container.sh db-cleanup.sh --method batch
#   kill $TRAFFIC_PID
#############################################################################

set -euo pipefail

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

# Default values
OPS_PER_SEC=10
DB_NAME="cleanup_bench"
TABLES="cleanup_partitioned,cleanup_truncate,cleanup_copy,cleanup_batch"
WORKLOAD_MIX="70:20:10"
DURATION=""
VERBOSE=0
BATCH_SIZE=10  # Number of rows per INSERT statement

# Statistics tracking
INSERTS=0
SELECTS=0
UPDATES=0
ERRORS=0
TOTAL_INSERTS=0
TOTAL_SELECTS=0
TOTAL_UPDATES=0
TOTAL_ERRORS=0
START_TIME=""
LAST_REPORT_TIME=""
REPORT_INTERVAL=10  # Report every 10 seconds

# Signal handling flag
SHUTDOWN=0

# Function to display help
show_help() {
    sed -n '2,/^$/p' "$0" | grep '^#' | sed 's/^# \?//'
}

# Source environment from task01 or use environment variables
# Try multiple locations for .env file (host vs container paths)
if [[ -n "${MYSQL_ROOT_PASSWORD:-}" ]]; then
    # Environment variables already set (e.g., when running in container)
    : # no-op, variables already available
else
    # Try to source .env file
    ENV_LOCATIONS=(
        "$(dirname "${BASH_SOURCE[0]}")/../task01/compose/.env"
        "/opt/compose/.env"
        "../task01/compose/.env"
    )
    
    ENV_FILE=""
    for loc in "${ENV_LOCATIONS[@]}"; do
        if [[ -f "$loc" ]]; then
            ENV_FILE="$loc"
            break
        fi
    done
    
    if [[ -z "$ENV_FILE" ]]; then
        log_error "Environment file not found and required variables not set"
        log_error "Required variables: MYSQL_ROOT_PASSWORD"
        exit 1
    fi
    
    source "$ENV_FILE"
fi

# MySQL connection defaults (running inside container, use localhost)
MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
MYSQL_USER="root"
MYSQL_PASS="${MYSQL_ROOT_PASSWORD}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --rows-per-second)
            OPS_PER_SEC="$2"
            shift 2
            ;;
        --tables)
            TABLES="$2"
            shift 2
            ;;
        --workload-mix)
            WORKLOAD_MIX="$2"
            shift 2
            ;;
        --batch-size)
            BATCH_SIZE="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE="true"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# Parse workload mix (format: W:R:U, e.g., 70:20:10)
IFS=':' read -r WRITE_PCT READ_PCT UPDATE_PCT <<< "$WORKLOAD_MIX"

# Validate mix ratios
TOTAL_PCT=$((WRITE_PCT + READ_PCT + UPDATE_PCT))
if [[ $TOTAL_PCT -ne 100 ]]; then
    log_error "Workload mix must sum to 100 (got: $TOTAL_PCT)"
    exit 1
fi

# Convert tables string to array
IFS=',' read -ra TABLE_ARRAY <<< "$TABLES"

# MySQL connection function (wrapper around helpers.sh mysql_query)
mysql_exec() {
    local sql="$1"
    mysql_query "$sql" "$MYSQL_USER" "$MYSQL_PASS" "$MYSQL_HOST" "$DB_NAME"
}

# Test database connectivity
test_connection() {
    log "Testing database connection..."
    
    if ! mysql_exec "SELECT 1" > /dev/null 2>&1; then
        log_error "Cannot connect to MySQL database"
        log_error "       Host: $MYSQL_HOST, Database: $DB_NAME"
        exit 1
    fi
    
    log_verbose "Database connection successful"
}

# Verify tables exist
verify_tables() {
    log "Verifying tables..."
    
    for table in "${TABLE_ARRAY[@]}"; do
        if ! mysql_exec "SHOW TABLES LIKE '$table'" | grep -q "$table"; then
            log_error "Table '$table' does not exist in database '$DB_NAME'"
            exit 1
        fi
        log_verbose "Table '$table' verified"
    done
}

# Generate random 10-character uppercase string (A-Z)
generate_random_name() {
    local name=""
    for i in {1..10}; do
        # ASCII 65-90 for A-Z
        local char_code=$((65 + RANDOM % 26))
        name+=$(printf "\\$(printf '%03o' "$char_code")")
    done
    echo "$name"
}

# Generate random integer 0-10,000,000
generate_random_data() {
    echo $((RANDOM * RANDOM % 10000001))
}

# Execute INSERT operation
do_insert() {
    local table="${TABLE_ARRAY[$((RANDOM % ${#TABLE_ARRAY[@]}))]}"
    
    # Build multi-row INSERT statement
    local values=""
    for i in $(seq 1 $BATCH_SIZE); do
        local name=$(generate_random_name)
        local data=$(generate_random_data)
        if [[ $i -eq 1 ]]; then
            values="(NOW(), '$name', $data)"
        else
            values+=", (NOW(), '$name', $data)"
        fi
    done
    
    local sql="INSERT INTO $table (ts, name, data) VALUES $values"
    
    log_verbose "INSERT into $table ($BATCH_SIZE rows)"
    
    if mysql_exec "$sql" > /dev/null 2>&1; then
        INSERTS=$((INSERTS + BATCH_SIZE))
        TOTAL_INSERTS=$((TOTAL_INSERTS + BATCH_SIZE))
        return 0
    else
        ERRORS=$((ERRORS + 1))
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        log "ERROR: INSERT failed for table $table"
        return 1
    fi
}

# Execute SELECT operation
do_select() {
    local table="${TABLE_ARRAY[$((RANDOM % ${#TABLE_ARRAY[@]}))]}"
    
    # Randomly select query pattern
    local pattern=$((RANDOM % 3))
    local sql=""
    
    case $pattern in
        0)
            # Recent data query
            sql="SELECT * FROM $table WHERE ts >= NOW() - INTERVAL 5 MINUTE ORDER BY ts DESC LIMIT 10"
            ;;
        1)
            # Time range query (random range in last hour)
            sql="SELECT * FROM $table WHERE ts >= NOW() - INTERVAL 1 HOUR LIMIT 100"
            ;;
        2)
            # Aggregate query
            sql="SELECT COUNT(*), AVG(data) FROM $table WHERE ts >= NOW() - INTERVAL 1 HOUR"
            ;;
    esac
    
    log_verbose "SELECT from $table (pattern $pattern)"
    
    if mysql_exec "$sql" > /dev/null 2>&1; then
        SELECTS=$((SELECTS + 1))
        TOTAL_SELECTS=$((TOTAL_SELECTS + 1))
        return 0
    else
        ERRORS=$((ERRORS + 1))
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        log "ERROR: SELECT failed for table $table"
        return 1
    fi
}

# Execute UPDATE operation
do_update() {
    local table="${TABLE_ARRAY[$((RANDOM % ${#TABLE_ARRAY[@]}))]}"
    
    # Randomly select update pattern
    local pattern=$((RANDOM % 2))
    local sql=""
    
    case $pattern in
        0)
            # Update recent rows by timestamp
            local name=$(generate_random_name)
            sql="UPDATE $table SET name = '$name' WHERE ts >= NOW() - INTERVAL 10 MINUTE LIMIT 10"
            ;;
        1)
            # Update data value
            sql="UPDATE $table SET data = data + 1 WHERE ts >= NOW() - INTERVAL 5 MINUTE LIMIT 10"
            ;;
    esac
    
    log_verbose "UPDATE on $table (pattern $pattern)"
    
    if mysql_exec "$sql" > /dev/null 2>&1; then
        UPDATES=$((UPDATES + 1))
        TOTAL_UPDATES=$((TOTAL_UPDATES + 1))
        return 0
    else
        ERRORS=$((ERRORS + 1))
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        log "ERROR: UPDATE failed for table $table"
        return 1
    fi
}

# Print periodic statistics
print_stats() {
    local now=$(date +%s)
    local elapsed=$((now - LAST_REPORT_TIME))
    
    if [[ $elapsed -ge $REPORT_INTERVAL ]]; then
        local insert_rate=$(( (INSERTS * 10 / REPORT_INTERVAL + 5) / 10 ))
        local select_rate=$(( (SELECTS * 10 / REPORT_INTERVAL + 5) / 10 ))
        local update_rate=$(( (UPDATES * 10 / REPORT_INTERVAL + 5) / 10 ))
        
        log "Stats: INSERTs=$INSERTS (~${insert_rate}/s), SELECTs=$SELECTS (~${select_rate}/s), UPDATEs=$UPDATES (~${update_rate}/s), Errors=$ERRORS"
        
        # Reset counters for next interval
        INSERTS=0
        SELECTS=0
        UPDATES=0
        ERRORS=0
        LAST_REPORT_TIME=$now
    fi
}

# Print final summary
print_summary() {
    local now=$(date +%s)
    local runtime=$((now - START_TIME))
    local total_ops=$((TOTAL_INSERTS + TOTAL_SELECTS + TOTAL_UPDATES))
    local avg_rate=0
    
    if [[ $runtime -gt 0 ]]; then
        avg_rate=$(( (total_ops * 10 / runtime + 5) / 10 ))
    fi
    
    echo ""
    log "Shutting down gracefully..."
    echo ""
    echo "=== Traffic Simulation Summary ==="
    echo "Runtime:           $runtime seconds"
    echo "Total Operations:  $total_ops"
    local insert_pct=0
    local select_pct=0
    local update_pct=0
    if [[ $total_ops -gt 0 ]]; then
        insert_pct=$(( (TOTAL_INSERTS * 1000 / total_ops + 5) / 10 ))
        select_pct=$(( (TOTAL_SELECTS * 1000 / total_ops + 5) / 10 ))
        update_pct=$(( (TOTAL_UPDATES * 1000 / total_ops + 5) / 10 ))
    fi
    echo "  - INSERTs:       $TOTAL_INSERTS (~${insert_pct}%)"
    echo "  - SELECTs:       $TOTAL_SELECTS (~${select_pct}%)"
    echo "  - UPDATEs:       $TOTAL_UPDATES (~${update_pct}%)"
    echo "Errors:            $TOTAL_ERRORS"
    echo "Average Rate:      ~${avg_rate} ops/sec"
    echo "Tables Affected:   ${TABLES}"
    echo ""
}

# Signal handler for graceful shutdown
handle_signal() {
    SHUTDOWN=1
}

# Register signal handlers
trap handle_signal SIGINT SIGTERM

# Main function
main() {
    log "Starting traffic simulation: $OPS_PER_SEC ops/sec, mix $WORKLOAD_MIX"
    log "Target tables: $TABLES"
    
    # Validate environment
    test_connection
    verify_tables
    
    # Initialize statistics
    START_TIME=$(date +%s)
    LAST_REPORT_TIME=$START_TIME
    
    # Calculate operation delay (inter-operation interval)
    # Only INSERTs insert rows (BATCH_SIZE per operation)
    # Need to account for workload mix: only WRITE_PCT% of operations are INSERTs
    # Formula: delay = (BATCH_SIZE * 100) / (OPS_PER_SEC * WRITE_PCT) seconds
    # Using milliseconds to avoid floating-point arithmetic
    local delay_ms=$(( BATCH_SIZE * 100000 / (OPS_PER_SEC * WRITE_PCT) ))
    
    log "Operation delay: ${delay_ms}ms (target: $OPS_PER_SEC rows/sec, batch: $BATCH_SIZE, write: ${WRITE_PCT}%)"
    
    if [[ -n "$DURATION" ]]; then
        log "Duration: ${DURATION}s"
    else
        log "Duration: infinite (until stopped)"
    fi
    
    echo ""
    
    # Main operation loop
    local loop_start=$(date +%s)
    while [[ $SHUTDOWN -eq 0 ]]; do
        # Check duration limit
        if [[ -n "$DURATION" ]]; then
            local now=$(date +%s)
            if [[ $((now - loop_start)) -ge $DURATION ]]; then
                log "Duration limit reached, stopping..."
                break
            fi
        fi
        
        # Select operation type based on workload mix
        local op_rand=$((RANDOM % 100))
        
        local op_start=$(get_timestamp)
        
        if [[ $op_rand -lt $WRITE_PCT ]]; then
            do_insert
        elif [[ $op_rand -lt $((WRITE_PCT + READ_PCT)) ]]; then
            do_select
        else
            do_update
        fi
        
        local op_end=$(get_timestamp)
        local op_time=$(calculate_duration "$op_start" "$op_end")
        
        # Print periodic statistics
        print_stats
        
        # Rate limiting: sleep for remaining time
        # Convert op_time (seconds) to milliseconds for comparison
        local op_time_ms=$(awk "BEGIN {printf \"%d\", $op_time * 1000}")
        local sleep_ms=$(( delay_ms - op_time_ms ))
        
        log_verbose "Operation took ${op_time_ms}ms, delay target: ${delay_ms}ms, sleep: ${sleep_ms}ms"
        
        if [[ $sleep_ms -gt 0 ]]; then
            # Convert milliseconds to seconds for sleep command
            local sleep_sec=$(awk "BEGIN {printf \"%.6f\", $sleep_ms / 1000}")
            sleep "$sleep_sec"
        fi
    done
    
    # Print final summary
    print_summary
}

# Run main function
main

exit 0
