#!/bin/bash

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpassword}"
DB_MASTER_HOST="${DB_MASTER_HOST:-localhost}"

echo "=== Current cleanup_admin users in mysql.user table ==="
mysql -h"$DB_MASTER_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT User, Host, 
       Select_priv, Insert_priv, Update_priv, Delete_priv,
       Create_priv, Drop_priv, Reload_priv, Process_priv,
       Repl_client_priv
FROM mysql.user 
WHERE User = 'cleanup_admin'
ORDER BY Host;
"

echo ""
echo "=== Testing connection from current location ==="
if mysql -h"$DB_MASTER_HOST" -ucleanup_admin -pcleanup_pass123 -e "SELECT USER(), CURRENT_USER();" 2>&1; then
    echo "✓ Connection successful"
else
    echo "✗ Connection failed"
fi

echo ""
echo "=== Testing ANALYZE TABLE privilege ==="
if mysql -h"$DB_MASTER_HOST" -ucleanup_admin -pcleanup_pass123 cleanup_bench -e "ANALYZE TABLE cleanup_copy;" 2>&1; then
    echo "✓ ANALYZE TABLE works"
else
    echo "✗ ANALYZE TABLE failed"
fi
