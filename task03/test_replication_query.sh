#!/bin/bash

DB_SLAVE_HOST="${DB_SLAVE_HOST:-db_slave}"
CLEANUP_USER="${CLEANUP_USER:-root}"
CLEANUP_PASSW="${CLEANUP_PASSW:-${MYSQL_ROOT_PASSWORD:-}}"

echo "=== Simulating get_replication_lag function ==="
echo "Querying: $DB_SLAVE_HOST"
echo ""

# Test the exact query the script uses
echo "Test 1: SHOW REPLICA STATUS (MySQL 8.0+)"
result=$(mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    cleanup_bench --skip-column-names --batch \
    -e "SHOW REPLICA STATUS\G" 2>/dev/null | \
    grep "Seconds_Behind_Source:" | awk '{print $2}')

echo "Result: '$result'"
if [[ -z "$result" ]]; then
    echo "Empty result"
fi

echo ""
echo "Test 2: SHOW SLAVE STATUS (MySQL 5.7)"
result2=$(mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    cleanup_bench --skip-column-names --batch \
    -e "SHOW SLAVE STATUS\G" 2>/dev/null | \
    grep "Seconds_Behind_Master:" | awk '{print $2}')

echo "Result: '$result2'"
if [[ -z "$result2" ]]; then
    echo "Empty result"
fi

echo ""
echo "Test 3: Check stderr output"
mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    cleanup_bench --skip-column-names --batch \
    -e "SHOW REPLICA STATUS\G" 2>&1 | head -5

