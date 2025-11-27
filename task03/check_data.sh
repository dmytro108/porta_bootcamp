#!/bin/bash

MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
CLEANUP_USER="${CLEANUP_USER:-root}"
CLEANUP_PASSW="${CLEANUP_PASSW:-${MYSQL_ROOT_PASSWORD:-}}"

echo "=== Checking cleanup_batch table data distribution ==="
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" cleanup_bench << 'SQL'
SELECT 
    'Total rows' as metric,
    COUNT(*) as value
FROM cleanup_batch
UNION ALL
SELECT 
    'Rows older than 10 days',
    COUNT(*)
FROM cleanup_batch
WHERE ts < NOW() - INTERVAL 10 DAY
UNION ALL
SELECT 
    'Rows 0-5 days old',
    COUNT(*)
FROM cleanup_batch
WHERE ts >= NOW() - INTERVAL 5 DAY
UNION ALL
SELECT 
    'Oldest record',
    TIMESTAMPDIFF(DAY, MIN(ts), NOW())
FROM cleanup_batch
UNION ALL
SELECT 
    'Newest record',
    TIMESTAMPDIFF(SECOND, MAX(ts), NOW())
FROM cleanup_batch;
SQL

