-- =====================================================
-- Fix privileges for cleanup_admin user
-- =====================================================
-- Run this script to grant missing privileges for metrics collection
-- Execute as root user
-- =====================================================

USE cleanup_bench;

-- Grant global privileges needed for metrics collection
-- RELOAD privilege is required for ANALYZE TABLE
GRANT PROCESS, REPLICATION CLIENT, RELOAD ON *.* TO 'cleanup_admin'@'%';
GRANT SELECT ON mysql.* TO 'cleanup_admin'@'%';

-- Apply privilege changes
FLUSH PRIVILEGES;

-- Verify privileges
SHOW GRANTS FOR 'cleanup_admin'@'%';

-- Test information_schema access
SELECT 
    TABLE_NAME,
    ROUND(DATA_LENGTH/1024/1024, 2) AS data_mb,
    ROUND(INDEX_LENGTH/1024/1024, 2) AS index_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'cleanup_bench'
ORDER BY TABLE_NAME;
