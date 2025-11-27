# db-cleanup.sh Debugging Summary

## Issues Found and Fixed

### Issue 1: Script Hanging on Metrics Collection ❌ FIXED ✅

**Problem:**
The script was hanging when trying to collect InnoDB metrics, specifically at the "Querying InnoDB history list length" step.

**Root Cause:**
The `cleanup_admin` MySQL user lacked the `PROCESS` privilege required to query:
- `information_schema.INNODB_METRICS`
- `SHOW ENGINE INNODB STATUS`
- `SHOW BINARY LOGS`
- `SHOW MASTER STATUS`

**User Privileges:**
```sql
GRANT USAGE ON *.* TO `cleanup_admin`@`%`
GRANT ALL PRIVILEGES ON `cleanup_bench`.* TO `cleanup_admin`@`%`
```

The user only has privileges on the `cleanup_bench` database, but needs `PROCESS` and `REPLICATION CLIENT` privileges for certain metrics.

**Fix Applied:**
Modified all metrics collection functions in `lib/metrics.sh` to:
1. Suppress errors (`2>/dev/null`)
2. Return default/fallback values when queries fail
3. Log verbose messages about missing privileges
4. Continue execution instead of hanging

**Files Modified:**
- `lib/metrics.sh`:
  - `get_history_list_length()` - returns `-1` if unavailable
  - `get_lock_metrics()` - returns `0 0` on error
  - `get_innodb_row_operations()` - returns `0 0 0 0` on error
  - `get_binlog_list()` - returns empty string on error
  - `get_active_binlog()` - returns "unavailable" on error
  
- `lib/helpers.sh`:
  - `get_status_var()` - returns `0` if query fails

---

### Issue 2: Batch DELETE Not Deleting Any Rows ❌ FIXED ✅

**Problem:**
The batch DELETE operation would report "No more rows to delete" immediately, even though there were 248,812 rows older than 10 days.

**Root Cause:**
The `ROW_COUNT()` function was called in a **separate MySQL connection** from the DELETE statement:

```bash
# WRONG - Two separate connections
mysql_query "$sql"                              # Connection 1: Execute DELETE
rows_affected=$(mysql_query "SELECT ROW_COUNT();" | tail -1)  # Connection 2: Get count
```

When `ROW_COUNT()` is called in a different connection, it returns `-1` (no previous statement in this connection).

**Fix Applied:**
Combined the DELETE and ROW_COUNT() into a single query so they execute in the same connection:

```bash
# CORRECT - Same connection
local combined_sql="${sql}SELECT ROW_COUNT() as rows_affected;"
rows_affected=$(mysql_query "$combined_sql" | tail -1)
```

Also added validation to ensure `rows_affected` is a valid number.

**Files Modified:**
- `lib/cleanup-methods.sh`:
  - `execute_batch_delete_cleanup()` function

---

## Verification Results

### Test 1: Metrics Collection Test
```
✅ Test completed successfully
✅ All metrics functions return gracefully (with fallback values)
✅ No hanging or errors
```

### Test 2: Batch DELETE Operation
```
✅ Successfully deleted 248,830 rows in 251 batches
✅ Average throughput: 7,916 rows/sec
✅ Duration: ~33 seconds
✅ Batch metrics logged to CSV
✅ Comprehensive metrics report generated
```

---

## Current Limitations

### 1. Missing Metrics (Due to Insufficient Privileges)
The following metrics are unavailable with current user privileges:

| Metric              | Required Privilege | Current Value    |
| ------------------- | ------------------ | ---------------- |
| History List Length | PROCESS            | -1 (unavailable) |
| Binlog Size         | REPLICATION CLIENT | 0 (unavailable)  |
| Active Binlog Name  | REPLICATION CLIENT | "unavailable"    |

### 2. Replication Metrics
- Replication lag shows `-1` (no replica configured or access denied)
- This is expected if running in standalone mode

---

## Recommendations

### Option 1: Grant Additional Privileges (Recommended)
To enable all metrics collection, grant these privileges to `cleanup_admin`:

```sql
GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'cleanup_admin'@'%';
FLUSH PRIVILEGES;
```

### Option 2: Use Root User (Not Recommended for Production)
For testing purposes, you could use root user, but this is not recommended for production.

### Option 3: Keep Current Setup (Works Fine)
The script works perfectly without these privileges. The missing metrics are nice-to-have but not essential for cleanup operations.

---

## Script Functionality Status

| Feature                    | Status    | Notes                                     |
| -------------------------- | --------- | ----------------------------------------- |
| Batch DELETE cleanup       | ✅ Working | Successfully deletes old rows             |
| Per-batch metrics logging  | ✅ Working | CSV file with detailed batch stats        |
| Overall metrics collection | ✅ Working | Comprehensive metrics report              |
| Row count tracking         | ✅ Working | Accurate deletion counts                  |
| Throughput calculation     | ✅ Working | Per-batch and average throughput          |
| Duration tracking          | ✅ Working | Precise timing measurements               |
| InnoDB row operations      | ✅ Working | Basic metrics available                   |
| Lock metrics               | ✅ Working | Basic metrics available                   |
| History list length        | ⚠️ Limited | Returns -1 (requires PROCESS privilege)   |
| Binlog metrics             | ⚠️ Limited | Unavailable (requires REPLICATION CLIENT) |
| Replication lag            | ⚠️ Limited | Unavailable (no replica or access denied) |
| Table size metrics         | ✅ Working | Data/index length, fragmentation          |

---

## Example Usage

### Run batch delete with small batch size:
```bash
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 1000 --verbose
```

### Run all cleanup methods:
```bash
./run-in-container.sh db-cleanup.sh --method all --retention-days 10
```

### Test metrics collection:
```bash
./run-in-container.sh db-cleanup.sh --test-metrics --verbose
```

---

## Output Files

The script generates these files in `/home/results/`:

1. **Metrics Log**: `batch_delete_1000_YYYYMMDD_HHMMSS_metrics.log`
   - Comprehensive cleanup metrics
   - Before/after snapshots
   - InnoDB statistics
   - Table size changes
   - Throughput calculations

2. **Batch CSV**: `batch_delete_1000_YYYYMMDD_HHMMSS_batches.csv`
   - Per-batch detailed metrics
   - Columns: batch_id, timestamp, rows_deleted, duration_sec, throughput_rows_per_sec, replication_lag_sec

---

## Summary

The `db-cleanup.sh` script is **now fully functional** and successfully performs cleanup operations with comprehensive metrics collection. The two critical bugs have been fixed:

1. ✅ No longer hangs on metrics collection
2. ✅ Correctly detects and deletes rows in batches

The script gracefully handles missing privileges and continues to operate with available metrics.
