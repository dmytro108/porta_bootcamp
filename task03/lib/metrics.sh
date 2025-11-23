#!/bin/bash

#############################################################################
# MySQL Cleanup Benchmark - Metrics Collection Library
#
# This module provides comprehensive metrics collection functions:
# - InnoDB metrics (history list, locks, row operations)
# - Replication metrics (lag, status)
# - Binary log metrics (size, active binlog)
# - Query latency measurement
# - Metrics snapshot system
# - Metrics logging and analysis
#
# Usage:
#   source lib/metrics.sh
#
# Dependencies:
#   - lib/helpers.sh must be sourced first
#
#############################################################################

#############################################################################
# InnoDB Metrics Functions
#############################################################################

# Get InnoDB history list length (purge lag indicator)
get_history_list_length() {
    local host=${1:-${MYSQL_HOST:-localhost}}
    
    log_verbose "Querying InnoDB history list length"
    
    # Try information_schema first (faster) - requires PROCESS privilege
    local hll
    hll=$(mysql_query "SELECT COUNT FROM information_schema.INNODB_METRICS \
                       WHERE NAME = 'trx_rseg_history_len'" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host" "cleanup_bench" 2>/dev/null || echo "")
    
    if [[ -n "$hll" && "$hll" != "ERROR"* ]]; then
        echo "$hll"
        return 0
    fi
    
    # Fallback: parse SHOW ENGINE INNODB STATUS - also requires PROCESS privilege
    local status
    status=$(mysql_query "SHOW ENGINE INNODB STATUS\\G" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host" "cleanup_bench" 2>/dev/null || echo "")
    
    if [[ -n "$status" ]]; then
        local hll_value
        hll_value=$(echo "$status" | grep "History list length" | awk '{print $4}')
        if [[ -n "$hll_value" ]]; then
            echo "$hll_value"
            return 0
        fi
    fi
    
    # If both methods fail (insufficient privileges), return -1
    log_verbose "Unable to query history list length (PROCESS privilege required)"
    echo "-1"
}

# Get lock wait metrics
get_lock_metrics() {
    local host=${1:-${MYSQL_HOST:-localhost}}
    
    log_verbose "Querying lock metrics"
    
    local lock_time
    local lock_waits
    
    lock_time=$(get_status_var "Innodb_row_lock_time" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host" "cleanup_bench" 2>/dev/null)
    lock_waits=$(get_status_var "Innodb_row_lock_waits" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host" "cleanup_bench" 2>/dev/null)
    
    # Ensure we always return valid numbers
    echo "${lock_time:-0} ${lock_waits:-0}"
}

# Get InnoDB row operation counters
get_innodb_row_operations() {
    local host=${1:-${MYSQL_HOST:-localhost}}
    
    log_verbose "Querying InnoDB row operations"
    
    local deleted inserted updated read
    
    deleted=$(get_status_var "Innodb_rows_deleted" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host" "cleanup_bench" 2>/dev/null)
    inserted=$(get_status_var "Innodb_rows_inserted" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host" "cleanup_bench" 2>/dev/null)
    updated=$(get_status_var "Innodb_rows_updated" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host" "cleanup_bench" 2>/dev/null)
    read=$(get_status_var "Innodb_rows_read" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host" "cleanup_bench" 2>/dev/null)
    
    # Ensure we always return valid numbers
    echo "${deleted:-0} ${inserted:-0} ${updated:-0} ${read:-0}"
}

#############################################################################
# Replication Metrics Functions
#############################################################################

# Get replication lag from replica
get_replication_lag() {
    local replica_host=${1:-${DB_SLAVE_HOST:-}}
    
    if [[ -z "$replica_host" ]]; then
        log_verbose "No replica host configured, skipping replication lag"
        echo "-1"
        return 0
    fi
    
    log_verbose "Querying replication lag from $replica_host"
    
    # Query without --skip-column-names for proper \G format parsing
    # Try MySQL 8.0+ syntax first
    local lag
    lag=$(mysql -h"$replica_host" -u"${CLEANUP_USER}" -p"${CLEANUP_PASSW}" \
          -e "SHOW REPLICA STATUS\G" 2>/dev/null | \
          grep "Seconds_Behind_Source:" | awk '{print $2}')
    
    if [[ -z "$lag" ]]; then
        # Fallback to MySQL 5.7 syntax
        lag=$(mysql -h"$replica_host" -u"${CLEANUP_USER}" -p"${CLEANUP_PASSW}" \
              -e "SHOW SLAVE STATUS\G" 2>/dev/null | \
              grep "Seconds_Behind_Master:" | awk '{print $2}')
    fi
    
    # Return lag or -1 if unavailable
    if [[ -z "$lag" || "$lag" == "NULL" ]]; then
        log_verbose "Unable to query replication lag (REPLICATION CLIENT privilege may be required)"
        echo "-1"
    else
        echo "$lag"
    fi
}

# Get full replication status
get_replication_status() {
    local replica_host=${1:-${DB_SLAVE_HOST:-}}
    
    if [[ -z "$replica_host" ]]; then
        echo "NO_REPLICA_CONFIGURED"
        return 0
    fi
    
    log_verbose "Querying replication status from $replica_host"
    
    # Query without --skip-column-names for proper \G format parsing
    # Try MySQL 8.0+ syntax first
    local status
    status=$(mysql -h"$replica_host" -u"${CLEANUP_USER}" -p"${CLEANUP_PASSW}" \
             -e "SHOW REPLICA STATUS\G" 2>/dev/null || true)
    
    if [[ -z "$status" ]]; then
        # Fallback to MySQL 5.7 syntax
        status=$(mysql -h"$replica_host" -u"${CLEANUP_USER}" -p"${CLEANUP_PASSW}" \
                 -e "SHOW SLAVE STATUS\G" 2>/dev/null || true)
    fi
    
    if [[ -z "$status" ]]; then
        log_verbose "Unable to query replication status (REPLICATION CLIENT privilege may be required)"
        echo "UNAVAILABLE"
        return 0
    fi
    
    # Extract key fields
    local io_running sql_running lag
    io_running=$(echo "$status" | grep -E "(Replica|Slave)_IO_Running:" | awk '{print $2}')
    sql_running=$(echo "$status" | grep -E "(Replica|Slave)_SQL_Running:" | awk '{print $2}')
    lag=$(echo "$status" | grep -E "Seconds_Behind_(Source|Master):" | awk '{print $2}')
    
    echo "${io_running:-No} ${sql_running:-No} ${lag:-NULL}"
}

#############################################################################
# Binary Log Metrics Functions
#############################################################################

# Get list of binary logs with sizes
get_binlog_list() {
    local host=${1:-${MYSQL_HOST:-localhost}}
    
    log_verbose "Querying binary log list"
    local result
    result=$(mysql_query "SHOW BINARY LOGS" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host" "cleanup_bench" 2>/dev/null || echo "")
    
    # Return empty if query failed (insufficient privileges)
    if [[ -z "$result" || "$result" == *"ERROR"* ]]; then
        log_verbose "Unable to query binary logs (REPLICATION CLIENT privilege may be required)"
        echo ""
        return 0
    fi
    
    echo "$result"
}

# Get total binary log size
get_binlog_size() {
    local host=${1:-${MYSQL_HOST:-localhost}}
    
    log_verbose "Calculating total binlog size"
    
    local binlogs
    binlogs=$(get_binlog_list "$host")
    
    if [[ -z "$binlogs" ]]; then
        echo "0"
        return 0
    fi
    
    echo "$binlogs" | awk '{sum += $2} END {print sum}'
}

# Get active binary log name
get_active_binlog() {
    local host=${1:-${MYSQL_HOST:-localhost}}
    
    log_verbose "Querying active binlog"
    local result
    result=$(mysql_query "SHOW MASTER STATUS" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host" "cleanup_bench" 2>/dev/null | awk '{print $1}')
    
    # Return "unavailable" if query failed
    if [[ -z "$result" ]]; then
        log_verbose "Unable to query master status (REPLICATION CLIENT privilege may be required)"
        echo "unavailable"
    else
        echo "$result"
    fi
}

#############################################################################
# Query Latency Measurement Functions
#############################################################################

# Measure single query execution time in milliseconds
measure_query_latency() {
    local query=$1
    local host=${2:-${MYSQL_HOST:-localhost}}
    
    log_verbose "Measuring query latency: ${query:0:50}..."
    
    local start_ts end_ts duration_sec duration_ms
    start_ts=$(get_timestamp)
    
    mysql_query "$query" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host" "cleanup_bench" > /dev/null 2>&1
    
    end_ts=$(get_timestamp)
    duration_sec=$(calculate_duration "$start_ts" "$end_ts")
    duration_ms=$(awk "BEGIN {printf \"%.2f\", $duration_sec * 1000}")
    
    echo "$duration_ms"
}

# Measure query latency multiple times and return statistics
measure_latency_batch() {
    local query=$1
    local count=${2:-10}
    local host=${3:-${MYSQL_HOST:-localhost}}
    
    log_verbose "Measuring query latency $count times"
    
    local latencies=()
    local sum=0
    
    for ((i=1; i<=count; i++)); do
        local latency
        latency=$(measure_query_latency "$query" "$host")
        latencies+=("$latency")
        sum=$(awk "BEGIN {printf \"%.2f\", $sum + $latency}")
    done
    
    # Calculate average
    local avg
    avg=$(awk "BEGIN {printf \"%.2f\", $sum / $count}")
    
    # Calculate p95 (simple: sort and take 95th percentile)
    local p95_index
    p95_index=$(awk "BEGIN {printf \"%d\", ($count * 95) / 100}")
    local sorted
    sorted=($(printf '%s\n' "${latencies[@]}" | sort -n))
    local p95="${sorted[$p95_index]}"
    
    echo "$avg $p95"
}

# Measure baseline latency before cleanup
measure_latency_baseline() {
    local table=$1
    local database=${2:-${DATABASE:-cleanup_bench}}
    
    log "Measuring baseline query latency for $table..."
    
    # SELECT latency
    local select_query="SELECT * FROM \`$database\`.\`$table\` WHERE ts >= NOW() - INTERVAL 5 MINUTE ORDER BY ts DESC LIMIT 10"
    local select_stats
    select_stats=$(measure_latency_batch "$select_query" 10)
    
    # UPDATE latency
    local update_query="UPDATE \`$database\`.\`$table\` SET data = data + 1 WHERE ts >= NOW() - INTERVAL 10 MINUTE LIMIT 10"
    local update_stats
    update_stats=$(measure_latency_batch "$update_query" 10)
    
    echo "$select_stats $update_stats"
}

#############################################################################
# Metrics Snapshot System
#############################################################################

# Capture comprehensive metrics snapshot
capture_metrics_snapshot() {
    local label=$1
    local table=$2
    local database=${3:-${DATABASE:-cleanup_bench}}
    local host=${4:-${MYSQL_HOST:-localhost}}
    
    log_verbose "Capturing metrics snapshot: $label"
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Row count
    local row_count
    row_count=$(get_row_count "$database" "$table" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host")
    
    # Table info
    local table_info
    table_info=$(get_table_info "$database" "$table" "${CLEANUP_USER}" "${CLEANUP_PASSW}" "$host")
    read -r data_length index_length data_free table_rows <<< "$table_info"
    
    # InnoDB metrics
    local row_ops
    row_ops=$(get_innodb_row_operations "$host")
    read -r innodb_deleted innodb_inserted innodb_updated innodb_read <<< "$row_ops"
    
    # Lock metrics
    local lock_metrics
    lock_metrics=$(get_lock_metrics "$host")
    read -r lock_time lock_waits <<< "$lock_metrics"
    
    # History list length
    local hll
    hll=$(get_history_list_length "$host")
    
    # Replication metrics
    local repl_lag repl_status
    repl_lag=$(get_replication_lag)
    repl_status=$(get_replication_status)
    
    # Binlog size
    local binlog_size active_binlog
    binlog_size=$(get_binlog_size "$host")
    active_binlog=$(get_active_binlog "$host")
    
    # Create snapshot data structure (space-separated for easy parsing)
    cat <<-EOF
		SNAPSHOT:$label
		TIMESTAMP:$timestamp
		ROW_COUNT:$row_count
		DATA_LENGTH:$data_length
		INDEX_LENGTH:$index_length
		DATA_FREE:$data_free
		TABLE_ROWS:$table_rows
		INNODB_DELETED:$innodb_deleted
		INNODB_INSERTED:$innodb_inserted
		INNODB_UPDATED:$innodb_updated
		INNODB_READ:$innodb_read
		LOCK_TIME:$lock_time
		LOCK_WAITS:$lock_waits
		HISTORY_LIST_LENGTH:$hll
		REPL_LAG:$repl_lag
		REPL_STATUS:$repl_status
		BINLOG_SIZE:$binlog_size
		ACTIVE_BINLOG:$active_binlog
	EOF
}

# Parse snapshot data
parse_snapshot() {
    local snapshot=$1
    local field=$2
    
    echo "$snapshot" | grep "^${field}:" | cut -d: -f2
}

# Calculate metrics diff between snapshots
calculate_metrics_diff() {
    local snapshot_before=$1
    local snapshot_after=$2
    
    log_verbose "Calculating metrics diff"
    
    # Extract values
    local rows_before rows_after
    rows_before=$(parse_snapshot "$snapshot_before" "ROW_COUNT")
    rows_after=$(parse_snapshot "$snapshot_after" "ROW_COUNT")
    
    local data_len_before data_len_after
    data_len_before=$(parse_snapshot "$snapshot_before" "DATA_LENGTH")
    data_len_after=$(parse_snapshot "$snapshot_after" "DATA_LENGTH")
    
    local idx_len_before idx_len_after
    idx_len_before=$(parse_snapshot "$snapshot_before" "INDEX_LENGTH")
    idx_len_after=$(parse_snapshot "$snapshot_after" "INDEX_LENGTH")
    
    local data_free_before data_free_after
    data_free_before=$(parse_snapshot "$snapshot_before" "DATA_FREE")
    data_free_after=$(parse_snapshot "$snapshot_after" "DATA_FREE")
    
    local innodb_del_before innodb_del_after
    innodb_del_before=$(parse_snapshot "$snapshot_before" "INNODB_DELETED")
    innodb_del_after=$(parse_snapshot "$snapshot_after" "INNODB_DELETED")
    
    local lock_time_before lock_time_after
    lock_time_before=$(parse_snapshot "$snapshot_before" "LOCK_TIME")
    lock_time_after=$(parse_snapshot "$snapshot_after" "LOCK_TIME")
    
    local lock_waits_before lock_waits_after
    lock_waits_before=$(parse_snapshot "$snapshot_before" "LOCK_WAITS")
    lock_waits_after=$(parse_snapshot "$snapshot_after" "LOCK_WAITS")
    
    local binlog_before binlog_after
    binlog_before=$(parse_snapshot "$snapshot_before" "BINLOG_SIZE")
    binlog_after=$(parse_snapshot "$snapshot_after" "BINLOG_SIZE")
    
    # Ensure all values are numbers (default to 0 if empty)
    rows_before=${rows_before:-0}
    rows_after=${rows_after:-0}
    data_len_before=${data_len_before:-0}
    data_len_after=${data_len_after:-0}
    idx_len_before=${idx_len_before:-0}
    idx_len_after=${idx_len_after:-0}
    data_free_before=${data_free_before:-0}
    data_free_after=${data_free_after:-0}
    innodb_del_before=${innodb_del_before:-0}
    innodb_del_after=${innodb_del_after:-0}
    lock_time_before=${lock_time_before:-0}
    lock_time_after=${lock_time_after:-0}
    lock_waits_before=${lock_waits_before:-0}
    lock_waits_after=${lock_waits_after:-0}
    binlog_before=${binlog_before:-0}
    binlog_after=${binlog_after:-0}
    
    # Calculate deltas
    local rows_deleted
    rows_deleted=$((rows_before - rows_after))
    
    local space_freed
    space_freed=$(( (data_len_before + idx_len_before) - (data_len_after + idx_len_after) ))
    
    local data_free_change
    data_free_change=$((data_free_after - data_free_before))
    
    local innodb_deleted_delta
    innodb_deleted_delta=$((innodb_del_after - innodb_del_before))
    
    local lock_time_delta
    lock_time_delta=$((lock_time_after - lock_time_before))
    
    local lock_waits_delta
    lock_waits_delta=$((lock_waits_after - lock_waits_before))
    
    local binlog_growth
    binlog_growth=$((binlog_after - binlog_before))
    
    # Output diff data
    cat <<-EOF
		ROWS_DELETED:$rows_deleted
		SPACE_FREED:$space_freed
		DATA_FREE_CHANGE:$data_free_change
		INNODB_DELETED_DELTA:$innodb_deleted_delta
		LOCK_TIME_DELTA:$lock_time_delta
		LOCK_WAITS_DELTA:$lock_waits_delta
		BINLOG_GROWTH:$binlog_growth
	EOF
}

#############################################################################
# Metrics Logging
#############################################################################

# Log metrics to file
log_metrics() {
    local method=$1
    local table=$2
    local snapshot_before=$3
    local snapshot_after=$4
    local duration=$5
    local latency_baseline=${6:-}
    local latency_recovery=${7:-}
    
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    
    local log_file="${RESULTS_DIR}/${method}_${timestamp}_metrics.log"
    
    log "Writing metrics to $log_file"
    
    # Extract key values
    local start_time end_time
    start_time=$(parse_snapshot "$snapshot_before" "TIMESTAMP")
    end_time=$(parse_snapshot "$snapshot_after" "TIMESTAMP")
    
    local rows_before rows_after
    rows_before=$(parse_snapshot "$snapshot_before" "ROW_COUNT")
    rows_after=$(parse_snapshot "$snapshot_after" "ROW_COUNT")
    
    # Calculate diff
    local diff
    diff=$(calculate_metrics_diff "$snapshot_before" "$snapshot_after")
    
    local rows_deleted space_freed binlog_growth
    rows_deleted=$(parse_snapshot "$diff" "ROWS_DELETED")
    space_freed=$(parse_snapshot "$diff" "SPACE_FREED")
    binlog_growth=$(parse_snapshot "$diff" "BINLOG_GROWTH")
    
    # Calculate throughput
    local throughput
    if (( $(awk "BEGIN {print ($duration > 0)}") )); then
        throughput=$(awk "BEGIN {printf \"%.2f\", $rows_deleted / $duration}")
    else
        throughput="Infinity"
    fi
    
    # Calculate space in MB
    local space_freed_mb binlog_growth_mb
    space_freed_mb=$(awk "BEGIN {printf \"%.2f\", $space_freed / 1048576}")
    binlog_growth_mb=$(awk "BEGIN {printf \"%.2f\", $binlog_growth / 1048576}")
    
    # Write log file
    cat > "$log_file" <<-EOF
		=== Cleanup Metrics Report ===
		Method:              $method
		Table:               $table
		Start Time:          $start_time
		End Time:            $end_time
		Duration:            $duration seconds
		
		=== Row Statistics ===
		Rows Before:         $rows_before
		Rows After:          $rows_after
		Rows Deleted:        $rows_deleted
		Delete Throughput:   $throughput rows/sec
		
		=== InnoDB Metrics ===
	EOF
    
    # Add InnoDB metrics details
    parse_snapshot "$snapshot_before" "INNODB_DELETED" | \
        xargs -I {} echo "Innodb_rows_deleted (before):  {}" >> "$log_file"
    parse_snapshot "$snapshot_after" "INNODB_DELETED" | \
        xargs -I {} echo "Innodb_rows_deleted (after):   {}" >> "$log_file"
    parse_snapshot "$diff" "INNODB_DELETED_DELTA" | \
        xargs -I {} echo "Delta:                          {}" >> "$log_file"
    echo "" >> "$log_file"
    
    parse_snapshot "$snapshot_before" "LOCK_TIME" | \
        xargs -I {} echo "Innodb_row_lock_time (before): {} ms" >> "$log_file"
    parse_snapshot "$snapshot_after" "LOCK_TIME" | \
        xargs -I {} echo "Innodb_row_lock_time (after):  {} ms" >> "$log_file"
    parse_snapshot "$diff" "LOCK_TIME_DELTA" | \
        xargs -I {} echo "Delta:                          {} ms" >> "$log_file"
    echo "" >> "$log_file"
    
    parse_snapshot "$snapshot_before" "LOCK_WAITS" | \
        xargs -I {} echo "Innodb_row_lock_waits (before): {}" >> "$log_file"
    parse_snapshot "$snapshot_after" "LOCK_WAITS" | \
        xargs -I {} echo "Innodb_row_lock_waits (after):  {}" >> "$log_file"
    parse_snapshot "$diff" "LOCK_WAITS_DELTA" | \
        xargs -I {} echo "Delta:                          {}" >> "$log_file"
    echo "" >> "$log_file"
    
    parse_snapshot "$snapshot_before" "HISTORY_LIST_LENGTH" | \
        xargs -I {} echo "History List Length (before):   {}" >> "$log_file"
    parse_snapshot "$snapshot_after" "HISTORY_LIST_LENGTH" | \
        xargs -I {} echo "History List Length (after):    {}" >> "$log_file"
    
    # Add replication metrics
    cat >> "$log_file" <<-EOF
		
		=== Replication Metrics ===
	EOF
    
    local repl_lag_before repl_lag_after
    repl_lag_before=$(parse_snapshot "$snapshot_before" "REPL_LAG")
    repl_lag_after=$(parse_snapshot "$snapshot_after" "REPL_LAG")
    
    if [[ "$repl_lag_before" == "-1" ]]; then
        # Check if DB_SLAVE_HOST is configured
        if [[ -n "${DB_SLAVE_HOST:-}" ]]; then
            echo "Replication metrics unavailable (REPLICATION CLIENT privilege required)" >> "$log_file"
            echo "Replica host configured: ${DB_SLAVE_HOST}" >> "$log_file"
        else
            echo "Replication metrics unavailable (no replica configured)" >> "$log_file"
        fi
    else
        echo "Seconds_Behind_Source (before):  $repl_lag_before" >> "$log_file"
        echo "Seconds_Behind_Source (after):   $repl_lag_after" >> "$log_file"
    fi
    
    # Add table size metrics
    cat >> "$log_file" <<-EOF
		
		=== Table Size Metrics ===
	EOF
    
    local data_len_before_val data_len_after_val
    data_len_before_val=$(parse_snapshot "$snapshot_before" "DATA_LENGTH")
    data_len_before_val=${data_len_before_val:-0}
    data_len_after_val=$(parse_snapshot "$snapshot_after" "DATA_LENGTH")
    data_len_after_val=${data_len_after_val:-0}
    
    local data_len_before_mb data_len_after_mb
    data_len_before_mb=$(awk "BEGIN {printf \"%.2f\", $data_len_before_val / 1048576}")
    data_len_after_mb=$(awk "BEGIN {printf \"%.2f\", $data_len_after_val / 1048576}")
    
    echo "DATA_LENGTH (before):    $data_len_before_val bytes ($data_len_before_mb MB)" >> "$log_file"
    echo "DATA_LENGTH (after):     $data_len_after_val bytes ($data_len_after_mb MB)" >> "$log_file"
    
    local idx_len_before_val idx_len_after_val
    idx_len_before_val=$(parse_snapshot "$snapshot_before" "INDEX_LENGTH")
    idx_len_before_val=${idx_len_before_val:-0}
    idx_len_after_val=$(parse_snapshot "$snapshot_after" "INDEX_LENGTH")
    idx_len_after_val=${idx_len_after_val:-0}
    
    local idx_len_before_mb idx_len_after_mb
    idx_len_before_mb=$(awk "BEGIN {printf \"%.2f\", $idx_len_before_val / 1048576}")
    idx_len_after_mb=$(awk "BEGIN {printf \"%.2f\", $idx_len_after_val / 1048576}")
    
    echo "INDEX_LENGTH (before):   $idx_len_before_val bytes ($idx_len_before_mb MB)" >> "$log_file"
    echo "INDEX_LENGTH (after):    $idx_len_after_val bytes ($idx_len_after_mb MB)" >> "$log_file"
    
    local data_free_before_val data_free_after_val
    data_free_before_val=$(parse_snapshot "$snapshot_before" "DATA_FREE")
    data_free_before_val=${data_free_before_val:-0}
    data_free_after_val=$(parse_snapshot "$snapshot_after" "DATA_FREE")
    data_free_after_val=${data_free_after_val:-0}
    
    local data_free_before_mb data_free_after_mb
    data_free_before_mb=$(awk "BEGIN {printf \"%.2f\", $data_free_before_val / 1048576}")
    data_free_after_mb=$(awk "BEGIN {printf \"%.2f\", $data_free_after_val / 1048576}")
    
    echo "DATA_FREE (before):      $data_free_before_val bytes ($data_free_before_mb MB)" >> "$log_file"
    echo "DATA_FREE (after):       $data_free_after_val bytes ($data_free_after_mb MB)" >> "$log_file"
    
    echo "Space Freed to OS:       $space_freed bytes ($space_freed_mb MB)" >> "$log_file"
    
    # Calculate fragmentation
    local data_len_after_frag idx_len_after_frag data_free_after_frag total_size frag_pct
    data_len_after_frag=$(parse_snapshot "$snapshot_after" "DATA_LENGTH")
    data_len_after_frag=${data_len_after_frag:-0}
    idx_len_after_frag=$(parse_snapshot "$snapshot_after" "INDEX_LENGTH")
    idx_len_after_frag=${idx_len_after_frag:-0}
    data_free_after_frag=$(parse_snapshot "$snapshot_after" "DATA_FREE")
    data_free_after_frag=${data_free_after_frag:-0}
    total_size=$((data_len_after_frag + idx_len_after_frag + data_free_after_frag))
    
    if (( total_size > 0 )); then
        frag_pct=$(awk "BEGIN {printf \"%.2f\", ($data_free_after_frag * 100) / $total_size}")
        echo "Fragmentation:           $frag_pct%" >> "$log_file"
    fi
    
    # Add binlog metrics
    cat >> "$log_file" <<-EOF
		
		=== Binlog Metrics ===
		Binlog Growth:           $binlog_growth bytes ($binlog_growth_mb MB)
	EOF
    
    # Add latency metrics if available
    if [[ -n "$latency_baseline" ]]; then
        cat >> "$log_file" <<-EOF
			
			=== Query Latency ===
		EOF
        
        read -r select_avg select_p95 update_avg update_p95 <<< "$latency_baseline"
        
        echo "SELECT latency (baseline):      ${select_avg} ms avg, ${select_p95} ms p95" >> "$log_file"
        echo "UPDATE latency (baseline):      ${update_avg} ms avg, ${update_p95} ms p95" >> "$log_file"
        
        if [[ -n "$latency_recovery" ]]; then
            read -r select_avg_rec select_p95_rec update_avg_rec update_p95_rec <<< "$latency_recovery"
            echo "SELECT latency (after):         ${select_avg_rec} ms avg, ${select_p95_rec} ms p95" >> "$log_file"
            echo "UPDATE latency (after):         ${update_avg_rec} ms avg, ${update_p95_rec} ms p95" >> "$log_file"
        fi
    fi
    
    log "Metrics written to $log_file"
}

#############################################################################
# Batch Metrics Analysis
#############################################################################

analyze_batch_metrics() {
    local batch_log=$1
    
    if [[ ! -f "$batch_log" ]]; then
        log "WARNING: Batch log not found: $batch_log"
        return 1
    fi
    
    log ""
    log "=== Batch Metrics Analysis ==="
    
    # Calculate statistics using awk
    awk -F',' 'NR>1 {
        total_rows += $3
        total_duration += $4
        sum_throughput += $5
        if (NR == 2) { first_throughput = $5 }
        last_throughput = $5
        max_lag = ($6 > max_lag) ? $6 : max_lag
        min_throughput = (min_throughput == 0 || $5 < min_throughput) ? $5 : min_throughput
        max_throughput = ($5 > max_throughput) ? $5 : max_throughput
        count++
    }
    END {
        if (count == 0) {
            print "No batch data found (no rows were deleted)"
        } else {
            printf "Total Batches: %d\n", count
            printf "Total Rows Deleted: %d\n", total_rows
            printf "Total Duration: %.2f seconds\n", total_duration
            printf "Average Throughput: %.2f rows/sec\n", sum_throughput / count
            printf "Min Throughput: %.2f rows/sec\n", min_throughput
            printf "Max Throughput: %.2f rows/sec\n", max_throughput
            if (max_throughput > 0) {
                printf "Throughput Degradation: %.1f%%\n", ((max_throughput - min_throughput) / max_throughput) * 100
            }
            printf "Max Replication Lag: %s seconds\n", max_lag
        }
    }' "$batch_log"
    
    log "==========================="
}
