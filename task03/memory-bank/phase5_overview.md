# Phase 5 Overview: Cleanup Methods Implementation

**Status**: Ready for Implementation  
**Dependencies**: Phase 1 ✅, Phase 2 ✅, Phase 3 ✅, Phase 4 ✅  
**Target Completion**: November 21-22, 2025  

---

## What is Phase 5?

Phase 5 is the **core implementation phase** of the MySQL cleanup benchmark project. This phase implements the four cleanup methods that will be compared to determine the fastest and most efficient way to remove old data from large MySQL tables.

## The Four Methods

### 1. DROP PARTITION - The Speed Champion 🏆

**How it works**: Drops entire partitions containing old data in a single DDL operation.

**SQL**: `ALTER TABLE cleanup_partitioned DROP PARTITION p20251101, p20251102;`

**Key Characteristics**:
- ⚡ Fastest (millions of rows/sec)
- 📊 Minimal replication lag (<1 second)
- 💾 Full space recovery
- 🧹 Zero fragmentation
- ✅ Best method when partitioning available

**Limitation**: Requires partitioned table

---

### 2. TRUNCATE TABLE - The Quick Reset ⚡

⚠️ **DOES NOT MEET REQUIREMENT**: Removes **ALL** data, not just records older than 10 days

**How it works**: Truncates entire table, recreating it empty.

**SQL**: `TRUNCATE TABLE cleanup_truncate;`

**Key Characteristics**:
- ⚡ Very fast (hundreds of thousands rows/sec)
- 📊 Minimal replication lag (<2 seconds)
- 💾 Full space recovery
- 🧹 Zero fragmentation
- ❌ **Removes ALL data** (not selective - does NOT keep recent 10 days)
- ❌ **Not suitable for production cleanup with retention policy**

**Use Case**: Batch processing, temporary tables, staging tables where ALL data can be removed

**Warning**: This method does NOT meet the project requirement of "remove old data, keep recent 10 days". It's included for performance comparison only.

---

### 3. Copy-to-New-Table - The Defragmenter 🔄

**How it works**: Creates new table, copies recent data, swaps tables, drops old.

**SQL**: Four-step process
```sql
CREATE TABLE cleanup_copy_new LIKE cleanup_copy;
INSERT INTO cleanup_copy_new SELECT * WHERE ts >= retention_date;
RENAME TABLE cleanup_copy TO cleanup_copy_old, cleanup_copy_new TO cleanup_copy;
DROP TABLE cleanup_copy_old;
```

**Key Characteristics**:
- 🐢 Moderate speed (thousands rows/sec)
- 📊 High replication lag (10-60 seconds)
- 💾 Full space recovery
- 🧹 Zero fragmentation
- ⚠️ Brief table lock during RENAME
- ⚠️ Loses concurrent writes

**Use Case**: Scheduled maintenance, fragmentation problems, non-partitioned tables

**Warning**: Data written during execution is LOST

---

### 4. Batch DELETE - The 24/7 Option 🔁

**How it works**: Deletes data in small batches (e.g., 5000 rows) in a loop.

**SQL**: Repeated until no rows match
```sql
DELETE FROM cleanup_batch 
WHERE ts < retention_date 
ORDER BY ts 
LIMIT 5000;
```

**Key Characteristics**:
- 🐌 Slowest (hundreds to low thousands rows/sec)
- 📊 Medium-high replication lag (5-60 seconds)
- 💾 **No space freed** (requires OPTIMIZE TABLE)
- 🧹 High fragmentation (20-50%)
- ✅ Table stays online
- 📉 Performance degrades over time

**Use Case**: Must keep table online 24/7, cannot use partitioning

**Post-Cleanup**: Run `OPTIMIZE TABLE` to reclaim space

---

## What Phase 5 Delivers

### 1. Implementations
- `execute_truncate_cleanup()` - TRUNCATE implementation
- `execute_partition_drop_cleanup()` - DROP PARTITION implementation
- `execute_copy_cleanup()` - Copy-to-new-table implementation
- `execute_batch_delete_cleanup()` - Batch DELETE implementation

### 2. Metrics Integration
Each method wrapped with Phase 4 metrics framework:
- Before/after snapshots
- Duration tracking
- Throughput calculation
- Replication lag monitoring
- Space usage tracking
- Comprehensive logging

### 3. CLI Interface
```bash
# Run individual methods
./run-in-container.sh db-cleanup.sh --method truncate
./run-in-container.sh db-cleanup.sh --method partition_drop
./run-in-container.sh db-cleanup.sh --method copy
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 5000

# Run all methods for comparison
./run-in-container.sh db-cleanup.sh --method all

# Preview without executing
./run-in-container.sh db-cleanup.sh --method partition_drop --dry-run
```

### 4. Comprehensive Testing
- Individual method tests
- Concurrent load tests (with db-traffic.sh)
- Parameter tuning tests (batch sizes)
- Integration tests (all methods)
- Performance benchmarks

### 5. Complete Documentation
- Method descriptions and characteristics
- Usage examples
- Results interpretation guide
- Method selection decision tree
- Best practices and warnings

---

## Why This Matters

### Real-World Problem
Production databases accumulate data over time. Old data must be removed to:
- Control storage costs
- Maintain query performance
- Comply with data retention policies

### The Challenge
Deleting millions of rows is **not trivial**:
- Can lock tables (blocking application)
- Can cause replication lag (stale replicas)
- Can fragment tables (wasting space)
- Can consume binlog space
- Can impact query performance

### The Solution
**Measure and compare** different cleanup approaches to find the best method for specific scenarios.

---

## Expected Performance Profile

Based on design and similar benchmarks:

| Method         | Throughput  | Duration (100K rows) | Repl Lag | Space Freed | Fragmentation |
| -------------- | ----------- | -------------------- | -------- | ----------- | ------------- |
| DROP PARTITION | 1M - 5M     | <1 second            | <1 sec   | 100%        | 0%            |
| TRUNCATE       | 100K - 500K | 1-2 seconds          | <2 sec   | 100%        | 0%            |
| Copy           | 2K - 10K    | 10-50 seconds        | 10-60s   | 100%        | 0%            |
| Batch DELETE   | 500 - 5K    | 20-200 seconds       | 5-60s    | 0%          | 20-50%        |

*Throughput in rows/second*

---

## Method Selection Guide

### Decision Tree

```
Need to cleanup old data (keep recent 10 days)?
│
├─ Is table partitioned by date?
│  ├─ YES → Use DROP PARTITION ⭐ (best option - selective cleanup)
│  └─ NO → Continue
│
├─ Can you delete ALL data (no retention needed)?
│  ├─ YES → Use TRUNCATE (fast but removes everything - NOT selective)
│  └─ NO → Continue (need selective cleanup)
│
├─ Can table be offline briefly (<1 min)?
│  ├─ YES → Use Copy-to-New-Table
│  └─ NO → Use Batch DELETE (last resort)
```

### Quick Recommendations

**Use DROP PARTITION if**:
- ✅ Table is partitioned by date/time
- ✅ Production environment
- ✅ Speed is critical
- ✅ Regular cleanup schedule

**Use TRUNCATE if**:
- ✅ Entire table can be cleared
- ✅ Temporary/staging tables
- ✅ Batch processing workflows

**Use Copy-to-New-Table if**:
- ✅ Table not partitioned
- ✅ Scheduled maintenance windows
- ✅ Fragmentation is a problem
- ✅ Brief downtime acceptable

**Use Batch DELETE if**:
- ✅ Table must stay online 24/7
- ✅ Cannot use partitioning
- ✅ Performance degradation acceptable
- ⚠️ Remember to run OPTIMIZE TABLE after

---

## Implementation Approach

### Incremental Development
1. Implement one method at a time
2. Test thoroughly before moving to next
3. Integrate with metrics framework
4. Validate results

### Testing Strategy
- Unit test each method independently
- Integration test with concurrent load
- Performance benchmark with different data sizes
- Compare results objectively

### Quality Gates
Each method must:
- Execute successfully without errors
- Delete correct number of rows
- Generate complete metrics log
- Handle concurrent load gracefully
- Meet expected performance characteristics

---

## Success Criteria

Phase 5 is complete when:

✅ All four cleanup methods implemented  
✅ Metrics integration working for all methods  
✅ CLI interface complete (--method, --batch-size, etc.)  
✅ Dry-run mode working  
✅ All methods tested individually  
✅ All methods tested with concurrent load  
✅ Performance benchmarks collected  
✅ Documentation complete (README, usage, interpretation)  
✅ Results logged to task03/results/  
✅ Ready for Phase 6 (orchestration and comparison)  

---

## Dependencies

### Phase 4 Prerequisites (All Complete ✅)
- Metrics collection framework (`capture_metrics_snapshot`, `log_metrics`)
- Helper functions (`get_timestamp`, `get_row_count`, `get_table_info`)
- Replication lag monitoring
- InnoDB metrics tracking
- Results directory structure

### Phase 1-3 Prerequisites (All Complete ✅)
- Database schema with four test tables
- Partition maintenance for `cleanup_partitioned`
- Data loading script (`db-load.sh`)
- Load simulation script (`db-traffic.sh`)
- Container execution wrapper (`run-in-container.sh`)

---

## What Happens After Phase 5?

### Phase 6: Orchestration & Automation
- Enhanced orchestration in `db-cleanup.sh`
- Summary report generation across all methods
- Comparison tables and charts
- Automated result analysis
- Cron integration for scheduled cleanup

### Phase 7: Final Documentation
- Complete project README
- How to run experiments guide
- Results interpretation documentation
- Best practices and recommendations
- Troubleshooting guide

---

## Key Insights

### What We'll Learn

**Performance Characteristics**:
- Actual throughput for each method
- Replication lag impact
- Space recovery efficiency
- Fragmentation effects

**Trade-offs**:
- Speed vs. application impact
- Space recovery vs. complexity
- Simplicity vs. flexibility

**Real-World Applicability**:
- When to use each method
- Production considerations
- Method limitations

### Impact

This benchmark will provide **objective data** to:
- Choose the right cleanup method for production
- Optimize cleanup procedures
- Avoid common pitfalls
- Minimize impact on application and replication

---

## Timeline

| Day   | Stages     | Hours     | Deliverables                      |
| ----- | ---------- | --------- | --------------------------------- |
| Day 1 | Stages 1-2 | 4-6       | TRUNCATE + DROP PARTITION methods |
| Day 2 | Stages 3-4 | 4-6       | Copy + Batch DELETE methods       |
| Day 3 | Stages 5-7 | 3-4       | CLI, Testing, Documentation       |
|       | **Total**  | **12-16** | **All four methods complete**     |

---

## Related Documents

📄 **Detailed Plan**: `phase5_implementation_plan.md` - Comprehensive implementation guide  
📋 **Task Checklist**: `phase5_tasks.md` - Step-by-step checklist  
📊 **Cleanup Methods Spec**: `implementation_cleanup_methods.md` - Original requirements  
📈 **Phase 4 Summary**: `phase4_implementation_summary.md` - Metrics framework  
📖 **Project README**: `README.md` - Overall project context  

---

**Document Status**: Complete  
**Last Updated**: November 20, 2025  
**Ready for**: Implementation  

---

## Quick Start

Ready to begin? Here's your first step:

```bash
cd task03
./run-in-container.sh db-load.sh --rows 10000
# Now open phase5_implementation_plan.md and start Stage 1!
```

Good luck! 🚀
