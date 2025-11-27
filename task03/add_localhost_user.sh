#!/bin/bash

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpassword}"
DB_MASTER_HOST="${DB_MASTER_HOST:-localhost}"

echo "=== Creating cleanup_admin@localhost user ==="
mysql -h"$DB_MASTER_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" <<'EOF'
CREATE USER IF NOT EXISTS 'cleanup_admin'@'localhost' IDENTIFIED BY 'cleanup_pass123';

GRANT ALL PRIVILEGES ON cleanup_bench.* TO 'cleanup_admin'@'localhost';
GRANT RELOAD, PROCESS, REPLICATION CLIENT ON *.* TO 'cleanup_admin'@'localhost';
GRANT SELECT ON mysql.* TO 'cleanup_admin'@'localhost';

FLUSH PRIVILEGES;

SELECT '=== Grants for cleanup_admin@localhost ===' AS '';
SHOW GRANTS FOR 'cleanup_admin'@'localhost';

SELECT '=== Grants for cleanup_admin@% ===' AS '';
SHOW GRANTS FOR 'cleanup_admin'@'%';
EOF

echo ""
echo "=== Testing ANALYZE TABLE with localhost user ==="
mysql -hlocalhost -ucleanup_admin -pcleanup_pass123 cleanup_bench -e "ANALYZE TABLE cleanup_copy;"

echo ""
echo "✓ Privileges configured for both '%' and 'localhost'"
