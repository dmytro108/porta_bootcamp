#!/bin/bash

MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
CLEANUP_USER="${CLEANUP_USER:-root}"
CLEANUP_PASSW="${CLEANUP_PASSW:-${MYSQL_ROOT_PASSWORD:-}}"
DATABASE="cleanup_bench"

# Simulate what the script does
echo "Test 1: DELETE and check ROW_COUNT in same connection"
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    "$DATABASE" --skip-column-names --batch << 'SQL'
DELETE FROM cleanup_batch WHERE ts < NOW() - INTERVAL 10 DAY ORDER BY ts LIMIT 5;
SELECT ROW_COUNT();
SQL

echo -e "\nTest 2: DELETE in one query, ROW_COUNT in separate query (WRONG!)"
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    "$DATABASE" --skip-column-names --batch \
    -e "DELETE FROM cleanup_batch WHERE ts < NOW() - INTERVAL 10 DAY ORDER BY ts LIMIT 5;"

echo "Rows affected from separate query:"
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    "$DATABASE" --skip-column-names --batch \
    -e "SELECT ROW_COUNT();"

