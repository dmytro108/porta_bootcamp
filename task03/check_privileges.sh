#!/bin/bash

MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
CLEANUP_USER="${CLEANUP_USER:-root}"
CLEANUP_PASSW="${CLEANUP_PASSW:-${MYSQL_ROOT_PASSWORD:-}}"

echo "Checking privileges for $CLEANUP_USER..."

mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    -e "SHOW GRANTS FOR CURRENT_USER();" 2>&1

