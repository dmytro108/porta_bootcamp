#!/bin/bash

MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
CLEANUP_USER="${CLEANUP_USER:-root}"
CLEANUP_PASSW="${CLEANUP_PASSW:-${MYSQL_ROOT_PASSWORD:-}}"
DB_SLAVE_HOST="${DB_SLAVE_HOST:-db_slave}"

echo "=== Checking Replication Configuration ==="
echo "Master Host: $MYSQL_HOST"
echo "Slave Host: $DB_SLAVE_HOST"
echo "User: $CLEANUP_USER"
echo ""

echo "=== Testing connection to SLAVE ==="
mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    -e "SELECT 'Slave connection successful' as status;" 2>&1

echo -e "\n=== Checking SLAVE STATUS (MySQL 8.0+ syntax) ==="
mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    -e "SHOW REPLICA STATUS\G" 2>&1 | head -30

echo -e "\n=== Checking SLAVE STATUS (MySQL 5.7 syntax) ==="
mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    -e "SHOW SLAVE STATUS\G" 2>&1 | head -30

echo -e "\n=== Checking if replication is configured ==="
mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    -e "SELECT COUNT(*) as replica_configured FROM performance_schema.replication_connection_status;" 2>&1

