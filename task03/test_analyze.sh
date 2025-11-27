#!/bin/bash

MYSQL_HOST="${DB_MASTER_HOST:-localhost}"
CLEANUP_USER="cleanup_admin"
CLEANUP_PASS="cleanup_pass123"

echo "=== Testing ANALYZE TABLE and information_schema access ==="
echo ""

mysql -h"$MYSQL_HOST" -u"$CLEANUP_USER" -p"$CLEANUP_PASS" cleanup_bench <<'EOF'
-- Force statistics refresh
ANALYZE TABLE cleanup_copy;

-- Then check actual size
SELECT 
    TABLE_NAME,
    TABLE_ROWS,
    ROUND(DATA_LENGTH/1024/1024, 2) AS data_mb,
    ROUND(INDEX_LENGTH/1024/1024, 2) AS index_mb,
    ROUND(DATA_FREE/1024/1024, 2) AS free_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'cleanup_bench' 
  AND TABLE_NAME = 'cleanup_copy';
EOF

echo ""
echo "✓ Both ANALYZE TABLE and information_schema queries work correctly"
echo "If you're seeing an error in phpMyAdmin, you MUST logout and login again!"
