#!/bin/bash

#############################################################################
# MySQL Cleanup Benchmark - Helper Functions Library
#
# This module provides core utility functions used across the cleanup
# benchmark system:
# - Logging functions (log, log_verbose, log_error)
# - Timestamp and duration calculations
# - MySQL query execution
# - MySQL status and information retrieval
# - Table information queries
#
# Usage:
#   source lib/helpers.sh
#
#############################################################################

#############################################################################
# Logging Functions
#############################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_verbose() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VERBOSE] $*" >&2
    fi
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

#############################################################################
# Timestamp and Duration Functions
#############################################################################

# Get current timestamp with nanosecond precision
get_timestamp() {
    date +%s.%N
}

# Calculate duration in seconds between two timestamps
calculate_duration() {
    local start_ts=$1
    local end_ts=$2
    awk "BEGIN {printf \"%.6f\", $end_ts - $start_ts}"
}

#############################################################################
# MySQL Connection Functions
#############################################################################

# Execute MySQL query and return result
mysql_query() {
    local query=$1
    local user=${2:-${CLEANUP_USER}}
    local password=${3:-${CLEANUP_PASSW}}
    local host=${4:-${MYSQL_HOST:-localhost}}
    local database=${5:-cleanup_bench}
    local port=${MYSQL_PORT:-3306}
    
    mysql -h"$host" -P"$port" -u"$user" -p"$password" \
        "$database" --skip-column-names --batch -e "$query" 2>/dev/null
}

#############################################################################
# MySQL Status and Information Functions
#############################################################################

# Get MySQL status variable
get_status_var() {
    local var_name=$1
    local user=${2:-${CLEANUP_USER}}
    local password=${3:-${CLEANUP_PASSW}}
    local host=${4:-${MYSQL_HOST:-localhost}}
    local database=${5:-cleanup_bench}
    
    log_verbose "Querying status variable: $var_name"
    local result
    result=$(mysql_query "SHOW GLOBAL STATUS LIKE '$var_name'" "$user" "$password" "$host" "$database" 2>/dev/null | awk '{print $2}')
    
    # Return 0 if query failed or returned empty
    if [[ -z "$result" ]]; then
        echo "0"
    else
        echo "$result"
    fi
}

# Get InnoDB metric from information_schema
get_innodb_metric() {
    local metric_name=$1
    local user=${2:-${CLEANUP_USER}}
    local password=${3:-${CLEANUP_PASSW}}
    local host=${4:-${MYSQL_HOST:-localhost}}
    local database=${5:-cleanup_bench}
    
    log_verbose "Querying InnoDB metric: $metric_name"
    mysql_query "SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = '$metric_name'" "$user" "$password" "$host" "$database"
}

# Get exact row count for a table
get_row_count() {
    local database=$1
    local table=$2
    local user=${3:-${CLEANUP_USER}}
    local password=${4:-${CLEANUP_PASSW}}
    local host=${5:-${MYSQL_HOST:-localhost}}
    
    log_verbose "Counting rows in $database.$table"
    mysql_query "SELECT COUNT(*) FROM \`$database\`.\`$table\`" "$user" "$password" "$host" "$database"
}

# Get table information from information_schema
get_table_info() {
    local database=$1
    local table=$2
    local user=${3:-${CLEANUP_USER}}
    local password=${4:-${CLEANUP_PASSW}}
    local host=${5:-${MYSQL_HOST:-localhost}}
    
    log_verbose "Querying table info for $database.$table"
    mysql_query "SELECT DATA_LENGTH, INDEX_LENGTH, DATA_FREE, TABLE_ROWS \
                 FROM information_schema.TABLES \
                 WHERE TABLE_SCHEMA = '$database' AND TABLE_NAME = '$table'" "$user" "$password" "$host" "$database"
}

