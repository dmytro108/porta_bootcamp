#!/bin/bash

MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
CLEANUP_USER="${CLEANUP_USER:-root}"
CLEANUP_PASSW="${CLEANUP_PASSW:-${MYSQL_ROOT_PASSWORD:-}}"

echo "Testing DELETE query..."

# First check what would be deleted
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" cleanup_bench << 'SQL'
SELECT COUNT(*) as 'Rows that match DELETE condition'
FROM cleanup_batch
WHERE ts < NOW() - INTERVAL 10 DAY;
SQL

# Try actual delete with limit
echo -e "\nExecuting DELETE with LIMIT 10..."
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" cleanup_bench << 'SQL'
DELETE FROM cleanup_batch
WHERE ts < NOW() - INTERVAL 10 DAY
ORDER BY ts
LIMIT 10;

SELECT ROW_COUNT() as 'Rows affected';
SQL

