#!/bin/bash

MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpass}"

echo "=== Applying updated db-schema.sql to master ==="
mysql -h"$MYSQL_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" < db-schema.sql

echo ""
echo "=== Verifying cleanup_admin privileges ==="
mysql -h"$MYSQL_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW GRANTS FOR 'cleanup_admin'@'%';"

