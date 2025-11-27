-- Grant privileges for localhost connections (for phpMyAdmin and web interfaces)

CREATE USER IF NOT EXISTS 'cleanup_admin'@'localhost' IDENTIFIED BY 'cleanup_pass123';

GRANT ALL PRIVILEGES ON cleanup_bench.* TO 'cleanup_admin'@'localhost';
GRANT RELOAD, PROCESS, REPLICATION CLIENT ON *.* TO 'cleanup_admin'@'localhost';
GRANT SELECT ON mysql.* TO 'cleanup_admin'@'localhost';

FLUSH PRIVILEGES;

-- Verify both users
SHOW GRANTS FOR 'cleanup_admin'@'%';
SHOW GRANTS FOR 'cleanup_admin'@'localhost';
