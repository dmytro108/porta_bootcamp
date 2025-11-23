# Phase 2 – Data Generation & Load: Task Checklist

This checklist breaks down Phase 2 into concrete, trackable tasks.
Use `[ ]` / `[x]` to mark items as you progress.

---

## Prerequisites

- [x] `.env` in `task03/` defines MySQL connection (`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`, `DB_NAME=cleanup_bench`). **Note: Using task01/compose/.env**
- [x] Master–replica setup from task01 is running and reachable from this environment.
- [x] Phase 1 schema (`db-schema.sql`) is implemented and applied, with tables:
  - [x] `cleanup_partitioned`
  - [x] `cleanup_truncate`
  - [x] `cleanup_copy`
  - [x] `cleanup_batch`
- [x] MySQL client/bulk tools available (`mysql`, `mysqlimport` or `LOAD DATA LOCAL INFILE` enabled). **Note: Using mysql client with INSERT statements**
- [x] `task03/` scripts can `source` the shared `.env` without errors (`set -u` friendly, no missing vars).

---

## Phase 2 Tasks – Data Generation & Load

### 1. Row Volume and Distribution

- [x] Confirm base row volume target of **100,000 rows** per table in spec.
- [x] Decide and document random distribution for `ts` between `NOW() - INTERVAL 20 DAY` and `NOW()`.
- [x] Implement generation so that roughly half of rows are older than 10 days.
- [x] Define generator for `name` as random 10-character ASCII (A–Z or alphanumeric).
- [x] Define generator for `data` as random integer in `[0, 10,000,000]`.

### 2. `db-load.sh` Script Skeleton

- [x] Create `task03/db-load.sh` with executable permissions.
- [x] In `db-load.sh`, `source` `task03/.env` and validate required variables. **Note: Script supports both sourcing .env and using environment variables**
- [x] Implement CLI parsing for options:
  - [x] `--rows N` (default `100000`).
  - [x] `--db NAME` (default `cleanup_bench`).
- [x] Add `--help` output describing script usage and options.

### 3. CSV Generation Logic

- [x] Choose CSV location and filename (e.g. `task03/data/events_seed.csv`).
- [x] Ensure `task03/data/` directory is created if missing.
- [x] Implement CSV generation for N rows with columns: `ts,name,data` (no `id`).
- [x] Use deterministic or seeded RNG option (optional) to allow reproducible datasets.
- [x] Ensure CSV is generated once and **reused** across tables for fair comparison.
- [x] Add guard to skip regeneration when existing CSV already satisfies requested row count (or add `--force-regenerate` option).

### 4. Bulk Load Strategy

- [x] Decide between `LOAD DATA LOCAL INFILE` and `mysqlimport` (default to `LOAD DATA LOCAL INFILE`). **Note: Using batched INSERT statements due to LOCAL INFILE being disabled**
- [x] Implement helper in `db-load.sh` that performs `LOAD DATA` for a given table.
- [x] Ensure connection parameters (host, port, user, password, db) are passed correctly to the MySQL client.
- [x] Define column list for `LOAD DATA` to map CSV `ts,name,data` to table columns (skipping `id`).
- [x] Handle `LOCAL` capability: document and/or configure MySQL to allow `LOCAL INFILE` as needed. **Note: Implemented alternative using batched INSERT statements (1000 rows/batch)**

### 5. Per-table Load Flow

For each table (`cleanup_partitioned`, `cleanup_truncate`, `cleanup_copy`, `cleanup_batch`):

- [x] Optionally truncate or delete existing rows before loading (for clean base state).
- [x] Execute `LOAD DATA` from the shared CSV into the table.
- [x] Capture number of affected rows and check against requested row count.

### 6. Script Output and Logging

- [x] Print clear summary at the end of `db-load.sh`:
  - [x] Rows requested vs loaded per table.
  - [x] CSV path and row count.
- [x] Log errors (connection failures, `LOAD DATA` failures) with non-zero exit codes.
- [x] Optionally support a `--verbose` flag for detailed logging.

### 7. Integration with Other Phases

- [x] Ensure `db-cleanup.sh` and `db-traffic.sh` (Phase 3/6) can rely on tables being pre-populated by `db-load.sh`.
- [ ] Document in `task03/README.md` that `db-load.sh` must be run before cleanup experiments. **Note: Deferred to Phase 7 (Documentation)**

---

## Definition of Done (DoD)

- [x] All prerequisites in the **Prerequisites** section are satisfied and verified.
- [x] `task03/db-load.sh` exists, is executable, and returns exit code 0 on success.
- [x] Running `./db-load.sh` with defaults:
  - [x] Creates or reuses a CSV file with at least 100,000 rows.
  - [x] Populates each of the four method tables with ~100,000 rows.
  - [x] Uses the **same** CSV contents for all four tables.
- [x] Spot check query on `cleanup_bench` confirms:
  - [x] `ts` values span from ~20 days ago up to `NOW()`.
  - [x] At least half of rows have `ts < NOW() - INTERVAL 10 DAY`.
  - [x] `name` values are 10-character ASCII strings.
  - [x] `data` is within the expected numeric range.
- [ ] `task03/README.md` updated with:
  - [ ] Brief description of Phase 2 and `db-load.sh` purpose.
  - [ ] Example command(s) to run the data load.
- [x] Phase 2 checklist (this file) reviewed and all relevant items marked as done.
