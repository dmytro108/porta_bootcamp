# Implementation – Phase 6: Orchestration & Automation

## 7. Orchestrator Script – `db-cleanup.sh`

7.1 **Inputs and configuration**
- Extend existing `task03/db-cleanup.sh` to implement orchestration:
  - Source the `.env` file for connection parameters.
  - Accept CLI options, for example:
    - `--method all|partition|truncate|copy|batch`.
    - `--batch-size N` for batch delete.
    - `--output-dir task03/results`.
    - `--dry-run` for previewing actions.

7.2 **High-level flow (per invocation)**
1. Parse arguments and load configuration.
2. Verify database connectivity (`SELECT VERSION();`).
3. Optionally verify that `db-traffic.sh` is running (or document that user should start it manually).
4. For each selected method:
   - Capture pre-run metrics (InnoDB status vars, replication status, table sizes, row counts, binlog info).
   - Record wall-clock start time (e.g. `date +%s.%N`).
   - Execute the SQL sequence for that method.
   - Record wall-clock end time.
   - Capture post-run metrics using the same queries as pre-run.
   - Compute derived metrics (rows deleted, duration, rows_deleted_per_second, size differences, replication lag change).
   - Append metrics to a per-method log file in `task03/results/`.

7.3 **Utility helpers inside the script**
- `mysql_exec()`: wrapper calling `mysql` with configured connection options.
- `get_status_var(var_name)`: reads a specific `SHOW GLOBAL STATUS` variable.
- `get_table_size(db, table)`: queries `information_schema.TABLES` and returns `DATA_LENGTH + INDEX_LENGTH`.
- `get_row_count(db, table)`: runs `SELECT COUNT(*)`.
- `get_replication_status()`: runs `SHOW REPLICA STATUS\G` (or `SHOW SLAVE STATUS\G`) and parses `Seconds_Behind_Source`.
- `log()`: writes timestamped lines to a log file.

## 8. Optional Helper SQL Scripts

8.1 **Initialization helper**
- Either keep everything in `db-schema.sql` or add an extra file, e.g. `db-init.sql`, that:
  - Creates the database and tables.
  - Optionally creates a dedicated MySQL user for the tests.

8.2 **Metrics helper**
- Create an optional `db-show-metrics.sql` with queries to:
  - Show table sizes.
  - Show key InnoDB status variables.
  - Show replication lag.
