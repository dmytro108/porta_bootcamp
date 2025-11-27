#!/bin/bash

echo "=== Recreating database with updated privileges ==="
./run-in-container.sh create-db.sh

echo ""
echo "=== Verifying cleanup_admin privileges ==="
./run-in-container.sh bash -c "mysql -h db_master -u cleanup_admin -pcleanup_pass123 -e \"SHOW GRANTS FOR CURRENT_USER();\""

echo ""
echo "=== Testing PROCESS privilege (SHOW ENGINE INNODB STATUS) ==="
./run-in-container.sh bash -c "mysql -h db_master -u cleanup_admin -pcleanup_pass123 cleanup_bench -e \"SHOW ENGINE INNODB STATUS\\G\" 2>&1 | head -10"

echo ""
echo "=== Testing REPLICATION CLIENT privilege (SHOW REPLICA STATUS on slave) ==="
./run-in-container.sh bash -c "mysql -h db_slave -u cleanup_admin -pcleanup_pass123 -e \"SHOW REPLICA STATUS\\G\" 2>&1 | head -10"

