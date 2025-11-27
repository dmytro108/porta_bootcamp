#!/bin/bash

CLEANUP_USER="cleanup_admin"
CLEANUP_PASSW="cleanup_pass123"
DB_SLAVE_HOST="${DB_SLAVE_HOST:-db_slave}"

echo "=== Full SHOW REPLICA STATUS output ==="
mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    -e "SHOW REPLICA STATUS\G" 2>&1 | grep -i "seconds_behind"

echo ""
echo "=== Testing exact parsing logic from script ==="
lag=$(mysql -h"$DB_SLAVE_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASSW" \
    cleanup_bench --skip-column-names --batch \
    -e "SHOW REPLICA STATUS\G" 2>/dev/null | \
    grep "Seconds_Behind_Source:" | awk '{print $2}')

echo "Parsed lag value: '$lag'"

if [[ -z "$lag" || "$lag" == "NULL" ]]; then
    echo "Result: -1 (unavailable)"
else
    echo "Result: $lag seconds"
fi

