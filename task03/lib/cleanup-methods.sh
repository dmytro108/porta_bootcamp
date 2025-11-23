#!/bin/bash

#############################################################################
# MySQL Cleanup Benchmark - Cleanup Methods Implementation
#
# This module implements the four main cleanup methods:
# 1. TRUNCATE TABLE - Fast but removes ALL data (not selective)
# 2. DROP PARTITION - Fastest selective method (requires partitioning)
# 3. Copy-to-New-Table - Fast but causes data loss during execution
# 4. Batch DELETE - Slowest but keeps table online
#
# Each method has two functions:
# - execute_*_cleanup: Core implementation
# - run_*_cleanup: Wrapper with metrics collection
#
# Usage:
#   source lib/cleanup-methods.sh
#
# Dependencies:
#   - lib/helpers.sh must be sourced first
#   - lib/metrics.sh must be sourced first
#
#############################################################################

#############################################################################
# Method 1: TRUNCATE TABLE
# WARNING: Removes ALL data, not selective (does not meet 10-day retention requirement)
# Use only for temporary tables or when entire table can be cleared
#############################################################################

execute_truncate_cleanup() {
    local table=${1:-cleanup_truncate}
    
    log "Executing TRUNCATE cleanup on ${DATABASE}.${table}"
    log "WARNING: This will remove ALL data from the table"
    
    # Execute TRUNCATE
    local sql="TRUNCATE TABLE \`${DATABASE}\`.\`${table}\`;"
    
    log_verbose "SQL: $sql"
    mysql_query "$sql"
    
    if [[ $? -ne 0 ]]; then
        log_error "TRUNCATE failed"
        return 1
    fi
    
    log "TRUNCATE completed successfully"
    return 0
}

run_truncate_cleanup() {
    local table=${1:-cleanup_truncate}
    local method="truncate"
    
    log "Starting TRUNCATE cleanup with metrics collection"
    log "Table: ${DATABASE}.${table}"
    
    # Pre-cleanup snapshot
    local snapshot_before
    snapshot_before=$(capture_metrics_snapshot "before" "$table")
    local start_ts
    start_ts=$(get_timestamp)
    
    # Execute cleanup
    execute_truncate_cleanup "$table"
    local exit_code=$?
    
    # Post-cleanup snapshot
    local end_ts
    end_ts=$(get_timestamp)
    local snapshot_after
    snapshot_after=$(capture_metrics_snapshot "after" "$table")
    
    # Calculate duration
    local duration
    duration=$(calculate_duration "$start_ts" "$end_ts")
    
    # Log metrics
    if [[ $exit_code -eq 0 ]]; then
        log_metrics "$method" "$table" "$snapshot_before" "$snapshot_after" "$duration"
        log "TRUNCATE cleanup complete: duration=${duration}s"
    else
        log_error "TRUNCATE cleanup failed"
        return 1
    fi
    
    return 0
}

#############################################################################
# Method 2: DROP PARTITION
# Selectively drops partitions containing old data
# Fastest method when partitioning is available
#############################################################################

identify_old_partitions() {
    local table=${1:-cleanup_partitioned}
    local retention_days=${2:-10}
    
    log_verbose "Identifying partitions older than ${retention_days} days in ${DATABASE}.${table}"
    
    # Calculate TO_DAYS cutoff
    local sql_cutoff="SELECT TO_DAYS(NOW() - INTERVAL ${retention_days} DAY)"
    local to_days_cutoff
    to_days_cutoff=$(mysql_query "$sql_cutoff" | tail -1)
    
    log_verbose "TO_DAYS cutoff: $to_days_cutoff"
    
    # Query partitions from information_schema
    local sql="
    SELECT PARTITION_NAME
    FROM information_schema.PARTITIONS
    WHERE TABLE_SCHEMA = '${DATABASE}'
      AND TABLE_NAME = '${table}'
      AND PARTITION_NAME IS NOT NULL
      AND PARTITION_NAME != 'pFUTURE'
      AND PARTITION_DESCRIPTION != 'MAXVALUE'
      AND CAST(PARTITION_DESCRIPTION AS UNSIGNED) < ${to_days_cutoff}
    ORDER BY PARTITION_DESCRIPTION;
    "
    
    local partitions
    partitions=$(mysql_query "$sql")
    
    if [[ -z "$partitions" ]]; then
        log_verbose "No partitions found to drop"
        echo ""
        return 0
    fi
    
    local partition_count
    partition_count=$(echo "$partitions" | wc -l)
    local partition_names
    partition_names=$(echo "$partitions" | tr '\n' ' ' | sed 's/ $//')
    log_verbose "Found ${partition_count} partition(s) to drop: $partition_names"
    
    echo "$partitions"
    return 0
}

execute_partition_drop_cleanup() {
    local table=${1:-cleanup_partitioned}
    local retention_days=${2:-10}
    
    log "Executing DROP PARTITION cleanup on ${DATABASE}.${table}"
    log "Retention: ${retention_days} days"
    
    # Identify partitions to drop
    local partitions
    partitions=$(identify_old_partitions "$table" "$retention_days")
    
    if [[ -z "$partitions" ]]; then
        log "No partitions to drop, cleanup complete"
        return 0
    fi
    
    # Count partitions
    local partition_count
    partition_count=$(echo "$partitions" | wc -l)
    
    # Build partition list for ALTER TABLE (comma-separated)
    local partition_list
    partition_list=$(echo "$partitions" | tr '\n' ',' | sed 's/,$//')
    
    log "Dropping ${partition_count} partition(s): $partition_list"
    
    # Execute DROP PARTITION
    local sql="ALTER TABLE \`${DATABASE}\`.\`${table}\` DROP PARTITION ${partition_list};"
    
    log_verbose "SQL: $sql"
    mysql_query "$sql"
    
    if [[ $? -ne 0 ]]; then
        log_error "DROP PARTITION failed"
        return 1
    fi
    
    log "DROP PARTITION completed successfully"
    return 0
}

run_partition_drop_cleanup() {
    local table=${1:-cleanup_partitioned}
    local retention_days=${2:-10}
    local method="partition_drop"
    
    log "Starting DROP PARTITION cleanup with metrics collection"
    log "Table: ${DATABASE}.${table}, Retention: ${retention_days} days"
    
    # Pre-cleanup snapshot
    local snapshot_before
    snapshot_before=$(capture_metrics_snapshot "before" "$table")
    local start_ts
    start_ts=$(get_timestamp)
    
    # Execute cleanup
    execute_partition_drop_cleanup "$table" "$retention_days"
    local exit_code=$?
    
    # Post-cleanup snapshot
    local end_ts
    end_ts=$(get_timestamp)
    local snapshot_after
    snapshot_after=$(capture_metrics_snapshot "after" "$table")
    
    # Calculate duration
    local duration
    duration=$(calculate_duration "$start_ts" "$end_ts")
    
    # Log metrics
    if [[ $exit_code -eq 0 ]]; then
        log_metrics "$method" "$table" "$snapshot_before" "$snapshot_after" "$duration"
        log "DROP PARTITION cleanup complete: duration=${duration}s"
    else
        log_error "DROP PARTITION cleanup failed"
        return 1
    fi
    
    return 0
}

#############################################################################
# Method 3: Copy-to-New-Table
# Creates new table with recent data, swaps tables, drops old
# WARNING: Data written during execution is LOST
#############################################################################

execute_copy_cleanup() {
    local table=${1:-cleanup_copy}
    local retention_days=${2:-10}
    local temp_table="${table}_new"
    local old_table="${table}_old"
    
    log "Executing copy-to-new-table cleanup on ${DATABASE}.${table}"
    log "Retention: ${retention_days} days"
    log "WARNING: Data written during this operation will be LOST"
    
    # Step 1: Create new table with same structure
    log "Step 1/4: Creating new table ${temp_table}"
    local sql_create="CREATE TABLE \`${DATABASE}\`.\`${temp_table}\` LIKE \`${DATABASE}\`.\`${table}\`;"
    
    mysql_query "$sql_create"
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create new table"
        return 1
    fi
    
    # Step 2: Copy recent data (keep data newer than retention_days)
    log "Step 2/4: Copying data to new table (retaining data < ${retention_days} days old)"
    local sql_insert="
    INSERT INTO \`${DATABASE}\`.\`${temp_table}\`
    SELECT * FROM \`${DATABASE}\`.\`${table}\`
    WHERE ts >= NOW() - INTERVAL ${retention_days} DAY;
    "
    
    mysql_query "$sql_insert"
    if [[ $? -ne 0 ]]; then
        log_error "Failed to copy data to new table"
        # Cleanup: drop temp table
        mysql_query "DROP TABLE IF EXISTS \`${DATABASE}\`.\`${temp_table}\`;" 2>/dev/null
        return 1
    fi
    
    # Step 3: Atomic table swap
    log "Step 3/4: Swapping tables (brief lock)"
    local sql_rename="
    RENAME TABLE 
        \`${DATABASE}\`.\`${table}\` TO \`${DATABASE}\`.\`${old_table}\`,
        \`${DATABASE}\`.\`${temp_table}\` TO \`${DATABASE}\`.\`${table}\`;
    "
    
    mysql_query "$sql_rename"
    if [[ $? -ne 0 ]]; then
        log_error "Failed to rename tables"
        # Cleanup: drop temp table
        mysql_query "DROP TABLE IF EXISTS \`${DATABASE}\`.\`${temp_table}\`;" 2>/dev/null
        return 1
    fi
    
    # Step 4: Drop old table
    log "Step 4/4: Dropping old table"
    local sql_drop="DROP TABLE \`${DATABASE}\`.\`${old_table}\`;"
    
    mysql_query "$sql_drop"
    if [[ $? -ne 0 ]]; then
        log "WARNING: Failed to drop old table, but cleanup succeeded"
        # Not critical - table swap already happened
    fi
    
    log "Copy-to-new-table cleanup completed successfully"
    return 0
}

run_copy_cleanup() {
    local table=${1:-cleanup_copy}
    local retention_days=${2:-10}
    local method="copy"
    
    log "Starting copy-to-new-table cleanup with metrics collection"
    log "Table: ${DATABASE}.${table}, Retention: ${retention_days} days"
    
    # Pre-cleanup snapshot
    local snapshot_before
    snapshot_before=$(capture_metrics_snapshot "before" "$table")
    local start_ts
    start_ts=$(get_timestamp)
    
    # Execute cleanup
    execute_copy_cleanup "$table" "$retention_days"
    local exit_code=$?
    
    # Post-cleanup snapshot
    local end_ts
    end_ts=$(get_timestamp)
    local snapshot_after
    snapshot_after=$(capture_metrics_snapshot "after" "$table")
    
    # Calculate duration
    local duration
    duration=$(calculate_duration "$start_ts" "$end_ts")
    
    # Log metrics
    if [[ $exit_code -eq 0 ]]; then
        log_metrics "$method" "$table" "$snapshot_before" "$snapshot_after" "$duration"
        log "Copy-to-new-table cleanup complete: duration=${duration}s"
    else
        log_error "Copy-to-new-table cleanup failed"
        return 1
    fi
    
    return 0
}

#############################################################################
# Method 4: Batch DELETE
# Deletes data in small batches
# Table stays online but space is NOT freed (requires OPTIMIZE TABLE)
#############################################################################

execute_batch_delete_cleanup() {
    local table=${1:-cleanup_batch}
    local retention_days=${2:-10}
    local batch_size=${3:-5000}
    local batch_delay=${4:-0.1}
    
    log "Executing batch DELETE cleanup on ${DATABASE}.${table}"
    log "Parameters: retention=${retention_days}d, batch_size=${batch_size}, delay=${batch_delay}s"
    
    # Initialize counters
    local batch_num=0
    local total_deleted=0
    local rows_affected=1
    
    # Create batch log file
    local batch_log="${RESULTS_DIR}/batch_delete_${batch_size}_$(date +%Y%m%d_%H%M%S)_batches.csv"
    echo "batch_id,timestamp,rows_deleted,duration_sec,throughput_rows_per_sec,replication_lag_sec" > "$batch_log"
    
    log "Per-batch metrics will be logged to: $batch_log"
    
    # Execute DELETE in batches
    while [[ $rows_affected -gt 0 ]]; do
        batch_num=$((batch_num + 1))
        
        # Record batch start
        local batch_start
        batch_start=$(get_timestamp)
        local batch_start_readable
        batch_start_readable=$(date +"%Y-%m-%d %H:%M:%S")
        
        # Execute DELETE for one batch
        local sql="
        DELETE FROM \`${DATABASE}\`.\`${table}\`
        WHERE ts < NOW() - INTERVAL ${retention_days} DAY
        ORDER BY ts
        LIMIT ${batch_size};
        "
        
        # Execute DELETE and get rows affected in same connection
        # ROW_COUNT() must be called in the same connection as the DELETE
        local combined_sql="${sql}SELECT ROW_COUNT() as rows_affected;"
        rows_affected=$(mysql_query "$combined_sql" | tail -1)
        
        # Validate rows_affected is a number
        if ! [[ "$rows_affected" =~ ^[0-9]+$ ]]; then
            log_error "Invalid rows_affected value: '$rows_affected'"
            rows_affected=0
        fi
        
        # Record batch end
        local batch_end
        batch_end=$(get_timestamp)
        local batch_duration
        batch_duration=$(calculate_duration "$batch_start" "$batch_end")
        
        # Calculate batch throughput
        local batch_throughput=0
        if [[ $rows_affected -gt 0 ]]; then
            batch_throughput=$(awk "BEGIN {printf \"%.2f\", $rows_affected / $batch_duration}")
            total_deleted=$((total_deleted + rows_affected))
            
            # Get current replication lag
            local current_lag
            current_lag=$(get_replication_lag)
            
            # Log batch metrics
            echo "${batch_num},${batch_start_readable},${rows_affected},${batch_duration},${batch_throughput},${current_lag}" >> "$batch_log"
            
            log "Batch ${batch_num}: deleted ${rows_affected} rows in ${batch_duration}s (${batch_throughput} rows/sec, repl_lag=${current_lag}s)"
            
            # Sleep between batches if more work to do
            if [[ $rows_affected -eq $batch_size ]]; then
                sleep "$batch_delay"
            fi
        else
            log "No more rows to delete, cleanup complete"
            break
        fi
        
        # Safety check: prevent infinite loop
        if [[ $batch_num -ge 10000 ]]; then
            log_error "Exceeded maximum batch count (10000), aborting"
            return 1
        fi
    done
    
    log "Batch DELETE completed: ${batch_num} batches, ${total_deleted} total rows deleted"
    
    # Analyze batch metrics
    analyze_batch_metrics "$batch_log"
    
    return 0
}

run_batch_delete_cleanup() {
    local table=${1:-cleanup_batch}
    local retention_days=${2:-10}
    local batch_size=${3:-5000}
    local batch_delay=${4:-0.1}
    local method="batch_delete_${batch_size}"
    
    log "Starting batch DELETE cleanup with metrics collection"
    log "Table: ${DATABASE}.${table}, Retention: ${retention_days} days"
    log "Batch size: ${batch_size}, Delay: ${batch_delay}s"
    
    # Pre-cleanup snapshot
    local snapshot_before
    snapshot_before=$(capture_metrics_snapshot "before" "$table")
    local start_ts
    start_ts=$(get_timestamp)
    
    # Execute cleanup
    execute_batch_delete_cleanup "$table" "$retention_days" "$batch_size" "$batch_delay"
    local exit_code=$?
    
    # Post-cleanup snapshot
    local end_ts
    end_ts=$(get_timestamp)
    local snapshot_after
    snapshot_after=$(capture_metrics_snapshot "after" "$table")
    
    # Calculate duration
    local duration
    duration=$(calculate_duration "$start_ts" "$end_ts")
    
    # Log metrics
    if [[ $exit_code -eq 0 ]]; then
        log_metrics "$method" "$table" "$snapshot_before" "$snapshot_after" "$duration"
        log "Batch DELETE cleanup complete: duration=${duration}s"
        log "NOTE: Space not freed - run OPTIMIZE TABLE to reclaim space"
    else
        log_error "Batch DELETE cleanup failed"
        return 1
    fi
    
    return 0
}

#############################################################################
# Run All Methods Sequentially
#############################################################################

run_all_methods() {
    local retention_days=${1:-10}
    local batch_size=${2:-5000}
    
    log "=========================================="
    log "Running ALL cleanup methods sequentially"
    log "Retention: ${retention_days} days"
    log "Batch size (for DELETE): ${batch_size}"
    log "=========================================="
    
    # Method 1: Partition Drop
    log ""
    log "=== Method 1: DROP PARTITION ==="
    run_partition_drop_cleanup "cleanup_partitioned" "$retention_days"
    
    # Method 2: Truncate
    log ""
    log "=== Method 2: TRUNCATE TABLE ==="
    log "WARNING: This removes ALL data (not selective)"
    run_truncate_cleanup "cleanup_truncate"
    
    # Method 3: Copy
    log ""
    log "=== Method 3: Copy-to-New-Table ==="
    run_copy_cleanup "cleanup_copy" "$retention_days"
    
    # Method 4: Batch Delete
    log ""
    log "=== Method 4: Batch DELETE ==="
    run_batch_delete_cleanup "cleanup_batch" "$retention_days" "$batch_size"
    
    log ""
    log "=========================================="
    log "All methods completed"
    log "Results saved to: $RESULTS_DIR"
    log "=========================================="
}
