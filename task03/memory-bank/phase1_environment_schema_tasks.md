# Phase 1 – Environment & Schema: Task Checklist

Use this checklist to track the implementation progress for Phase 1.

## 1. Prerequisites

- [x] MySQL 8 server is installed and reachable from the environment where scripts will run.
- [x] Master–replica (source–replica) setup from task01 is up and healthy.
- [x] User account with sufficient privileges exists on master (CREATE/DROP DATABASE, CREATE TABLE, ALTER, EVENT, etc.).
- [x] User account with sufficient privileges exists on replica to read replication metrics (e.g. `SHOW SLAVE STATUS` / `SHOW REPLICA STATUS`).
- [x] Network/firewall rules allow connections from the `task03` environment to master and replica.
- [x] `mysql` CLI client is installed on the host where scripts will run.
- [x] Access to the `porta_bootcamp` repository checked out with `task03` folder available.
- [x] Agreement on retention policy and partition window (e.g. keep 21–30 days of data).
- [x] Decision made on where to run partition maintenance (MySQL EVENT vs external cron).

## 2. Environment and Configuration

- [x] Define MySQL connection parameters (host, port, user, password) for the master.
- [x] Define MySQL connection parameters (host, port, user, password) for the replica.
- [x] Choose and confirm database name `cleanup_bench` for all scripts and SQL.
- [x] Create `.env` file in `task03/` with all required variables (DB host, port, user, password, database name). **Note: Using task01/compose/.env directly**
- [x] Ensure all Phase 1 shell scripts source the `task03/.env` file.
- [x] Verify connectivity to master using the configured environment variables.
- [x] Verify connectivity to replica using the configured environment variables.
- [x] Document replication assumptions (master used for writes/cleanup, replica used for metrics).

## 3. SQL Schema Design

### 3.1 Common row structure

- [x] Define common row structure in `db-schema.sql`:
  - [x] `id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY`.
  - [x] `ts DATETIME NOT NULL`.
  - [x] `name CHAR(10) NOT NULL`.
  - [x] `data INT UNSIGNED NOT NULL`.
- [x] Add composite index `KEY idx_ts_name (ts, name)` on all tables.

### 3.2 Per-method tables

- [x] Create table `cleanup_partitioned` with common row structure.
- [x] Create table `cleanup_truncate` with common row structure.
- [x] Create table `cleanup_copy` with common row structure.
- [x] Create table `cleanup_batch` with common row structure.
- [x] Ensure all tables use consistent engine (e.g. `ENGINE=InnoDB`).
- [x] Ensure all tables use consistent charset/collation (e.g. `utf8mb4`).

### 3.3 Partitioning for `cleanup_partitioned`

- [x] Implement RANGE partitioning on `cleanup_partitioned` using `TO_DAYS(ts)`.
- [x] Define daily partitions for at least the last 21–30 days.
- [x] Use partition names in the `pYYYYMMDD` format.
- [x] Ensure the partitioning scheme allows dropping data strictly older than 10 days.
- [x] Validate that queries on `ts` use partitions as expected.

### 3.4 Partition maintenance mechanism

- [x] Decide on maintenance mechanism: MySQL EVENT or external cron + script. **Decision: External cron + script**
- [x] Implement daily job to add a new partition for `CURRENT_DATE + 1`.
- [x] Implement daily job to drop partitions older than the configured retention (e.g. >21–30 days).
- [x] Ensure maintenance job keeps a rolling 21–30 day window of partitions.
- [x] Test maintenance job in a safe environment (dry run or test DB).

## 4. `db-schema.sql` Implementation

- [x] Add `DROP DATABASE IF EXISTS cleanup_bench;`.
- [x] Add `CREATE DATABASE cleanup_bench;`.
- [x] Add `USE cleanup_bench;`.
- [x] Implement `CREATE TABLE` statements for all four tables.
- [x] Include partitioning definition only for `cleanup_partitioned`.
- [x] Verify that `db-schema.sql` runs successfully on the master.
- [x] Verify that resulting tables and indexes match the specification.


## 5. Definition of Done (DoD)

- [x] `.env` file in `task03/` contains working master and replica connection settings and is sourced by Phase 1 scripts. **Note: Using task01/compose/.env**
- [x] Executing `db-schema.sql` on the master successfully recreates the `cleanup_bench` database without errors.
- [x] All four tables (`cleanup_partitioned`, `cleanup_truncate`, `cleanup_copy`, `cleanup_batch`) exist with the common row structure and `idx_ts_name` index.
- [x] `cleanup_partitioned` is partitioned by day using `TO_DAYS(ts)` with partitions covering at least the last 21–30 days.
- [x] It is possible to drop all data strictly older than 10 days by dropping the appropriate partitions.
- [x] Partition maintenance mechanism (EVENT or cron + script) is implemented and validated on a test database.
- [x] Basic sanity tests confirm that inserts and simple queries against each table succeed.
- [ ] Phase 1 behavior and assumptions are briefly documented in `task03/README.md` or a dedicated section. **Note: Deferred to Phase 7 (Documentation)**
