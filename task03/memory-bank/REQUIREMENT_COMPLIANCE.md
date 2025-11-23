# Cleanup Methods - Requirement Compliance Analysis

**Project Requirement**: Remove records older than 10 days while keeping records from the last 10 days.

---

## Compliance Summary

| Method             | Meets Requirement? | Reason                                 |
| ------------------ | ------------------ | -------------------------------------- |
| **DROP PARTITION** | ✅ **YES**          | Selectively drops old partitions only  |
| **TRUNCATE TABLE** | ❌ **NO**           | Removes ALL data (no retention)        |
| **Copy-to-New**    | ✅ **YES**          | Copies only recent data (last 10 days) |
| **Batch DELETE**   | ✅ **YES**          | Deletes only rows older than 10 days   |

---

## Method Details

### 1. DROP PARTITION ✅ COMPLIANT

**SQL Pattern**:
```sql
-- Identifies and drops partitions older than 10 days
ALTER TABLE cleanup_partitioned 
DROP PARTITION p20251101, p20251102, p20251103;
```

**How it meets requirement**:
- Identifies partitions where data is > 10 days old
- Drops only those partitions
- Keeps all partitions with recent data (≤ 10 days)
- **Result**: Old data removed, recent data retained

**Compliance**: ✅ **FULLY COMPLIANT**

---

### 2. TRUNCATE TABLE ❌ NOT COMPLIANT

**SQL Pattern**:
```sql
-- Removes ALL data from table
TRUNCATE TABLE cleanup_truncate;
```

**Why it does NOT meet requirement**:
- ❌ Removes **ALL** data from table (both old and recent)
- ❌ Does NOT selectively keep recent 10 days
- ❌ No WHERE clause - cannot filter by date
- ❌ DDL operation - affects entire table

**Result**: ALL data removed (including recent data that should be kept)

**Compliance**: ❌ **NOT COMPLIANT**

**Why included in project**:
- Listed in original task as a method to explore
- Useful for performance comparison
- Shows fastest possible cleanup (but not selective)
- Valid for use cases where entire table can be cleared (e.g., temporary/staging tables)

**Important Note**: This method should ONLY be used when:
- The entire table can and should be cleared
- No data retention is needed
- Temporary or staging tables in batch processing
- NOT for production tables with retention policies

---

### 3. Copy-to-New-Table ✅ COMPLIANT

**SQL Pattern**:
```sql
-- Step 1: Create new table
CREATE TABLE cleanup_copy_new LIKE cleanup_copy;

-- Step 2: Copy ONLY recent data (last 10 days)
INSERT INTO cleanup_copy_new
SELECT * FROM cleanup_copy
WHERE ts >= NOW() - INTERVAL 10 DAY;  -- Keeps recent 10 days

-- Step 3: Atomic swap
RENAME TABLE 
    cleanup_copy TO cleanup_copy_old,
    cleanup_copy_new TO cleanup_copy;

-- Step 4: Drop old table (with old data)
DROP TABLE cleanup_copy_old;
```

**How it meets requirement**:
- Creates new table with same structure
- Copies ONLY rows where `ts >= NOW() - INTERVAL 10 DAY`
- Old data (> 10 days) is NOT copied
- Swaps tables atomically
- **Result**: Old data removed, recent data retained

**Compliance**: ✅ **FULLY COMPLIANT**

---

### 4. Batch DELETE ✅ COMPLIANT

**SQL Pattern**:
```sql
-- Executed repeatedly until no rows match
DELETE FROM cleanup_batch
WHERE ts < NOW() - INTERVAL 10 DAY  -- Deletes ONLY old data
ORDER BY ts
LIMIT 5000;
```

**How it meets requirement**:
- WHERE clause: `ts < NOW() - INTERVAL 10 DAY`
- Deletes ONLY rows older than 10 days
- Rows with `ts >= NOW() - INTERVAL 10 DAY` are NOT deleted
- Loops until all old data removed
- **Result**: Old data removed, recent data retained

**Compliance**: ✅ **FULLY COMPLIANT**

---

## Test Verification Plan

To ensure each method meets (or doesn't meet) the requirement:

### Test Setup
1. Load data spanning 20 days (NOW() - 20 days to NOW())
2. Expected distribution: ~50% old (> 10 days), ~50% recent (≤ 10 days)

### Verification Steps

**For DROP PARTITION**:
```sql
-- Before: Count total rows
SELECT COUNT(*) FROM cleanup_partitioned;  -- e.g., 10000

-- After cleanup:
SELECT COUNT(*) FROM cleanup_partitioned;  -- e.g., ~5000

-- Verify only recent data remains:
SELECT MIN(ts), MAX(ts) FROM cleanup_partitioned;
-- MIN should be ≥ NOW() - INTERVAL 10 DAY
-- MAX should be ≈ NOW()

-- ✅ Expected: ~50% of rows remain (recent data)
```

**For TRUNCATE**:
```sql
-- Before: Count total rows
SELECT COUNT(*) FROM cleanup_truncate;  -- e.g., 10000

-- After cleanup:
SELECT COUNT(*) FROM cleanup_truncate;  -- Should be 0

-- ❌ Expected: 0 rows (ALL data removed - does NOT meet requirement)
```

**For Copy-to-New-Table**:
```sql
-- Before: Count total rows
SELECT COUNT(*) FROM cleanup_copy;  -- e.g., 10000

-- After cleanup:
SELECT COUNT(*) FROM cleanup_copy;  -- e.g., ~5000

-- Verify only recent data remains:
SELECT MIN(ts), MAX(ts) FROM cleanup_copy;
-- MIN should be ≥ NOW() - INTERVAL 10 DAY
-- MAX should be ≈ NOW()

-- ✅ Expected: ~50% of rows remain (recent data)
```

**For Batch DELETE**:
```sql
-- Before: Count total rows
SELECT COUNT(*) FROM cleanup_batch;  -- e.g., 10000

-- After cleanup:
SELECT COUNT(*) FROM cleanup_batch;  -- e.g., ~5000

-- Verify only recent data remains:
SELECT MIN(ts), MAX(ts) FROM cleanup_batch;
-- MIN should be ≥ NOW() - INTERVAL 10 DAY
-- MAX should be ≈ NOW()

-- ✅ Expected: ~50% of rows remain (recent data)
```

---

## Documentation Requirements

Each method's documentation MUST clearly state:

### For Compliant Methods (DROP PARTITION, Copy, Batch DELETE):
- ✅ "Removes records older than 10 days"
- ✅ "Keeps records from the last 10 days"
- ✅ "Meets project requirement for selective cleanup"

### For Non-Compliant Method (TRUNCATE):
- ⚠️ "**WARNING: Removes ALL data**"
- ⚠️ "**Does NOT keep recent 10 days**"
- ⚠️ "**Does NOT meet project requirement for selective cleanup**"
- ⚠️ "**Only use when entire table can be cleared**"
- ℹ️ "Included for performance comparison only"
- ℹ️ "Valid for temporary/staging tables, NOT production with retention"

---

## Summary

**3 out of 4 methods meet the requirement**:
- ✅ DROP PARTITION - Fastest compliant method
- ❌ TRUNCATE TABLE - Fast but NOT compliant (removes all data)
- ✅ Copy-to-New-Table - Compliant with defragmentation benefit
- ✅ Batch DELETE - Compliant with minimal application impact

**Best method**: DROP PARTITION (when partitioning available)  
**Fallback**: Copy-to-New-Table or Batch DELETE (depending on downtime tolerance)  
**Never use for selective cleanup**: TRUNCATE TABLE

---

**Document Purpose**: Ensure clear understanding of which methods meet the "remove old, keep recent" requirement

**Last Updated**: November 21, 2025
