#!/bin/bash

CLEANUP_USER="cleanup_admin"
CLEANUP_PASSW="cleanup_pass123"
MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
DB_SLAVE_HOST="${DB_SLAVE_HOST:-db_slave}"

echo "=== Test 1: InnoDB History List Length (requires PROCESS) ==="
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" cleanup_bench \
    -e "SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'trx_rseg_history_len';" 2>&1 | grep -v "Warning"

echo ""
echo "=== Test 2: SHOW ENGINE INNODB STATUS (requires PROCESS) ==="
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" cleanup_bench \
    -e "SHOW ENGINE INNODB STATUS\G" 2>&1 | grep "History list length" | grep -v "Warning"

echo ""
echo "=== Test 3: Binary Logs (requires REPLICATION CLIENT) ==="
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" cleanup_bench \
    -e "SHOW BINARY LOGS;" 2>&1 | head -5 | grep -v "Warning"

echo ""
echo "=== Test 4: Master Status (requires REPLICATION CLIENT) ==="
mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" cleanup_bench \
    -e "SHOW MASTER STATUS;" 2>&1 | grep -v "Warning"

echo ""
echo "=== Test 5: Replica Status on Slave (requires REPLICATION CLIENT) ==="
mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" cleanup_bench \
    -e "SHOW REPLICA STATUS\G" 2>&1 | grep -E "(Slave_IO_Running|Slave_SQL_Running|Seconds_Behind)" | grep -v "Warning"

