# MySQL Cleanup Benchmark - Usage Guide

Complete guide for using the MySQL Cleanup Benchmark project.

## Table of Contents

- [Getting Started](#getting-started)
- [Common Scenarios](#common-scenarios)
- [Detailed Workflows](#detailed-workflows)
- [Command Reference](#command-reference)
- [Examples](#examples)
- [Tips and Best Practices](#tips-and-best-practices)

---

## Getting Started

### Prerequisites

- Docker environment from task01 running
- Access to MySQL database (db_master, db_slave)
- Basic understanding of MySQL

### First-Time Setup

**1. Verify environment**
```bash
# Check if containers are running
docker ps | grep -E '(db_master|db_slave)'
# Expected: db_master and db_slave_1 containers running
```

**2. Initialize database schema**
```bash
cd /home/padavan/repos/porta_bootcamp/task03

# Load schema (only needed once)
./run-in-container.sh bash -c "mysql < /task03/db-schema.sql"
```

**3. Verify tables exist**
```bash
./run-in-container.sh bash -c "mysql -e 'SHOW TABLES FROM cleanup_bench;'"
# Expected: cleanup_batch, cleanup_copy, cleanup_partitioned, cleanup_truncate
```

### Quick Start (5 Minutes)

Run your first cleanup test:

```bash
# 1. Load test data (10,000 rows)
./run-in-container.sh db-load.sh --rows 10000

# 2. Run partition drop cleanup (fastest method)
./run-in-container.sh db-cleanup.sh --method partition_drop

# 3. View results
cat results/partition_drop_*_metrics.log | grep "rows_deleted_per_second"
```

---

## Common Scenarios

### Scenario 1: Compare All Cleanup Methods

**Use Case**: Determine which method is fastest for your dataset

```bash
# 1. Load fresh data (all tables)
./run-in-container.sh db-load.sh --rows 10000

# 2. Run all cleanup methods
./run-in-container.sh db-cleanup.sh --method all

# 3. Compare results
grep "rows_deleted_per_second" results/*_metrics.log
```

**Expected Results**:
- `partition_drop`: 4,000-10,000+ rows/sec
- `truncate`: 50,000+ rows/sec
- `copy`: 1,000-3,000 rows/sec
- `batch_delete`: 500-2,000 rows/sec

### Scenario 2: Test with Concurrent Load

**Use Case**: Simulate real production environment with ongoing queries

```bash
# 1. Load data
./run-in-container.sh db-load.sh --rows 10000

# 2. Start background traffic
./run-in-container.sh db-traffic.sh --rows-per-second 20 &
TRAFFIC_PID=$!

# 3. Run cleanup (in another terminal)
./run-in-container.sh db-cleanup.sh --method batch_delete

# 4. Stop traffic
kill $TRAFFIC_PID
```

**What to Observe**:
- Increased cleanup time
- Higher replication lag
- Impact on query latency

### Scenario 3: Tune Batch DELETE Performance

**Use Case**: Optimize batch delete for your workload

```bash
# Test different batch sizes
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 1000
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 5000
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 10000

# Compare per-batch metrics
cat results/batch_delete_*_batches.csv | tail -20
```

**Find the Sweet Spot**:
- Small batches (1K): Lower impact, slower overall
- Medium batches (5K): Balanced (recommended)
- Large batches (10K+): Faster overall, higher impact

### Scenario 4: Test Custom Retention Period

**Use Case**: Keep 7 days instead of default 10 days

```bash
# Load data with wider date range
./run-in-container.sh db-load.sh --rows 20000

# Test with 7-day retention
./run-in-container.sh db-cleanup.sh --method partition_drop --retention-days 7
./run-in-container.sh db-cleanup.sh --method copy --retention-days 7
./run-in-container.sh db-cleanup.sh --method batch_delete --retention-days 7
```

### Scenario 5: Production-Like Testing

**Use Case**: Test with larger dataset (closer to production scale)

```bash
# 1. Load 100K rows (takes ~30 seconds)
./run-in-container.sh db-load.sh --rows 100000

# 2. Use test framework for consistent testing
./test-cleanup-methods.sh --scenario performance

# 3. Review comprehensive results
cat results/TEST_SUMMARY_*.md
```

---

## Detailed Workflows

### Workflow 1: Complete Benchmark

```bash
# Step 1: Initialize environment
cd /home/padavan/repos/porta_bootcamp/task03
./run-in-container.sh bash -c "mysql < /task03/db-schema.sql"

# Step 2: Generate test data
./run-in-container.sh db-load.sh --rows 100000

# Step 3: Run comprehensive tests
./test-cleanup-methods.sh --scenario all

# Step 4: Analyze results
cat results/TEST_SUMMARY_*.md
find results/test_runs -name "*_metrics.log" -exec grep "rows_deleted_per_second" {} \;

# Step 5: Make decision based on results
# See RESULTS_INTERPRETATION.md
```

### Workflow 2: Quick Validation

```bash
# Quick test to verify everything works

# Step 1: Load small dataset
./run-in-container.sh db-load.sh --rows 1000

# Step 2: Test one method
./run-in-container.sh db-cleanup.sh --method partition_drop

# Step 3: Verify cleanup worked
./run-in-container.sh bash -c "mysql -e '
  SELECT COUNT(*) as remaining_rows,
         MIN(ts) as oldest_date,
         MAX(ts) as newest_date
  FROM cleanup_bench.cleanup_partitioned;'"
# Expected: Fewer rows, oldest_date within last 10 days
```

### Workflow 3: Partition Maintenance

```bash
# Daily partition management (recommended for production)

# Step 1: Check current partitions
./run-in-container.sh bash -c "mysql -e '
  SELECT PARTITION_NAME, PARTITION_DESCRIPTION
  FROM information_schema.PARTITIONS
  WHERE TABLE_NAME = \"cleanup_partitioned\"
  ORDER BY PARTITION_DESCRIPTION;'"

# Step 2: Preview partition maintenance (dry-run)
./run-in-container.sh db-partition-maintenance.sh --dry-run

# Step 3: Execute maintenance
./run-in-container.sh db-partition-maintenance.sh
```

---

## Command Reference

### db-load.sh

**Purpose**: Load test data into all cleanup tables

**Syntax**:
```bash
./run-in-container.sh db-load.sh [options]
```

**Options**:
- `--rows N` - Number of rows to generate (default: 10000)
- `--verbose` - Enable detailed logging
- `--force-regenerate` - Regenerate CSV even if it exists

**Examples**:
```bash
# Load 10K rows (default)
./run-in-container.sh db-load.sh

# Load 100K rows with verbose output
./run-in-container.sh db-load.sh --rows 100000 --verbose

# Force regenerate CSV and load
./run-in-container.sh db-load.sh --rows 50000 --force-regenerate
```

**Data Distribution**:
- Date range: NOW() - 20 days to NOW()
- ~50% old data (> 10 days)
- ~50% recent data (≤ 10 days)

### db-cleanup.sh

**Purpose**: Execute cleanup methods and collect metrics

**Syntax**:
```bash
./run-in-container.sh db-cleanup.sh [options]
```

**Options**:
- `--method METHOD` - Cleanup method: partition_drop, truncate, copy, batch_delete, all
- `--table TABLE` - Target table (optional, uses default per method)
- `--retention-days N` - Days to retain (default: 10)
- `--batch-size N` - Batch size for DELETE (default: 5000)
- `--batch-delay N` - Seconds between batches (default: 0.1)
- `--test-metrics` - Test metrics collection only
- `--verbose` - Detailed logging
- `-h, --help` - Show help

**Examples**:
```bash
# Run all methods
./run-in-container.sh db-cleanup.sh --method all

# Run partition drop with default settings
./run-in-container.sh db-cleanup.sh --method partition_drop

# Run batch delete with custom parameters
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 10000 --batch-delay 0.2

# Run copy method with 7-day retention
./run-in-container.sh db-cleanup.sh --method copy --retention-days 7
```

### db-traffic.sh

**Purpose**: Simulate concurrent database load during cleanup tests

**Syntax**:
```bash
./run-in-container.sh db-traffic.sh [options]
```

**Options**:
- `--rows-per-second N` - Operations per second (default: 10)
- `--duration N` - Duration in seconds (default: unlimited)
- `--workload-mix I:S:U` - INSERT:SELECT:UPDATE ratio (default: 70:20:10)
- `--tables T1,T2` - Target tables (default: all cleanup tables)
- `--verbose` - Detailed logging

**Examples**:
```bash
# Default traffic (10 ops/sec, all tables)
./run-in-container.sh db-traffic.sh &

# High write load for 5 minutes
./run-in-container.sh db-traffic.sh --rows-per-second 50 --duration 300 --workload-mix 90:10:0

# Read-heavy load on specific table
./run-in-container.sh db-traffic.sh --workload-mix 10:80:10 --tables cleanup_batch
```

### test-cleanup-methods.sh

**Purpose**: Execute automated test scenarios with consistent baselines

**Syntax**:
```bash
./test-cleanup-methods.sh [options]
```

**Options**:
- `--scenario NAME` - Test scenario: basic, concurrent, performance, single, all
- `--method NAME` - Method for single scenario
- `--size N` - Dataset size (rows)
- `--concurrent` - Enable background traffic
- `--traffic-rate N` - Traffic operations per second
- `--dry-run` - Preview without execution
- `--verbose` - Detailed logging

**Examples**:
```bash
# Run basic test suite (no concurrent load)
./test-cleanup-methods.sh --scenario basic

# Run with concurrent load
./test-cleanup-methods.sh --scenario concurrent

# Performance benchmark (100K rows)
./test-cleanup-methods.sh --scenario performance

# Test single method
./test-cleanup-methods.sh --scenario single --method partition_drop

# Custom test
./test-cleanup-methods.sh --method copy --size 50000 --concurrent
```

### db-partition-maintenance.sh

**Purpose**: Maintain partitions on cleanup_partitioned table

**Syntax**:
```bash
./run-in-container.sh db-partition-maintenance.sh [options]
```

**Options**:
- `--dry-run` - Preview actions without executing
- `--retention-days N` - Partition retention window (default: 30)

**Examples**:
```bash
# Preview partition maintenance
./run-in-container.sh db-partition-maintenance.sh --dry-run

# Execute partition maintenance
./run-in-container.sh db-partition-maintenance.sh

# Custom retention (keep 60 days of partitions)
./run-in-container.sh db-partition-maintenance.sh --retention-days 60
```

---

## Examples

### Example 1: First-Time User

**Goal**: Get started and run first test in 10 minutes

```bash
# 1. Navigate to task03
cd /home/padavan/repos/porta_bootcamp/task03

# 2. Initialize database (if not done)
./run-in-container.sh bash -c "mysql < /task03/db-schema.sql"

# 3. Load small dataset for quick test
./run-in-container.sh db-load.sh --rows 5000

# 4. Run fastest method
./run-in-container.sh db-cleanup.sh --method partition_drop

# 5. Check results
cat results/partition_drop_*_metrics.log | grep -E "(Duration|Throughput|rows_deleted_per_second)"
```

### Example 2: Performance Comparison

**Goal**: Compare all methods with 50K rows

```bash
# 1. Load data
./run-in-container.sh db-load.sh --rows 50000 --verbose

# 2. Run all methods
./run-in-container.sh db-cleanup.sh --method all

# 3. Extract key metrics
echo "=== Performance Comparison ==="
for method in partition_drop truncate copy batch_delete; do
    log=$(ls -t results/${method}_*_metrics.log 2>/dev/null | head -1)
    if [ -f "$log" ]; then
        throughput=$(grep "rows_deleted_per_second" "$log" | awk '{print $NF}')
        duration=$(grep "^Duration:" "$log" | awk '{print $2}')
        echo "$method: $throughput rows/sec (Duration: $duration)"
    fi
done
```

### Example 3: Automated Testing

**Goal**: Use test framework for consistent results

```bash
# 1. Run basic test suite
./test-cleanup-methods.sh --scenario basic

# 2. Run concurrent load test
./test-cleanup-methods.sh --scenario concurrent --traffic-rate 20

# 3. Run performance benchmark
./test-cleanup-methods.sh --scenario performance

# 4. Review summary
cat results/TEST_SUMMARY_*.md
```

---

## Tips and Best Practices

### Data Loading

**Tip**: Reuse CSV file for consistent datasets
```bash
# Generate once
./run-in-container.sh db-load.sh --rows 10000
# CSV is reused on subsequent runs with same row count
```

**Tip**: Use verbose mode when troubleshooting
```bash
./run-in-container.sh db-load.sh --rows 10000 --verbose
```

### Cleanup Testing

**Best Practice**: Test in order of speed (fastest first)
1. `partition_drop` (fastest, validate it works)
2. `truncate` (fast, but removes all data)
3. `copy` (moderate speed)
4. `batch_delete` (slowest, test last)

**Best Practice**: Always check results
```bash
# After cleanup, verify data
./run-in-container.sh bash -c "mysql -e '
  SELECT COUNT(*) as rows,
         MIN(ts) as oldest,
         MAX(ts) as newest
  FROM cleanup_bench.cleanup_partitioned;'"
```

### Performance Tuning

**Best Practice**: Start with small batch sizes, increase gradually
```bash
# Test progression
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 1000
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 5000
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 10000
```

**Best Practice**: Monitor replication lag during tests
```bash
# In separate terminal
watch -n 1 './run-in-container.sh bash -c "mysql -e \"SHOW REPLICA STATUS\G\"" | grep -E "(Seconds_Behind_Source|Replica_SQL_Running)"'
```

### Results Analysis

**Best Practice**: Keep results organized
```bash
# Results are timestamped automatically
ls -lth results/

# Archive old results
mkdir -p results/archive/$(date +%Y%m)
mv results/*_202511* results/archive/202511/
```

### Common Mistakes to Avoid

❌ **Mistake**: Forgetting to load data
```bash
# This will fail (no data to clean)
./run-in-container.sh db-cleanup.sh --method partition_drop
```

✅ **Solution**: Always load data first
```bash
./run-in-container.sh db-load.sh --rows 10000
./run-in-container.sh db-cleanup.sh --method partition_drop
```

❌ **Mistake**: Using TRUNCATE in production (removes ALL data)

✅ **Solution**: Use selective methods for production
```bash
./run-in-container.sh db-cleanup.sh --method partition_drop
```

❌ **Mistake**: Ignoring fragmentation after batch DELETE

✅ **Solution**: Run OPTIMIZE TABLE after batch delete
```bash
./run-in-container.sh bash -c "mysql -e 'OPTIMIZE TABLE cleanup_bench.cleanup_batch;'"
```

---

## Next Steps

- **For Troubleshooting**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **For Production**: See [PRODUCTION_GUIDE.md](PRODUCTION_GUIDE.md)
- **For Results Analysis**: See [RESULTS_INTERPRETATION.md](RESULTS_INTERPRETATION.md)
- **For Quick Reference**: See main [README.md](README.md)

---

**Last Updated**: November 21, 2025
