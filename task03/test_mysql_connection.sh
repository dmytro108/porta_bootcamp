#!/bin/bash

# Test MySQL connection and query
MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
CLEANUP_USER="${CLEANUP_USER:-root}"
CLEANUP_PASSW="${CLEANUP_PASSW:-${MYSQL_ROOT_PASSWORD:-}}"

echo "Testing MySQL connection..."
echo "Host: $MYSQL_HOST"
echo "Port: $MYSQL_PORT"
echo "User: $CLEANUP_USER"

# Test basic connection
echo -e "\n1. Testing basic connection:"
mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    -e "SELECT 'Connection successful' as status;" 2>&1

# Test information_schema.INNODB_METRICS
echo -e "\n2. Testing INNODB_METRICS query:"
mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    cleanup_bench --skip-column-names --batch \
    -e "SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'trx_rseg_history_len'" 2>&1

# Test SHOW ENGINE INNODB STATUS
echo -e "\n3. Testing SHOW ENGINE INNODB STATUS:"
mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    cleanup_bench --skip-column-names --batch \
    -e "SHOW ENGINE INNODB STATUS\G" 2>&1 | grep -A2 "History list length"

