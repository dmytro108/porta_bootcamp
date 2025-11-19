# Phase 2 – Data Generation & Load: Task Checklist

This checklist breaks down Phase 2 into concrete, trackable tasks.
Use `[ ]` / `[x]` to mark items as you progress.

---

## Prerequisites

- [ ] `.env` in `task03/` defines MySQL connection (`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`, `DB_NAME=cleanup_bench`).
- [ ] Master–replica setup from task01 is running and reachable from this environment.
- [ ] Phase 1 schema (`db-schema.sql`) is implemented and applied, with tables:
  - [ ] `cleanup_partitioned`
  - [ ] `cleanup_truncate`
  - [ ] `cleanup_copy`
  - [ ] `cleanup_batch`
- [ ] MySQL client/bulk tools available (`mysql`, `mysqlimport` or `LOAD DATA LOCAL INFILE` enabled).
- [ ] `task03/` scripts can `source` the shared `.env` without errors (`set -u` friendly, no missing vars).

---

## Phase 2 Tasks – Data Generation & Load

### 1. Row Volume and Distribution

- [ ] Confirm base row volume target of **100,000 rows** per table in spec.
- [ ] Decide and document random distribution for `ts` between `NOW() - INTERVAL 20 DAY` and `NOW()`.
- [ ] Implement generation so that roughly half of rows are older than 10 days.
- [ ] Define generator for `name` as random 10-character ASCII (A–Z or alphanumeric).
- [ ] Define generator for `data` as random integer in `[0, 10,000,000]`.

### 2. `db-load.sh` Script Skeleton

- [ ] Create `task03/db-load.sh` with executable permissions.
- [ ] In `db-load.sh`, `source` `task03/.env` and validate required variables.
- [ ] Implement CLI parsing for options:
  - [ ] `--rows N` (default `100000`).
  - [ ] `--db NAME` (default `cleanup_bench`).
- [ ] Add `--help` output describing script usage and options.

### 3. CSV Generation Logic

- [ ] Choose CSV location and filename (e.g. `task03/data/events_seed.csv`).
- [ ] Ensure `task03/data/` directory is created if missing.
- [ ] Implement CSV generation for N rows with columns: `ts,name,data` (no `id`).
- [ ] Use deterministic or seeded RNG option (optional) to allow reproducible datasets.
- [ ] Ensure CSV is generated once and **reused** across tables for fair comparison.
- [ ] Add guard to skip regeneration when existing CSV already satisfies requested row count (or add `--force-regenerate` option).

### 4. Bulk Load Strategy

- [ ] Decide between `LOAD DATA LOCAL INFILE` and `mysqlimport` (default to `LOAD DATA LOCAL INFILE`).
- [ ] Implement helper in `db-load.sh` that performs `LOAD DATA` for a given table.
- [ ] Ensure connection parameters (host, port, user, password, db) are passed correctly to the MySQL client.
- [ ] Define column list for `LOAD DATA` to map CSV `ts,name,data` to table columns (skipping `id`).
- [ ] Handle `LOCAL` capability: document and/or configure MySQL to allow `LOCAL INFILE` as needed.

### 5. Per-table Load Flow

For each table (`cleanup_partitioned`, `cleanup_truncate`, `cleanup_copy`, `cleanup_batch`):

- [ ] Optionally truncate or delete existing rows before loading (for clean base state).
- [ ] Execute `LOAD DATA` from the shared CSV into the table.
- [ ] Capture number of affected rows and check against requested row count.

### 6. Script Output and Logging

- [ ] Print clear summary at the end of `db-load.sh`:
  - [ ] Rows requested vs loaded per table.
  - [ ] CSV path and row count.
- [ ] Log errors (connection failures, `LOAD DATA` failures) with non-zero exit codes.
- [ ] Optionally support a `--verbose` flag for detailed logging.

### 7. Integration with Other Phases

- [ ] Ensure `db-cleanup.sh` and `db-traffic.sh` (Phase 3/6) can rely on tables being pre-populated by `db-load.sh`.
- [ ] Document in `task03/README.md` that `db-load.sh` must be run before cleanup experiments.

---

## Definition of Done (DoD)

- [ ] All prerequisites in the **Prerequisites** section are satisfied and verified.
- [ ] `task03/db-load.sh` exists, is executable, and returns exit code 0 on success.
- [ ] Running `./db-load.sh` with defaults:
  - [ ] Creates or reuses a CSV file with at least 100,000 rows.
  - [ ] Populates each of the four method tables with ~100,000 rows.
  - [ ] Uses the **same** CSV contents for all four tables.
- [ ] Spot check query on `cleanup_bench` confirms:
  - [ ] `ts` values span from ~20 days ago up to `NOW()`.
  - [ ] At least half of rows have `ts < NOW() - INTERVAL 10 DAY`.
  - [ ] `name` values are 10-character ASCII strings.
  - [ ] `data` is within the expected numeric range.
- [ ] `task03/README.md` updated with:
  - [ ] Brief description of Phase 2 and `db-load.sh` purpose.
  - [ ] Example command(s) to run the data load.
- [ ] Phase 2 checklist (this file) reviewed and all relevant items marked as done.
