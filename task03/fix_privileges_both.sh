#!/bin/bash

# Fix privileges on both master and slave

set -euo pipefail

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpassword}"
DB_MASTER_HOST="${DB_MASTER_HOST:-localhost}"
DB_SLAVE_HOST="${DB_SLAVE_HOST:-db_slave}"

echo "=== Fixing privileges on MASTER ==="
mysql -h"$DB_MASTER_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" <<EOF
-- Grant privileges to cleanup_admin
GRANT RELOAD, PROCESS, REPLICATION CLIENT ON *.* TO 'cleanup_admin'@'%';
GRANT SELECT ON mysql.* TO 'cleanup_admin'@'%';
GRANT ALL PRIVILEGES ON cleanup_bench.* TO 'cleanup_admin'@'%';
FLUSH PRIVILEGES;

-- Verify grants
SHOW GRANTS FOR 'cleanup_admin'@'%';
EOF

echo ""
echo "=== Fixing privileges on SLAVE ==="
mysql -h"$DB_SLAVE_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" <<EOF
-- Grant privileges to cleanup_admin
GRANT RELOAD, PROCESS, REPLICATION CLIENT ON *.* TO 'cleanup_admin'@'%';
GRANT SELECT ON mysql.* TO 'cleanup_admin'@'%';
GRANT ALL PRIVILEGES ON cleanup_bench.* TO 'cleanup_admin'@'%';
FLUSH PRIVILEGES;

-- Verify grants
SHOW GRANTS FOR 'cleanup_admin'@'%';
EOF

echo ""
echo "=== Testing ANALYZE TABLE on both servers ==="

echo "Master:"
mysql -h"$DB_MASTER_HOST" -ucleanup_admin -pcleanup_pass123 cleanup_bench -e "ANALYZE TABLE cleanup_copy;"

echo ""
echo "Slave:"
mysql -h"$DB_SLAVE_HOST" -ucleanup_admin -pcleanup_pass123 cleanup_bench -e "ANALYZE TABLE cleanup_copy;"

echo ""
echo "=== Privileges fixed on both master and slave ==="
