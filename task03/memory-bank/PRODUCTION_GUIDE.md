# MySQL Cleanup Benchmark - Production Deployment Guide

Guide for deploying MySQL cleanup methods to production environments.

## Table of Contents

- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Production Recommendations](#production-recommendations)
- [Cron Integration](#cron-integration)
- [Monitoring Setup](#monitoring-setup)
- [Backup Considerations](#backup-considerations)
- [Security Guidelines](#security-guidelines)
- [Rollback Procedures](#rollback-procedures)
- [Performance Tuning](#performance-tuning)

---

## Pre-Deployment Checklist

### Environment Requirements

- [ ] MySQL 8.0+ installed and running
- [ ] Master-slave replication configured and healthy
- [ ] Sufficient disk space (2x table size for copy method)
- [ ] Backup solution in place
- [ ] Monitoring system configured

### Database Prerequisites

- [ ] Test database schema deployed
- [ ] Partitioning configured (if using partition_drop)
- [ ] Retention policy defined (e.g., 10 days)
- [ ] Partition maintenance scheduled (if using partitioning)

### Testing Requirements

- [ ] All cleanup methods tested in staging
- [ ] Performance benchmarks established
- [ ] Method selected based on requirements
- [ ] Replication lag tested under load
- [ ] Rollback procedure tested

### Backup Requirements

- [ ] Full database backup taken
- [ ] Backup retention policy defined
- [ ] Backup restoration tested
- [ ] Point-in-time recovery configured (binlog)

### Monitoring Requirements

- [ ] Replication lag monitoring
- [ ] Table size monitoring
- [ ] Cleanup job monitoring
- [ ] Alert thresholds defined
- [ ] On-call rotation defined

---

## Production Recommendations

### Method Selection

**Use DROP PARTITION when**:
- ✅ Table is partitioned by date/time
- ✅ Partition boundaries align with retention policy
- ✅ Speed is critical
- ✅ Minimal downtime required
- **Recommended for most production use cases**

**Use BATCH DELETE when**:
- ✅ Table must stay online 24/7
- ✅ Cannot use partitioning
- ✅ Gradual cleanup is acceptable
- ⚠️ Plan for OPTIMIZE TABLE (weekly maintenance)

**Use COPY method when**:
- ✅ Scheduled maintenance windows available
- ✅ Defragmentation is needed
- ✅ Brief downtime is acceptable
- ⚠️ Understand data loss risk during copy

**Avoid TRUNCATE for**:
- ❌ Production tables with retention requirements
- ✅ Only use for temporary/staging tables

### Performance Guidelines

**DROP PARTITION**:
- Expected throughput: 4,000-10,000+ rows/sec
- Replication lag: <1 second
- Downtime: Brief metadata lock only
- Space recovery: Immediate and complete

**BATCH DELETE**:
- Expected throughput: 500-2,000 rows/sec
- Replication lag: 5-60 seconds (tune batch size)
- Downtime: None
- Space recovery: Requires OPTIMIZE TABLE

**COPY**:
- Expected throughput: 1,000-3,000 rows/sec
- Replication lag: 10-60 seconds
- Downtime: Brief lock during RENAME
- Space recovery: Immediate and complete

### Safety Guidelines

1. **Always test in staging first**
2. **Run during low-traffic periods** (e.g., 1-4 AM)
3. **Monitor replication lag** during cleanup
4. **Have rollback plan ready**
5. **Alert on-call team before scheduled cleanup**
6. **Verify backup is recent** (<24 hours)

---

## Cron Integration

### Recommended Schedule

**Daily Partition Maintenance** (required for partition_drop):
```cron
# Add new partitions, drop old partitions
# Daily at 1:00 AM
0 1 * * * /path/to/db-partition-maintenance.sh
```

**Daily Cleanup - DROP PARTITION** (recommended):
```cron
# Clean up old data using partition drop
# Daily at 2:00 AM (after partition maintenance)
0 2 * * * /path/to/db-cleanup.sh --method partition_drop --retention-days 10
```

**Daily Cleanup - BATCH DELETE** (alternative):
```cron
# Clean up old data using batch delete
# Daily at 2:00 AM during low traffic
0 2 * * * /path/to/db-cleanup.sh --method batch_delete --batch-size 5000 --batch-delay 0.1
```

**Weekly Maintenance - COPY** (during maintenance window):
```cron
# Defragment and cleanup using copy method
# Weekly on Sunday at 2:00 AM
0 2 * * 0 /path/to/db-cleanup.sh --method copy --retention-days 10
```

**Weekly OPTIMIZE TABLE** (if using batch_delete):
```cron
# Reclaim space after batch DELETE
# Weekly on Sunday at 3:00 AM
0 3 * * 0 mysql -e 'OPTIMIZE TABLE cleanup_bench.cleanup_batch;'
```

### Cron Best Practices

1. **Redirect output to log files**:
   ```cron
   0 2 * * * /path/to/db-cleanup.sh >> /var/log/mysql-cleanup.log 2>&1
   ```

2. **Use absolute paths**:
   ```cron
   0 2 * * * /usr/local/bin/db-cleanup.sh
   ```

3. **Set up email notifications**:
   ```cron
   MAILTO=dba@example.com
   0 2 * * * /path/to/db-cleanup.sh
   ```

4. **Add locking to prevent concurrent runs**:
   ```bash
   0 2 * * * flock -n /var/lock/cleanup.lock /path/to/db-cleanup.sh
   ```

---

## Monitoring Setup

### Key Metrics to Monitor

**Cleanup Job Metrics**:
- Job completion status (success/failure)
- Duration (alert if >expected)
- Rows deleted
- Throughput (rows/sec)

**Database Metrics**:
- Replication lag (alert if >10 seconds)
- Table sizes (alert if growing unexpectedly)
- Disk space usage
- InnoDB history list length

**Performance Metrics**:
- Query latency during cleanup
- Lock waits and timeouts
- Binlog size growth

### Alert Thresholds

**Critical Alerts**:
- Cleanup job failed
- Replication stopped
- Disk space <10%
- Replication lag >60 seconds

**Warning Alerts**:
- Cleanup duration >2x normal
- Replication lag >10 seconds
- Table size increased unexpectedly
- Fragmentation >30%

### Monitoring Tools

**Prometheus + Grafana**:
```yaml
# Example Prometheus alert
- alert: HighReplicationLag
  expr: mysql_slave_status_seconds_behind_master > 10
  for: 5m
  annotations:
    summary: "High replication lag on {{ $labels.instance }}"
```

**MySQL Enterprise Monitor**:
- Built-in MySQL metrics
- Replication monitoring
- Query analysis

**Custom Monitoring Script**:
```bash
#!/bin/bash
# check-cleanup-job.sh
# Alert if last cleanup was >48 hours ago

last_cleanup=$(find /path/to/results -name "*_metrics.log" -mtime -2 | wc -l)
if [ $last_cleanup -eq 0 ]; then
    echo "CRITICAL: No cleanup job in last 48 hours" | mail -s "Cleanup Alert" dba@example.com
fi
```

---

## Backup Considerations

### Before Cleanup

**Full Backup**:
```bash
# Take full backup before first production cleanup
mysqldump --all-databases --master-data=2 > backup_before_cleanup.sql
```

**Verify Backup**:
```bash
# Test restoration in separate environment
mysql test_db < backup_before_cleanup.sql
```

### During Cleanup

**Binlog-based Point-in-Time Recovery**:
```sql
-- Ensure binlog is enabled
SHOW VARIABLES LIKE 'log_bin';
-- Expected: ON

-- Check binlog retention
SHOW VARIABLES LIKE 'binlog_expire_logs_seconds';
-- Recommended: 604800 (7 days)
```

### Backup Retention

- Full backups: 7 days minimum
- Binlogs: 7 days minimum
- Before major changes: 30 days

---

## Security Guidelines

### Access Control

**Principle of Least Privilege**:
```sql
-- Create dedicated cleanup user
CREATE USER 'cleanup_user'@'localhost' IDENTIFIED BY 'secure_password';

-- Grant only necessary privileges
GRANT SELECT, DELETE, DROP ON cleanup_bench.* TO 'cleanup_user'@'localhost';
GRANT ALTER ON cleanup_bench.cleanup_partitioned TO 'cleanup_user'@'localhost';

FLUSH PRIVILEGES;
```

### Credential Management

**Use MySQL configuration file**:
```bash
# ~/.my.cnf
[client]
user=cleanup_user
password=secure_password
host=localhost
```

**Set restrictive permissions**:
```bash
chmod 600 ~/.my.cnf
```

### Audit Logging

**Enable audit log**:
```sql
-- Install audit plugin (if not installed)
INSTALL PLUGIN audit_log SONAME 'audit_log.so';

-- Configure audit log
SET GLOBAL audit_log_policy = 'LOGINS,QUERIES';
SET GLOBAL audit_log_format = 'JSON';
```

**Log cleanup operations**:
```bash
# In db-cleanup.sh, add logging
echo "$(date) - User: $(whoami) - Method: $METHOD - Status: $STATUS" >> /var/log/cleanup-audit.log
```

---

## Rollback Procedures

### When to Rollback

- Cleanup deleted wrong data
- Unexpected errors during cleanup
- Severe performance degradation
- Replication issues

### Rollback Methods

**For DROP PARTITION** (restore from backup):
```bash
# 1. Identify affected partitions from backup
# 2. Extract data for those partitions
# 3. Reload data

# Example:
mysql cleanup_bench < backup_partition_p20251110.sql
```

**For BATCH DELETE** (restore from binlog):
```bash
# 1. Find binlog position before cleanup
# 2. Extract deleted rows from binlog
# 3. Restore data

# Example (requires binlog2sql tool):
binlog2sql --start-file=mysql-bin.000123 --start-datetime="2025-11-21 02:00:00" \
           --stop-datetime="2025-11-21 02:30:00" \
           --flashback > restore.sql
mysql cleanup_bench < restore.sql
```

**For COPY** (rename old table back):
```bash
# If old table still exists (cleanup_copy_old)
mysql -e "
  DROP TABLE cleanup_bench.cleanup_copy;
  RENAME TABLE cleanup_bench.cleanup_copy_old TO cleanup_bench.cleanup_copy;
"
```

### Rollback Validation

```bash
# After rollback, verify:
# 1. Row count matches expected
# 2. Data distribution is correct
# 3. No duplicate data
# 4. Replication is healthy

mysql -e "
  SELECT COUNT(*) as rows,
         MIN(ts) as oldest,
         MAX(ts) as newest
  FROM cleanup_bench.cleanup_batch;
"
```

---

## Performance Tuning

### Batch DELETE Tuning

**Optimize Batch Size**:
```bash
# Start small, increase gradually
# Test with 1K, 5K, 10K batches

# Monitor metrics:
# - Replication lag
# - Query latency
# - Lock waits

# Find sweet spot:
# - Small batches (1K): Low impact, slower overall
# - Medium batches (5K): Balanced (recommended)
# - Large batches (10K+): Fast, higher impact
```

**Optimize Batch Delay**:
```bash
# Increase delay if:
# - Replication lag is high
# - Query latency increases
# - Lock waits increase

# Recommended delays:
# - Low traffic: 0.05-0.1s
# - Medium traffic: 0.1-0.3s
# - High traffic: 0.3-0.5s
```

### Timing Optimization

**Run During Low Traffic**:
- Analyze traffic patterns
- Identify low-traffic windows
- Schedule cleanup accordingly

**Example traffic analysis**:
```sql
-- Queries per hour over last 7 days
SELECT HOUR(FROM_UNIXTIME(UNIX_TIMESTAMP() - 
       (seq * 3600))) as hour,
       COUNT(*) / 7 as avg_queries_per_hour
FROM mysql.slow_log,
     (SELECT 0 as seq UNION ALL SELECT 1 UNION ALL ... SELECT 23) hours
WHERE start_time > DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY hour
ORDER BY avg_queries_per_hour ASC;
```

### Resource Allocation

**InnoDB Configuration**:
```sql
-- Ensure adequate buffer pool
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
-- Recommended: 70-80% of available RAM

-- Optimize purge lag
SHOW VARIABLES LIKE 'innodb_purge_threads';
-- Recommended: 4 (adjust based on workload)
```

**Replication Configuration**:
```sql
-- Parallel replication (if supported)
SET GLOBAL slave_parallel_workers = 4;
SET GLOBAL slave_parallel_type = 'LOGICAL_CLOCK';
```

---

## Production Checklist

### Pre-Deployment

- [ ] Staging tests completed successfully
- [ ] Performance benchmarks acceptable
- [ ] Backup verified and recent
- [ ] Monitoring alerts configured
- [ ] On-call team notified
- [ ] Rollback procedure documented
- [ ] Cron schedule reviewed

### Deployment

- [ ] Deploy during maintenance window
- [ ] Monitor first execution closely
- [ ] Verify cleanup completed successfully
- [ ] Check replication status
- [ ] Verify expected data deleted
- [ ] Check no unexpected data deleted

### Post-Deployment

- [ ] Review cleanup logs
- [ ] Verify monitoring alerts working
- [ ] Document any issues encountered
- [ ] Update runbooks if needed
- [ ] Schedule follow-up review
- [ ] Archive deployment documentation

---

## Troubleshooting Production Issues

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

**Quick fixes for production**:
- **High replication lag**: Reduce batch size, increase delay
- **Cleanup too slow**: Check fragmentation, run OPTIMIZE TABLE
- **Disk space issues**: Verify cleanup is running, check for large binlogs
- **Replication stopped**: Skip error if safe, restart replication

---

**Last Updated**: November 21, 2025  
**For detailed usage**: See [USAGE_GUIDE.md](USAGE_GUIDE.md)  
**For results analysis**: See [RESULTS_INTERPRETATION.md](RESULTS_INTERPRETATION.md)
