#!/bin/bash
# Add some old data for testing
mysql -h"${DB_MASTER_HOST:-localhost}" -u"${CLEANUP_USER:-root}" -p"${CLEANUP_PASSW}" cleanup_bench << 'SQL'
INSERT INTO cleanup_batch (ts, name, data) 
SELECT NOW() - INTERVAL 15 DAY, CONCAT('test_', FLOOR(RAND() * 1000)), FLOOR(RAND() * 1000000)
FROM (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) t1,
     (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) t2
LIMIT 25;
SELECT 'Added rows for testing' as status;
SQL
