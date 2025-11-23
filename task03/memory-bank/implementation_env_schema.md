# Implementation – Phase 1: Environment & Schema

## 1. Environment and Configuration

1.1 **Database and connection parameters**
- Database name: `cleanup_bench`.
- Connection details: host, default port, user, password.
- Store connection settings in a `.env` file in `task03/` and source it from all shell scripts.

1.2 **Replication test setup**
- Experiments run against an existing master–slave (source–replica) setup from task01.
- DSNs:
  - Master: used for data load and cleanup methods.
  - Replica: used to read replication-related metrics (`Seconds_Behind_Source`, relay log application speed).

---

## 2. SQL Schema Design

2.1 **Common row structure**
All method-specific tables share the same logical row format:
- `id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY`
- `ts DATETIME NOT NULL` – timestamp of the event, indexed.
- `name CHAR(10) NOT NULL` – fixed-length ASCII string.
- `data INT UNSIGNED NOT NULL`.

2.2 **Per-method tables**
Create separate tables for each cleanup strategy:
- `cleanup_partitioned` – InnoDB table partitioned by day on `ts`.
- `cleanup_truncate` – non-partitioned table used for `TRUNCATE TABLE` tests.
- `cleanup_copy` – non-partitioned table used for the "copy to new table" method.
- `cleanup_batch` – non-partitioned table used for batch `DELETE ... LIMIT`.

2.3 **Indexing strategy**
- Add a composite index `KEY idx_ts_name (ts, name)` to simulate realistic query workloads and observe index maintenance overhead.

2.4 **Partitioning details for `cleanup_partitioned`**
- Use RANGE partitioning by `TO_DAYS(ts)` with daily partitions:
  - Partitions for at least the last 21–30 days.
  - Naming convention like `pYYYYMMDD` for clarity.
- Ensure there is a partitioning scheme that makes it trivial to drop all partitions strictly older than 10 days.
- Maintain a rolling window of partitions using a scheduled job (cron or MySQL EVENT) that, once per day:
  - Adds a new partition for `CURRENT_DATE + 1` day ahead (future partition).
  - Drops the partition whose range upper bound is older than the configured retention (e.g. 21–30 days).
- Ensure there is a partitioning maintenance mechanism (script or EVENT) that keeps the 21–30 day window by regularly adding new daily partitions and dropping old ones.

2.5 **Implementation in `db-schema.sql`**
- Drop and recreate the test database:
  - `DROP DATABASE IF EXISTS cleanup_bench;`
  - `CREATE DATABASE cleanup_bench;`
  - `USE cleanup_bench;`
- Create all four tables with consistent engine and charset (e.g. `ENGINE=InnoDB`, `utf8mb4`).
- Include partitioning definition only for `cleanup_partitioned`.
