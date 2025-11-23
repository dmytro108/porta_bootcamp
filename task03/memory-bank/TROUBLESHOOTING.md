# MySQL Cleanup Benchmark - Troubleshooting Guide

This guide helps resolve common issues encountered when using the MySQL Cleanup Benchmark project.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Data Loading Problems](#data-loading-problems)
- [Cleanup Failures](#cleanup-failures)
- [Replication Issues](#replication-issues)
- [Performance Problems](#performance-problems)
- [Test Framework Issues](#test-framework-issues)
- [Diagnostic Commands](#diagnostic-commands)

---

## Installation Issues

### Database containers not running

**Symptoms**:
```
Error: Container 'db_master' not found
```

**Diagnosis**:
```bash
docker ps | grep -E '(db_master|db_slave)'
# If nothing shown, containers are not running
```

**Solution**:
```bash
# Start docker environment from task01
cd ../task01
docker-compose up -d

# Verify containers are running
docker ps
# Expected: db_master and db_slave_1 containers
```

### Cannot connect to MySQL

**Symptoms**:
```
ERROR 2002 (HY000): Can't connect to MySQL server
```

**Solutions**:

**1. Wait for MySQL to fully start**:
```bash
sleep 10
docker exec db_master mysqladmin ping
```

**2. Check MySQL credentials**:
```bash
source ../task01/task01.env.sh
echo $MYSQL_ROOT_PASSWORD
```

**3. Restart MySQL container**:
```bash
docker restart db_master
sleep 15
docker exec db_master mysqladmin ping
```

### Schema not loaded

**Symptoms**:
```
ERROR 1146 (42S02): Table 'cleanup_bench.cleanup_partitioned' doesn't exist
```

**Diagnosis**:
```bash
# Check if database and tables exist
./run-in-container.sh bash -c "mysql -e 'SHOW DATABASES LIKE \"cleanup_bench\";'"
./run-in-container.sh bash -c "mysql -e 'SHOW TABLES FROM cleanup_bench;'"
```

**Solution**:
```bash
# Load schema
./run-in-container.sh bash -c "mysql < /task03/db-schema.sql"

# Verify tables created
./run-in-container.sh bash -c "mysql -e 'SHOW TABLES FROM cleanup_bench;'"
```

---

## Data Loading Problems

### No CSV file generated

**Symptoms**:
```
[ERROR] Failed to generate CSV file
```

**Solutions**:

**1. Check disk space**:
```bash
df -h /home/padavan/repos/porta_bootcamp/task03/data
```

**2. Check permissions**:
```bash
chmod 755 task03/data
```

**3. Force regenerate**:
```bash
./run-in-container.sh db-load.sh --rows 10000 --force-regenerate
```

### LOAD DATA LOCAL INFILE not allowed

**Symptoms**:
```
ERROR 3948 (42000): Loading local data is disabled
```

**Solution**:
```bash
# Enable local_infile in MySQL
./run-in-container.sh bash -c "mysql -e 'SET GLOBAL local_infile = ON;'"

# Verify setting
./run-in-container.sh bash -c "mysql -e 'SHOW VARIABLES LIKE \"local_infile\";'"
# Expected: local_infile | ON

# Retry loading
./run-in-container.sh db-load.sh --rows 10000
```

### Partition doesn't exist for data date

**Symptoms**:
```
ERROR 1526 (HY000): Table has no partition for value 738885
```

**Solution**:
```bash
# Add missing partitions
./run-in-container.sh db-partition-maintenance.sh

# Verify partitions cover date range
./run-in-container.sh bash -c "mysql -e '
  SELECT PARTITION_NAME, PARTITION_DESCRIPTION
  FROM information_schema.PARTITIONS
  WHERE TABLE_NAME = \"cleanup_partitioned\"
  ORDER BY PARTITION_DESCRIPTION;'"
```

---

## Cleanup Failures

### No partitions to drop

**Symptoms**:
```
[WARN] No partitions found matching criteria
[INFO] ✓ No partitions to drop
```

**Diagnosis**:
```bash
# Check what partitions exist
./run-in-container.sh bash -c "mysql -e '
  SELECT PARTITION_NAME,
         FROM_DAYS(PARTITION_DESCRIPTION) as partition_date
  FROM information_schema.PARTITIONS
  WHERE TABLE_NAME = \"cleanup_partitioned\"
    AND PARTITION_NAME != \"pFUTURE\"
  ORDER BY PARTITION_DESCRIPTION;'"

# Check data distribution
./run-in-container.sh bash -c "mysql -e '
  SELECT COUNT(*) as total_rows,
         SUM(CASE WHEN ts < NOW() - INTERVAL 10 DAY THEN 1 ELSE 0 END) as old_rows,
         MIN(ts) as oldest,
         MAX(ts) as newest
  FROM cleanup_bench.cleanup_partitioned;'"
```

**Solutions**:

**1. Load data with older dates**:
```bash
./run-in-container.sh db-load.sh --rows 10000
```

**2. Adjust retention days**:
```bash
./run-in-container.sh db-cleanup.sh --method partition_drop --retention-days 5
```

**3. Verify partition maintenance**:
```bash
./run-in-container.sh db-partition-maintenance.sh
```

### Batch DELETE finds no rows

**Symptoms**:
```
[INFO] Batch 1: 0 rows deleted
[INFO] Total rows deleted: 0
```

**Diagnosis**:
```bash
# Check if table has data and deletable rows
./run-in-container.sh bash -c "mysql -e '
  SELECT COUNT(*) as total_rows,
         COUNT(CASE WHEN ts < NOW() - INTERVAL 10 DAY THEN 1 END) as deletable_rows
  FROM cleanup_bench.cleanup_batch;'"
```

**Solutions**:

**1. Load data first**:
```bash
./run-in-container.sh db-load.sh --rows 10000
./run-in-container.sh db-cleanup.sh --method batch_delete
```

**2. Adjust retention days**:
```bash
./run-in-container.sh db-cleanup.sh --method batch_delete --retention-days 5
```

### Copy method loses data

**Explanation**: This is **expected behavior**. The copy method creates a new table and copies recent data. Any data written between the copy and rename steps is permanently lost.

**Solutions**:

**1. Use during maintenance window**:
```bash
# Schedule during low-traffic period
# Example: 2 AM daily via cron
```

**2. Enable read-only mode**:
```bash
# Before cleanup
./run-in-container.sh bash -c "mysql -e 'SET GLOBAL read_only = ON;'"

# Run cleanup
./run-in-container.sh db-cleanup.sh --method copy

# After cleanup
./run-in-container.sh bash -c "mysql -e 'SET GLOBAL read_only = OFF;'"
```

**3. Use different method**:
```bash
# Use partition_drop or batch_delete for 24/7 operation
./run-in-container.sh db-cleanup.sh --method partition_drop
```

---

## Replication Issues

### High replication lag

**Symptoms**:
```
Seconds_Behind_Source: 45
```

**Diagnosis**:
```bash
# Monitor replication lag in real-time
watch -n 1 './run-in-container.sh bash -c "mysql -e \"SHOW REPLICA STATUS\G\"" | grep -E "(Seconds_Behind_Source|Replica_SQL_Running)"'
```

**Solutions**:

**1. Reduce batch size**:
```bash
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 1000
```

**2. Increase batch delay**:
```bash
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-delay 0.5
```

**3. Use partition drop instead**:
```bash
# Partition drop has minimal replication lag
./run-in-container.sh db-cleanup.sh --method partition_drop
```

### Replication stopped

**Symptoms**:
```
Replica_SQL_Running: No
Last_SQL_Error: Error 'Duplicate entry' on query
```

**Solutions**:

**1. Skip error (if safe)**:
```bash
./run-in-container.sh bash -c "mysql -e '
  STOP REPLICA SQL_THREAD;
  SET GLOBAL sql_slave_skip_counter = 1;
  START REPLICA SQL_THREAD;'"
```

**2. Restart replication**:
```bash
./run-in-container.sh bash -c "mysql -e '
  STOP REPLICA;
  START REPLICA;'"
```

---

## Performance Problems

### Cleanup is very slow

**Diagnosis**:
```bash
# Check table stats
./run-in-container.sh bash -c "mysql -e '
  SELECT TABLE_NAME,
         TABLE_ROWS,
         DATA_LENGTH,
         INDEX_LENGTH,
         DATA_FREE,
         ROUND(DATA_FREE/(DATA_LENGTH+INDEX_LENGTH)*100,2) as fragmentation_pct
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = \"cleanup_bench\";'"
```

**Solutions**:

**1. High fragmentation - run OPTIMIZE**:
```bash
# If fragmentation > 20%
./run-in-container.sh bash -c "mysql -e '
  OPTIMIZE TABLE cleanup_bench.cleanup_batch;'"
```

**2. High concurrent load - reduce batch size**:
```bash
./run-in-container.sh db-cleanup.sh --method batch_delete --batch-size 1000 --batch-delay 0.3
```

### Batch DELETE throughput degrades

**Symptoms**: Per-batch throughput decreases over time

**Explanation**: This is **normal behavior** for batch DELETE:
- Early batches: Indexed rows (fast)
- Later batches: Fewer matching rows (slower)
- Fragmentation increases (slower overall)

**Solutions**:

**1. Accept degradation (expected)**:
```bash
# This is normal for batch delete
```

**2. Use different method**:
```bash
# partition_drop has consistent performance
./run-in-container.sh db-cleanup.sh --method partition_drop
```

---

## Test Framework Issues

### Baseline validation fails

**Symptoms**:
```
[ERROR] Baseline validation failed: Row count mismatch
```

**Solution**:
```bash
# Reload test data
./run-in-container.sh db-load.sh --rows 10000 --force-regenerate

# Retry test
./test-cleanup-methods.sh --scenario basic
```

### Seed dataset checksum mismatch

**Symptoms**:
```
[ERROR] MD5 checksum mismatch for data/events_seed_10k_v1.0.csv
```

**Solution**:
```bash
# Regenerate seed datasets
./generate-seeds.sh
```

### Test results directory not created

**Solution**:
```bash
# Create directory structure
mkdir -p task03/results/{test_runs,baselines,comparisons}
chmod 755 task03/results task03/results/*
```

---

## Diagnostic Commands

### Check Database Connectivity

```bash
# Ping MySQL
./run-in-container.sh bash -c "mysqladmin ping"

# Connect to MySQL
./run-in-container.sh bash -c "mysql -e 'SELECT VERSION();'"

# Show databases
./run-in-container.sh bash -c "mysql -e 'SHOW DATABASES;'"
```

### Check Table Status

```bash
# Show all tables
./run-in-container.sh bash -c "mysql -e 'SHOW TABLES FROM cleanup_bench;'"

# Check table sizes and fragmentation
./run-in-container.sh bash -c "mysql -e '
  SELECT TABLE_NAME,
         ROUND(DATA_LENGTH/1024/1024,2) as data_mb,
         ROUND(INDEX_LENGTH/1024/1024,2) as index_mb,
         ROUND(DATA_FREE/1024/1024,2) as free_mb,
         TABLE_ROWS,
         ROUND(DATA_FREE / (DATA_LENGTH + INDEX_LENGTH) * 100, 2) as fragmentation_pct
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = \"cleanup_bench\"
    AND DATA_LENGTH > 0;'"
```

### Check Partition Information

```bash
# List partitions
./run-in-container.sh bash -c "mysql -e '
  SELECT PARTITION_NAME,
         PARTITION_DESCRIPTION,
         TABLE_ROWS,
         DATA_LENGTH
  FROM information_schema.PARTITIONS
  WHERE TABLE_NAME = \"cleanup_partitioned\"
  ORDER BY PARTITION_DESCRIPTION;'"
```

### Check Replication Status

```bash
# Full replication status
./run-in-container.sh bash -c "mysql -e 'SHOW REPLICA STATUS\G'"

# Key replication metrics
./run-in-container.sh bash -c "mysql -e '
  SHOW REPLICA STATUS\G'" | grep -E "(Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Last_Error)"

# Monitor replication lag
watch -n 2 './run-in-container.sh bash -c "mysql -e \"SHOW REPLICA STATUS\G\"" | grep Seconds_Behind_Source'
```

### Check InnoDB Metrics

```bash
# InnoDB row operations
./run-in-container.sh bash -c "mysql -e '
  SHOW GLOBAL STATUS WHERE Variable_name LIKE \"Innodb_rows%\";'"

# InnoDB locking
./run-in-container.sh bash -c "mysql -e '
  SHOW GLOBAL STATUS WHERE Variable_name LIKE \"Innodb%lock%\";'"

# History list length (purge lag indicator)
./run-in-container.sh bash -c "mysql -e 'SHOW ENGINE INNODB STATUS\G'" | grep "History list length"
```

### Check Active Queries

```bash
# Show running queries
./run-in-container.sh bash -c "mysql -e 'SHOW PROCESSLIST;'"

# Show long-running queries (>5 seconds)
./run-in-container.sh bash -c "mysql -e '
  SELECT * FROM information_schema.PROCESSLIST
  WHERE TIME > 5 AND COMMAND != \"Sleep\"
  ORDER BY TIME DESC;'"
```

### Check System Resources

```bash
# Container resource usage
docker stats db_master --no-stream

# Disk usage
docker exec db_master df -h

# Memory usage in MySQL
./run-in-container.sh bash -c "mysql -e '
  SHOW VARIABLES WHERE Variable_name IN (
    \"innodb_buffer_pool_size\",
    \"innodb_log_buffer_size\",
    \"key_buffer_size\",
    \"max_connections\"
  );'"
```

---

## Getting Help

### Before Asking for Help

1. Check this troubleshooting guide
2. Review relevant logs:
   ```bash
   # MySQL error log
   docker logs db_master | tail -100
   
   # Cleanup metrics log
   cat results/*_metrics.log | tail -50
   ```
3. Gather diagnostic information (see commands above)

### When Reporting Issues

Include:
1. **What you were trying to do** (command)
2. **What happened** (error message)
3. **Diagnostic information** (docker ps, MySQL version, table status)
4. **What you've tried** (troubleshooting steps)

---

**Last Updated**: November 21, 2025
