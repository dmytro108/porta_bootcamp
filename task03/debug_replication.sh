#!/bin/bash

CLEANUP_USER="cleanup_admin"
CLEANUP_PASSW="cleanup_pass123"
DB_SLAVE_HOST="${DB_SLAVE_HOST:-db_slave}"

echo "=== Testing SHOW REPLICA STATUS on slave ==="
mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    -e "SHOW REPLICA STATUS\G" 2>&1 | head -20

echo ""
echo "=== Checking if replication is even configured on slave ==="
mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    -e "SELECT * FROM performance_schema.replication_connection_configuration\G" 2>&1 | head -10

