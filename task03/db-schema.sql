-- =====================================================
-- Task 03: MySQL Cleanup Benchmark - Database Schema
-- =====================================================
-- This script creates the cleanup_bench database and tables
-- for testing different cleanup methods on large datasets.
-- =====================================================

-- Drop and recreate the test database
DROP DATABASE IF EXISTS cleanup_bench;
CREATE DATABASE cleanup_bench CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE cleanup_bench;

-- =====================================================
-- Create database user with full privileges
-- =====================================================
-- Drop users if exists (MySQL 5.7+)
DROP USER IF EXISTS 'cleanup_admin'@'%';
DROP USER IF EXISTS 'cleanup_admin'@'localhost';

-- Create new users with password
-- '%' - for remote connections (container-to-container, scripts)
-- 'localhost' - for local connections (phpMyAdmin, web interfaces)
CREATE USER 'cleanup_admin'@'%' IDENTIFIED BY 'cleanup_pass123';
CREATE USER 'cleanup_admin'@'localhost' IDENTIFIED BY 'cleanup_pass123';

-- Grant all privileges on cleanup_bench database to both users
-- This includes SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, INDEX, etc.
GRANT ALL PRIVILEGES ON cleanup_bench.* TO 'cleanup_admin'@'%';
GRANT ALL PRIVILEGES ON cleanup_bench.* TO 'cleanup_admin'@'localhost';

-- Grant global privileges needed for metrics collection and table maintenance
-- PROCESS: Required for SHOW ENGINE INNODB STATUS, information_schema.INNODB_METRICS, information_schema.TABLES
-- REPLICATION CLIENT: Required for SHOW REPLICA/SLAVE STATUS, SHOW BINARY LOGS, SHOW MASTER STATUS
-- RELOAD: Required for FLUSH operations and ANALYZE TABLE
-- SELECT on mysql.*: Required for reading mysql system tables
GRANT PROCESS, REPLICATION CLIENT, RELOAD ON *.* TO 'cleanup_admin'@'%';
GRANT SELECT ON mysql.* TO 'cleanup_admin'@'%';

GRANT PROCESS, REPLICATION CLIENT, RELOAD ON *.* TO 'cleanup_admin'@'localhost';
GRANT SELECT ON mysql.* TO 'cleanup_admin'@'localhost';

-- Apply privilege changes
FLUSH PRIVILEGES;

-- =====================================================
-- Common table structure for all cleanup methods
-- =====================================================
-- All tables share the same logical structure:
--   - id: auto-increment primary key
--   - ts: timestamp for partitioning and cleanup filtering
--   - name: 10-char string for realistic data size
--   - data: integer value for workload simulation
--   - idx_ts_name: composite index to simulate query patterns
-- =====================================================

-- Table 1: cleanup_partitioned
-- Uses RANGE partitioning by day on ts column
-- Cleanup method: DROP PARTITION / TRUNCATE PARTITION
-- Note: PRIMARY KEY must include partitioning column (ts)
-- =====================================================
CREATE TABLE cleanup_partitioned (
    id BIGINT UNSIGNED AUTO_INCREMENT,
    ts DATETIME NOT NULL,
    name CHAR(10) NOT NULL,
    data INT UNSIGNED NOT NULL,
    PRIMARY KEY (id, ts),
    KEY idx_ts_name (ts, name)
) ENGINE=InnoDB
PARTITION BY RANGE (TO_DAYS(ts)) (
    -- Create partitions for the last 30 days
    -- Partitions are named pYYYYMMDD for clarity
    -- Current date: 2025-11-20, so we create partitions from 2025-10-21 to 2025-12-20
    PARTITION p20251021 VALUES LESS THAN (TO_DAYS('2025-10-22')),
    PARTITION p20251022 VALUES LESS THAN (TO_DAYS('2025-10-23')),
    PARTITION p20251023 VALUES LESS THAN (TO_DAYS('2025-10-24')),
    PARTITION p20251024 VALUES LESS THAN (TO_DAYS('2025-10-25')),
    PARTITION p20251025 VALUES LESS THAN (TO_DAYS('2025-10-26')),
    PARTITION p20251026 VALUES LESS THAN (TO_DAYS('2025-10-27')),
    PARTITION p20251027 VALUES LESS THAN (TO_DAYS('2025-10-28')),
    PARTITION p20251028 VALUES LESS THAN (TO_DAYS('2025-10-29')),
    PARTITION p20251029 VALUES LESS THAN (TO_DAYS('2025-10-30')),
    PARTITION p20251030 VALUES LESS THAN (TO_DAYS('2025-10-31')),
    PARTITION p20251031 VALUES LESS THAN (TO_DAYS('2025-11-01')),
    PARTITION p20251101 VALUES LESS THAN (TO_DAYS('2025-11-02')),
    PARTITION p20251102 VALUES LESS THAN (TO_DAYS('2025-11-03')),
    PARTITION p20251103 VALUES LESS THAN (TO_DAYS('2025-11-04')),
    PARTITION p20251104 VALUES LESS THAN (TO_DAYS('2025-11-05')),
    PARTITION p20251105 VALUES LESS THAN (TO_DAYS('2025-11-06')),
    PARTITION p20251106 VALUES LESS THAN (TO_DAYS('2025-11-07')),
    PARTITION p20251107 VALUES LESS THAN (TO_DAYS('2025-11-08')),
    PARTITION p20251108 VALUES LESS THAN (TO_DAYS('2025-11-09')),
    PARTITION p20251109 VALUES LESS THAN (TO_DAYS('2025-11-10')),
    PARTITION p20251110 VALUES LESS THAN (TO_DAYS('2025-11-11')),
    PARTITION p20251111 VALUES LESS THAN (TO_DAYS('2025-11-12')),
    PARTITION p20251112 VALUES LESS THAN (TO_DAYS('2025-11-13')),
    PARTITION p20251113 VALUES LESS THAN (TO_DAYS('2025-11-14')),
    PARTITION p20251114 VALUES LESS THAN (TO_DAYS('2025-11-15')),
    PARTITION p20251115 VALUES LESS THAN (TO_DAYS('2025-11-16')),
    PARTITION p20251116 VALUES LESS THAN (TO_DAYS('2025-11-17')),
    PARTITION p20251117 VALUES LESS THAN (TO_DAYS('2025-11-18')),
    PARTITION p20251118 VALUES LESS THAN (TO_DAYS('2025-11-19')),
    PARTITION p20251119 VALUES LESS THAN (TO_DAYS('2025-11-20')),
    PARTITION p20251120 VALUES LESS THAN (TO_DAYS('2025-11-21')),
    PARTITION p20251121 VALUES LESS THAN (TO_DAYS('2025-11-22')),
    PARTITION p20251122 VALUES LESS THAN (TO_DAYS('2025-11-23')),
    PARTITION p20251123 VALUES LESS THAN (TO_DAYS('2025-11-24')),
    PARTITION p20251124 VALUES LESS THAN (TO_DAYS('2025-11-25')),
    PARTITION p20251125 VALUES LESS THAN (TO_DAYS('2025-11-26')),
    PARTITION p20251126 VALUES LESS THAN (TO_DAYS('2025-11-27')),
    PARTITION p20251127 VALUES LESS THAN (TO_DAYS('2025-11-28')),
    PARTITION p20251128 VALUES LESS THAN (TO_DAYS('2025-11-29')),
    PARTITION p20251129 VALUES LESS THAN (TO_DAYS('2025-11-30')),
    PARTITION p20251130 VALUES LESS THAN (TO_DAYS('2025-12-01')),
    PARTITION p20251201 VALUES LESS THAN (TO_DAYS('2025-12-02')),
    PARTITION p20251202 VALUES LESS THAN (TO_DAYS('2025-12-03')),
    PARTITION p20251203 VALUES LESS THAN (TO_DAYS('2025-12-04')),
    PARTITION p20251204 VALUES LESS THAN (TO_DAYS('2025-12-05')),
    PARTITION p20251205 VALUES LESS THAN (TO_DAYS('2025-12-06')),
    PARTITION p20251206 VALUES LESS THAN (TO_DAYS('2025-12-07')),
    PARTITION p20251207 VALUES LESS THAN (TO_DAYS('2025-12-08')),
    PARTITION p20251208 VALUES LESS THAN (TO_DAYS('2025-12-09')),
    PARTITION p20251209 VALUES LESS THAN (TO_DAYS('2025-12-10')),
    PARTITION p20251210 VALUES LESS THAN (TO_DAYS('2025-12-11')),
    PARTITION p20251211 VALUES LESS THAN (TO_DAYS('2025-12-12')),
    PARTITION p20251212 VALUES LESS THAN (TO_DAYS('2025-12-13')),
    PARTITION p20251213 VALUES LESS THAN (TO_DAYS('2025-12-14')),
    PARTITION p20251214 VALUES LESS THAN (TO_DAYS('2025-12-15')),
    PARTITION p20251215 VALUES LESS THAN (TO_DAYS('2025-12-16')),
    PARTITION p20251216 VALUES LESS THAN (TO_DAYS('2025-12-17')),
    PARTITION p20251217 VALUES LESS THAN (TO_DAYS('2025-12-18')),
    PARTITION p20251218 VALUES LESS THAN (TO_DAYS('2025-12-19')),
    PARTITION p20251219 VALUES LESS THAN (TO_DAYS('2025-12-20')),
    PARTITION p20251220 VALUES LESS THAN (TO_DAYS('2025-12-21')),
    PARTITION pFUTURE VALUES LESS THAN MAXVALUE
);

-- Table 2: cleanup_truncate
-- Non-partitioned table for TRUNCATE TABLE tests
-- Cleanup method: TRUNCATE TABLE (removes all data)
-- =====================================================
CREATE TABLE cleanup_truncate (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ts DATETIME NOT NULL,
    name CHAR(10) NOT NULL,
    data INT UNSIGNED NOT NULL,
    KEY idx_ts_name (ts, name)
) ENGINE=InnoDB;

-- Table 3: cleanup_copy
-- Non-partitioned table for "copy to new table" method
-- Cleanup method: CREATE ... LIKE, INSERT ... SELECT, RENAME, DROP
-- =====================================================
CREATE TABLE cleanup_copy (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ts DATETIME NOT NULL,
    name CHAR(10) NOT NULL,
    data INT UNSIGNED NOT NULL,
    KEY idx_ts_name (ts, name)
) ENGINE=InnoDB;

-- Table 4: cleanup_batch
-- Non-partitioned table for batch DELETE tests
-- Cleanup method: DELETE ... WHERE ... LIMIT in batches
-- =====================================================
CREATE TABLE cleanup_batch (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ts DATETIME NOT NULL,
    name CHAR(10) NOT NULL,
    data INT UNSIGNED NOT NULL,
    KEY idx_ts_name (ts, name)
) ENGINE=InnoDB;

-- =====================================================
-- Verification queries
-- =====================================================
-- Show all tables
SHOW TABLES;

-- Show partition information for cleanup_partitioned
SELECT 
    TABLE_NAME,
    PARTITION_NAME,
    PARTITION_METHOD,
    PARTITION_EXPRESSION,
    PARTITION_DESCRIPTION
FROM INFORMATION_SCHEMA.PARTITIONS
WHERE TABLE_SCHEMA = 'cleanup_bench' 
  AND TABLE_NAME = 'cleanup_partitioned'
ORDER BY PARTITION_ORDINAL_POSITION;