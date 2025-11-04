#!/bin/bash

# Healthcheck script for MySQL slave/replica
# Checks: 1) Replica is running, 2) No replication errors, 3) Tables are replicated

set -e

# Check replica status
REPLICA_STATUS=$(mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW REPLICA STATUS\G" 2>/dev/null)

if [ -z "$REPLICA_STATUS" ]; then
  echo "Healthcheck failed: Unable to get replica status"
  exit 1
fi

# Check if both IO and SQL threads are running
IO_RUNNING=$(echo "$REPLICA_STATUS" | grep "Replica_IO_Running:" | awk '{print $2}')
SQL_RUNNING=$(echo "$REPLICA_STATUS" | grep "Replica_SQL_Running:" | awk '{print $2}')

if [ "$IO_RUNNING" != "Yes" ]; then
  echo "Healthcheck failed: Replica IO thread not running (IO_Running: $IO_RUNNING)"
  exit 1
fi

if [ "$SQL_RUNNING" != "Yes" ]; then
  echo "Healthcheck failed: Replica SQL thread not running (SQL_Running: $SQL_RUNNING)"
  exit 1
fi

# Check for replication errors
LAST_IO_ERROR=$(echo "$REPLICA_STATUS" | grep "Last_IO_Error:" | cut -d: -f2- | xargs)
LAST_SQL_ERROR=$(echo "$REPLICA_STATUS" | grep "Last_SQL_Error:" | cut -d: -f2- | xargs)

if [ -n "$LAST_IO_ERROR" ] && [ "$LAST_IO_ERROR" != "" ]; then
  echo "Healthcheck failed: Replica IO error: $LAST_IO_ERROR"
  exit 1
fi

if [ -n "$LAST_SQL_ERROR" ] && [ "$LAST_SQL_ERROR" != "" ]; then
  echo "Healthcheck failed: Replica SQL error: $LAST_SQL_ERROR"
  exit 1
fi

# Check if tables have been replicated
TABLES_COUNT=$(mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e \
  "SELECT COUNT(*) FROM information_schema.tables 
   WHERE table_schema='${MYSQL_DATABASE}' 
   AND table_name IN ('Movie','Reviewer','Rating');" 2>/dev/null)

if [ "$TABLES_COUNT" -ne 3 ]; then
  echo "Healthcheck failed: Expected 3 replicated tables, found ${TABLES_COUNT}"
  exit 1
fi

echo "Healthcheck passed: Replica running, no errors, tables replicated"
exit 0
