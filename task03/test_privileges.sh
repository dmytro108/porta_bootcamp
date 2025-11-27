#!/bin/bash

# Test if cleanup_admin can access information_schema

MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
CLEANUP_USER="cleanup_admin"
CLEANUP_PASS="cleanup_pass123"

echo "=== Testing information_schema access for cleanup_admin ==="
echo ""

echo "Test 1: Query information_schema.TABLES"
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASS" -e "
SELECT 
    TABLE_NAME,
    TABLE_ROWS,
    ROUND(DATA_LENGTH/1024/1024, 2) AS data_mb,
    ROUND(INDEX_LENGTH/1024/1024, 2) AS index_mb,
    ROUND(DATA_FREE/1024/1024, 2) AS free_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'cleanup_bench'
ORDER BY TABLE_NAME;
"

echo ""
echo "Test 2: Query information_schema.INNODB_METRICS"
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASS" -e "
SELECT NAME, COUNT 
FROM information_schema.INNODB_METRICS 
WHERE NAME = 'trx_rseg_history_len'
LIMIT 1;
"

echo ""
echo "Test 3: Execute SHOW ENGINE INNODB STATUS"
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASS" -e "
SHOW ENGINE INNODB STATUS\\G
" | grep -A2 "TRANSACTIONS"

echo ""
echo "Test 4: Execute SHOW BINARY LOGS"
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASS" -e "
SHOW BINARY LOGS;
"

echo ""
echo "=== All tests completed ==="
