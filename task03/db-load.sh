#!/bin/bash

#############################################################################
# db-load.sh - Data Loading Script for MySQL Cleanup Benchmark
#############################################################################
# This script loads CSV data into all four test tables for the cleanup benchmark.
# It uses LOAD DATA LOCAL INFILE for efficient bulk loading.
#
# Prerequisites:
#   Generate CSV file first using: ./generate-seeds.sh --rows N
#
# Usage:
#   ./db-load.sh [OPTIONS]
#
# Options:
#   --csv FILE         CSV file to load (default: data/events_seed.csv)
#   --db NAME          Database name (default: cleanup_bench)
#   --disable-indexes  Drop indexes before load, rebuild after (faster for large loads)
#   --batch-size N     Batch size for INSERT method (default: 10000)
#   --verbose          Enable verbose output
#   -h, --help         Show this help message
#
# Example:
#   ./generate-seeds.sh --rows 200000
#   ./db-load.sh --csv data/events_seed.csv --disable-indexes --verbose
#############################################################################

set -euo pipefail

# Source helper functions
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/lib/helpers.sh"

# Default values
DB_NAME="cleanup_bench"
DISABLE_INDEXES=0
BATCH_SIZE=10000
VERBOSE=false
DATA_DIR="${SOURCE_DIR}/data"
CSV_FILE="${DATA_DIR}/events_seed.csv"

# Function to display help
show_help() {
    sed -n '2,/^$/p' "$0" | grep '^#' | sed 's/^# \?//'
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --csv)
            CSV_FILE="$2"
            shift 2
            ;;
        --db)
            DB_NAME="$2"
            shift 2
            ;;
        --disable-indexes)
            DISABLE_INDEXES=1
            shift
            ;;
        --batch-size)
            BATCH_SIZE="$2"
            shift 2
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
            echo "ERROR: Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Validate batch size
if ! [[ "$BATCH_SIZE" =~ ^[0-9]+$ ]] || [[ $BATCH_SIZE -lt 1 ]]; then
    echo "ERROR: --batch-size must be a positive integer" >&2
    exit 1
fi

# MySQL connection settings
# When running inside container, use localhost
# When running from host, use container name or docker exec
MYSQL_HOST="localhost"
MYSQL_PORT="${MYSQL_PORT:-3306}"

# Map credentials for helper functions
CLEANUP_USER="${CLEANUP_USER:-root}"
CLEANUP_PASSW="${CLEANUP_PASSW:-${MYSQL_ROOT_PASSWORD}}"

log "Starting data load process"
log_verbose "Configuration:"
log_verbose "  Database: ${DB_NAME}"
log_verbose "  CSV file: ${CSV_FILE}"
log_verbose "  MySQL host: ${MYSQL_HOST}"
log_verbose "  MySQL user: ${MYSQL_USER}"
log_verbose "  Batch size: ${BATCH_SIZE}"
log_verbose "  Disable indexes: ${DISABLE_INDEXES}"

#############################################################################
# Function: verify_csv_file
# Description: Verifies that the CSV file exists
#############################################################################
verify_csv_file() {
    log_verbose "Verifying CSV file exists..."
    
    if [[ ! -f "$CSV_FILE" ]]; then
        log_error "CSV file not found: ${CSV_FILE}"
        log_error "Please generate CSV file first using:"
        log_error "  ./generate-seeds.sh --rows N"
        exit 1
    fi
    
    local row_count=$(wc -l < "$CSV_FILE")
    log "CSV file found: ${CSV_FILE} (${row_count} rows)"
}

#############################################################################
# Function: enable_local_infile
# Description: Enables LOAD DATA LOCAL INFILE for the session
#############################################################################
enable_local_infile() {
    log_verbose "Checking LOAD DATA LOCAL INFILE support..."
    
    # Try to enable local_infile for this session (requires root)
    mysql_query "SET GLOBAL local_infile=1" "root" "${MYSQL_ROOT_PASSWORD}" || true
    
    # Check if it's enabled
    local local_infile=$(mysql_query "SELECT @@GLOBAL.local_infile" || echo "0")
    
    if [[ "$local_infile" == "1" ]]; then
        log_verbose "  ✓ LOAD DATA LOCAL INFILE is enabled"
        return 0
    else
        log_verbose "  ✗ LOAD DATA LOCAL INFILE is disabled, will use INSERT method"
        return 1
    fi
}

#############################################################################
# Function: get_table_indexes
# Description: Gets all indexes for a table (except PRIMARY)
# Parameters: $1 - table name
#############################################################################
get_table_indexes() {
    local table=$1
    
    mysql_query "SELECT DISTINCT INDEX_NAME FROM INFORMATION_SCHEMA.STATISTICS 
                WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_NAME='${table}' 
                AND INDEX_NAME != 'PRIMARY'"
}

#############################################################################
# Function: drop_table_indexes
# Description: Drops all non-primary indexes from a table
# Parameters: $1 - table name
#############################################################################
drop_table_indexes() {
    local table=$1
    
    log_verbose "  Dropping indexes from ${table}..."
    
    local indexes=$(get_table_indexes "$table")
    
    if [[ -z "$indexes" ]]; then
        log_verbose "    No indexes to drop"
        return 0
    fi
    
    while IFS= read -r index; do
        log_verbose "    Dropping index: ${index}"
        mysql_query "USE ${DB_NAME}; ALTER TABLE ${table} DROP INDEX \`${index}\`"
    done <<< "$indexes"
}

#############################################################################
# Function: recreate_table_indexes
# Description: Recreates indexes on a table
# Parameters: $1 - table name
#############################################################################
recreate_table_indexes() {
    local table=$1
    
    log_verbose "  Recreating indexes on ${table}..."
    
    # Add index on ts column (used for cleanup queries)
    mysql_query "USE ${DB_NAME}; ALTER TABLE ${table} ADD INDEX idx_ts (ts)" || true
    
    log_verbose "    ✓ Index idx_ts created"
}

#############################################################################
# Function: load_table_with_load_data
# Description: Loads CSV data using LOAD DATA LOCAL INFILE (fastest method)
# Parameters: $1 - table name
#############################################################################
load_table_with_load_data() {
    local table=$1
    local start_time=$(date +%s)
    
    log_verbose "  Using LOAD DATA LOCAL INFILE (fastest method)..."
    
    # Use LOAD DATA LOCAL INFILE with single transaction
    mysql --local-infile=1 -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${CLEANUP_USER}" -p"${CLEANUP_PASSW}" \
        "${DB_NAME}" 2>/dev/null <<EOF
SET autocommit=0;
LOAD DATA LOCAL INFILE '${CSV_FILE}'
INTO TABLE ${table}
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
(ts, name, data);
COMMIT;
SET autocommit=1;
EOF
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_verbose "  Load completed in ${duration}s"
}

#############################################################################
# Function: load_table_with_insert
# Description: Loads CSV data using multi-row INSERT statements
# Parameters: $1 - table name
#############################################################################
load_table_with_insert() {
    local table=$1
    local start_time=$(date +%s)
    
    log_verbose "  Using INSERT statements (batch size: ${BATCH_SIZE})..."
    
    local sql_file="/tmp/${table}_load.sql"
    
    # Generate multi-row INSERT statements with single transaction
    {
        echo "USE ${DB_NAME};"
        echo "SET autocommit=0;"
        
        awk -F',' -v table="$table" -v batch="$BATCH_SIZE" '
        BEGIN { 
            count = 0
            printf "INSERT INTO %s (ts, name, data) VALUES\n", table
        }
        {
            if (count > 0 && count % batch == 0) {
                print ";"
                printf "INSERT INTO %s (ts, name, data) VALUES\n", table
                prefix = ""
            } else if (count > 0) {
                prefix = ","
            } else {
                prefix = ""
            }
            
            # Escape single quotes in data
            gsub(/'\''\'\''/,"'\'''\'''\'''\''", $2)
            printf "%s('\''%s'\'','\''%s'\'',%s)\n", prefix, $1, $2, $3
            count++
        }
        END { 
            if (count > 0) {
                print ";"
            }
        }
        ' "$CSV_FILE"
        
        echo "COMMIT;"
        echo "SET autocommit=1;"
    } > "$sql_file"
    
    # Execute the SQL file
    mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${CLEANUP_USER}" -p"${CLEANUP_PASSW}" \
        "${DB_NAME}" < "$sql_file" 2>/dev/null
    
    # Clean up
    rm -f "$sql_file"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_verbose "  Load completed in ${duration}s"
}

#############################################################################
# Function: load_table
# Description: Loads CSV data into a specific table using optimal method
# Parameters: $1 - table name
#############################################################################
load_table() {
    local table=$1
    local overall_start=$(date +%s)
    
    log "Loading data into table: ${table}"
    log_verbose "  Truncating ${table}..."
    
    # Truncate table to start fresh
    mysql_query "USE ${DB_NAME}; TRUNCATE TABLE ${table}"
    
    # Drop indexes if requested (improves load performance)
    if [[ $DISABLE_INDEXES -eq 1 ]]; then
        drop_table_indexes "$table"
    fi
    
    # Try LOAD DATA LOCAL INFILE first (fastest), fall back to INSERT
    if enable_local_infile; then
        load_table_with_load_data "$table"
    else
        load_table_with_insert "$table"
    fi
    
    # Recreate indexes if they were dropped
    if [[ $DISABLE_INDEXES -eq 1 ]]; then
        recreate_table_indexes "$table"
    fi
    
    # Get row count
    local row_count=$(get_row_count "${DB_NAME}" "${table}")
    
    local overall_end=$(date +%s)
    local total_duration=$((overall_end - overall_start))
    
    log "  ✓ Loaded ${row_count} rows into ${table} (${total_duration}s total)"
}

#############################################################################
# Function: verify_mysql_connection
# Description: Tests MySQL connection
#############################################################################
verify_mysql_connection() {
    log_verbose "Verifying MySQL connection..."
    
    if ! mysql_query "SELECT 1" >/dev/null 2>&1; then
        log_error "Cannot connect to MySQL at ${MYSQL_HOST}:${MYSQL_PORT}"
        log_error "Check that MySQL is running and credentials are correct"
        exit 1
    fi
    
    log_verbose "MySQL connection successful"
}

#############################################################################
# Function: verify_database
# Description: Verifies that the target database exists
#############################################################################
verify_database() {
    log_verbose "Verifying database ${DB_NAME} exists..."
    
    local db_exists=$(mysql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}'")
    
    if [[ $db_exists -eq 0 ]]; then
        log_error "Database ${DB_NAME} does not exist"
        log_error "Please run db-schema.sql first to create the database and tables"
        exit 1
    fi
    
    log_verbose "Database ${DB_NAME} exists"
}

#############################################################################
# Function: verify_tables
# Description: Verifies that all required tables exist
#############################################################################
verify_tables() {
    log_verbose "Verifying tables exist..."
    
    local tables=("cleanup_partitioned" "cleanup_truncate" "cleanup_copy" "cleanup_batch")
    
    for table in "${tables[@]}"; do
        local table_exists=$(mysql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_NAME='${table}'")
        
        if [[ $table_exists -eq 0 ]]; then
            log_error "Table ${table} does not exist in database ${DB_NAME}"
            log_error "Please run db-schema.sql first to create all tables"
            exit 1
        fi
        
        log_verbose "  ✓ Table ${table} exists"
    done
}

#############################################################################
# Function: show_summary
# Description: Displays summary of data distribution
#############################################################################
show_summary() {
    log "Generating data distribution summary..."
    
    # Query to show distribution of data
    mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${CLEANUP_USER}" -p"${CLEANUP_PASSW}" \
        "${DB_NAME}" 2>/dev/null <<'EOF'
SELECT 
    'cleanup_partitioned' AS table_name,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN ts < NOW() - INTERVAL 10 DAY THEN 1 ELSE 0 END) AS rows_older_than_10d,
    MIN(ts) AS oldest_ts,
    MAX(ts) AS newest_ts
FROM cleanup_partitioned
UNION ALL
SELECT 
    'cleanup_truncate',
    COUNT(*),
    SUM(CASE WHEN ts < NOW() - INTERVAL 10 DAY THEN 1 ELSE 0 END),
    MIN(ts),
    MAX(ts)
FROM cleanup_truncate
UNION ALL
SELECT 
    'cleanup_copy',
    COUNT(*),
    SUM(CASE WHEN ts < NOW() - INTERVAL 10 DAY THEN 1 ELSE 0 END),
    MIN(ts),
    MAX(ts)
FROM cleanup_copy
UNION ALL
SELECT 
    'cleanup_batch',
    COUNT(*),
    SUM(CASE WHEN ts < NOW() - INTERVAL 10 DAY THEN 1 ELSE 0 END),
    MIN(ts),
    MAX(ts)
FROM cleanup_batch;
EOF
}

#############################################################################
# Main execution
#############################################################################

# Step 1: Verify CSV file exists
verify_csv_file

# Step 2: Verify MySQL connection
verify_mysql_connection

# Step 3: Verify database exists
verify_database

# Step 4: Verify tables exist
verify_tables

# Step 5: Load data into all tables
log "Loading data into all tables..."
load_table "cleanup_partitioned"
load_table "cleanup_truncate"
load_table "cleanup_copy"
load_table "cleanup_batch"

# Step 6: Show summary
show_summary

log "Data load completed successfully!"
log ""
log "Summary:"
log "  CSV file: ${CSV_FILE}"
log "  Database: ${DB_NAME}"
log ""
log "Next steps:"
log "  1. Run db-traffic.sh to simulate ongoing workload (optional)"
log "  2. Run db-cleanup.sh to test cleanup methods"
