#!/bin/bash

# Healthcheck script for MySQL master
# Checks: 1) Replica user exists, 2) Tables created, 3) Master replication ready

set -e

# Check if replica user exists
REPLICA_USER_COUNT=$(mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e \
  "SELECT COUNT(*) FROM mysql.user WHERE user='${REPLICA_USER}';")

if [ "$REPLICA_USER_COUNT" -ne 1 ]; then
  echo "Healthcheck failed: Replica user '${REPLICA_USER}' not found"
  exit 1
fi

# Check if all application tables exist
TABLES_COUNT=$(mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e \
  "SELECT COUNT(*) FROM information_schema.tables 
   WHERE table_schema='${MYSQL_DATABASE}' 
   AND table_name IN ('Movie','Reviewer','Rating');")

if [ "$TABLES_COUNT" -ne 3 ]; then
  echo "Healthcheck failed: Expected 3 tables, found ${TABLES_COUNT}"
  exit 1
fi

# Check if master replication is active (binary logging enabled)
MASTER_STATUS=$(mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e "SHOW MASTER STATUS\G" 2>/dev/null)

if ! echo "$MASTER_STATUS" | grep -q "mysql-bin"; then
  echo "Healthcheck failed: Master binary logging not active"
  exit 1
fi

echo "Healthcheck passed: Replica user exists, tables created, master replication ready"
exit 0
