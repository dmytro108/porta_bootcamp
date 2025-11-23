#!/bin/bash
# =====================================================
# Task 03: Partition Maintenance Script
# =====================================================
# This script maintains a rolling window of daily partitions
# for the cleanup_partitioned table.
#
# Actions:
# - Adds new partition for tomorrow (if not exists)
# - Drops partitions older than retention window (30 days)
#
# Usage:
#   ./db-partition-maintenance.sh [OPTIONS]
#
# Options:
#   -h, --help              Show this help message
#   -d, --dry-run           Show what would be done without executing
#   -v, --verbose           Enable verbose output
#
# This script should be run daily via cron.
# =====================================================

set -e

# Source environment variables from task01
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../task01/compose/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: Environment file not found: $ENV_FILE" >&2
    exit 1
fi

source "$ENV_FILE"

# Configuration
DB_HOST="${DB_MASTER_HOST}"
DB_USER="root"
DB_PASS="${MYSQL_ROOT_PASSWORD}"
DB_NAME="cleanup_bench"
TABLE_NAME="cleanup_partitioned"
RETENTION_DAYS=30
DRY_RUN=0
VERBOSE=0

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            grep "^#" "$0" | grep -v "#!/bin/bash" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use -h or --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Function to execute MySQL command
execute_sql() {
    local sql="$1"
    if [[ $VERBOSE -eq 1 ]]; then
        echo "SQL: $sql"
    fi
    
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would execute: $sql"
    else
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$sql"
    fi
}

# Function to add a new partition for a given date
add_partition() {
    local partition_date="$1"
    local partition_name=$(date -d "$partition_date" +p%Y%m%d)
    local next_date=$(date -d "$partition_date + 1 day" +%Y-%m-%d)
    
    # Check if partition already exists
    local exists=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -sse "SELECT COUNT(*) FROM INFORMATION_SCHEMA.PARTITIONS WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='$TABLE_NAME' AND PARTITION_NAME='$partition_name'")
    
    if [[ $exists -eq 0 ]]; then
        local sql="ALTER TABLE $TABLE_NAME REORGANIZE PARTITION pFUTURE INTO (
            PARTITION $partition_name VALUES LESS THAN (TO_DAYS('$next_date')),
            PARTITION pFUTURE VALUES LESS THAN MAXVALUE
        );"
        
        echo "Adding partition: $partition_name (for date: $partition_date)"
        execute_sql "$sql"
    else
        if [[ $VERBOSE -eq 1 ]]; then
            echo "Partition $partition_name already exists"
        fi
    fi
}

# Function to drop partitions older than retention period
drop_old_partitions() {
    local cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%d)
    local cutoff_days=$(date -d "$cutoff_date" +%s)
    cutoff_days=$((cutoff_days / 86400))
    
    echo "Dropping partitions older than $cutoff_date (retention: $RETENTION_DAYS days)"
    
    # Get list of partitions with their upper bounds
    local partitions=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -sse "SELECT PARTITION_NAME, PARTITION_DESCRIPTION FROM INFORMATION_SCHEMA.PARTITIONS 
              WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='$TABLE_NAME' 
              AND PARTITION_NAME != 'pFUTURE' 
              ORDER BY PARTITION_ORDINAL_POSITION")
    
    while IFS=$'\t' read -r partition_name partition_desc; do
        # Skip if MAXVALUE
        if [[ "$partition_desc" == "MAXVALUE" ]]; then
            continue
        fi
        
        # Parse the TO_DAYS value
        local partition_days=$partition_desc
        
        # Convert cutoff_date to TO_DAYS value for comparison
        local cutoff_to_days=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -sse "SELECT TO_DAYS('$cutoff_date')")
        
        # Drop partition if it's older than retention period
        if [[ $partition_days -lt $cutoff_to_days ]]; then
            echo "Dropping old partition: $partition_name (upper bound: $partition_desc)"
            execute_sql "ALTER TABLE $TABLE_NAME DROP PARTITION $partition_name;"
        fi
    done <<< "$partitions"
}

# Main execution
echo "========================================"
echo "Partition Maintenance - $(date)"
echo "========================================"
echo "Database: $DB_NAME"
echo "Table: $TABLE_NAME"
echo "Retention: $RETENTION_DAYS days"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "Mode: DRY-RUN"
fi
echo "========================================"

# Add partition for tomorrow
TOMORROW=$(date -d "tomorrow" +%Y-%m-%d)
add_partition "$TOMORROW"

# Drop old partitions
drop_old_partitions

echo "========================================"
echo "Partition maintenance completed"
echo "========================================"

# Show current partition status
if [[ $VERBOSE -eq 1 ]]; then
    echo ""
    echo "Current partitions:"
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -e "SELECT PARTITION_NAME, PARTITION_DESCRIPTION, TABLE_ROWS 
            FROM INFORMATION_SCHEMA.PARTITIONS 
            WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='$TABLE_NAME' 
            ORDER BY PARTITION_ORDINAL_POSITION;"
fi
