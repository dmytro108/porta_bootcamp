# Implementation – Phase 4: Metrics & Instrumentation

## 5. Metrics and Instrumentation

5.1 **MySQL status metrics**
- Collect values before and after each run (and, if needed, during the experiment):
  - `SHOW GLOBAL STATUS LIKE 'Innodb_rows_deleted';`
  - `SHOW GLOBAL STATUS LIKE 'Innodb_row_lock_time';`
  - other relevant InnoDB counters if needed.
- Always use the **difference** between before/after values to attribute effects to the cleanup run, because these counters are global.
- For purge lag:
  - use `SHOW ENGINE INNODB STATUS\G` and parse the `History list length` line, **or**
  - use `information_schema.INNODB_METRICS`:

    ```sql
    SELECT NAME, COUNT
    FROM information_schema.INNODB_METRICS
    WHERE NAME = 'trx_rseg_history_len';
    ```

  - record the value before and after, and for long-running runs capture it periodically to see the trend.

5.2 **Replication metrics**
- On the replica, collect from `SHOW REPLICA STATUS\G` (or `SHOW SLAVE STATUS\G` on older versions):
  - `Seconds_Behind_Source` / `Seconds_Behind_Master`;
  - `Replica_IO_Running` / `Replica_SQL_Running` (or `Slave_IO_Running` / `Slave_SQL_Running`);
  - optionally relay log size and position.
- Required checkpoints:
  - measure values **right before** the cleanup starts;
  - measure **immediately after** the cleanup finishes;
  - for long runs, record lag **periodically (every N seconds)** into a separate log to build a time series.
- Interpretation:
  - primary interest is the **maximum lag** and the shape of the lag graph for each cleanup method;
  - additionally flag situations where `*_Running = 'No'` or `Seconds_Behind_*` becomes `NULL`.

5.3 **Table size, free space and row count**
- For each test table, capture from `information_schema.TABLES`:

  ```sql
  SELECT TABLE_SCHEMA, TABLE_NAME,
         DATA_LENGTH, INDEX_LENGTH, DATA_FREE, TABLE_ROWS
  FROM   information_schema.TABLES
  WHERE  TABLE_SCHEMA = 'cleanup_bench'
    AND  TABLE_NAME   = '<table_name>';
  ```

  - `DATA_LENGTH` and `INDEX_LENGTH` — to estimate the total table size;
  - `DATA_FREE` — to estimate internal fragmentation and how much space **remains inside the file** after DELETE.
- Additionally compute exact row counts:
  - `SELECT COUNT(*) FROM <table>;` before and after cleanup.
- Log **differences** before/after for sizes and row counts to compare methods by:
  - actual disk space freed (TRUNCATE / DROP PARTITION vs batch DELETE);
  - amount of remaining `DATA_FREE`.

5.4 **Binlog size**
- Track binlog growth attributable to a specific cleanup run:
  - `SHOW BINARY LOGS;` before and after cleanup; or
  - read the size of the current binlog file from the filesystem (if allowed in the environment).
- Optionally log the name and size of the active binlog before start and after completion.

5.5 **Throughput, latency and lock/conflict metrics**

5.5.1 **Delete throughput**
- For each method run, compute:
  - `rows_deleted_total` = `rows_before - rows_after`;
  - `total_duration_sec` = `end_ts - start_ts` (in seconds);
  - `rows_deleted_per_second = rows_deleted_total / total_duration_sec`.
- For batch-based methods additionally log per-batch throughput on the client side (e.g. in `db-cleanup.sh`):
  - batch size (LIMIT);
  - batch duration;
  - local metric `rows_in_batch / duration_of_batch`.
- Important: total deleted rows should be accumulated **on the client side** (script), not via MySQL user variables, if batches are executed in separate sessions.

5.5.2 **Latency of other queries**
- During cleanup, run the background workload described in `implementation_load_simulation.md` and additionally measure latency of “representative” queries:
  - one fixed `SELECT` (for example, last N rows by index);
  - one fixed `UPDATE` over a small range.
- Measure average/median response time:
  - either via `mysql` timing (`\t` + parsing the output);
  - or via a client script (bash, Python) that timestamps before/after the query.
- For simplicity, log at least:
  - `query_type` (e.g. `select_sample`, `update_sample`);
  - `ts` (timestamp);
  - `duration_ms`.

5.5.3 **Locks and conflicts**
- If there are signs of contention on data, periodically capture state from:
  - `INFORMATION_SCHEMA.INNODB_LOCKS` / `INNODB_TRX`; or
  - the corresponding `performance_schema` tables.
- The key aggregate metric is the difference in `Innodb_row_lock_time` before/after the run as an indicator of row-level locking conflicts.

5.5.4 **Aggregated stats by statement type (optional)**
- With `performance_schema` enabled, you can use `events_statements_summary_by_digest` to estimate average DELETE throughput by statement type:

  ```sql
  SELECT
    DIGEST_TEXT,
    COUNT_STAR              AS exec_count,
    SUM_TIMER_WAIT/1e12     AS total_time_sec,
    SUM_ROWS_AFFECTED       AS total_rows,
    SUM_ROWS_AFFECTED /
      NULLIF(SUM_TIMER_WAIT/1e12, 0) AS rows_per_sec
  FROM performance_schema.events_statements_summary_by_digest
  WHERE DIGEST_TEXT LIKE 'DELETE FROM `big_table`%'
  ORDER BY total_time_sec DESC
  LIMIT 5;
  ```

- Keep in mind this is an **aggregate by query type**, not for a single experimental run; treat it as an auxiliary data source.

5.6 **Logging format**
- For each cleanup method run, create a log file under `task03/results/`:
  - file name: `<method>_<timestamp>.log` or `.csv`.
- Minimal field set (one summary row per run):
  - `method` — method name (e.g. `batch_delete_10k`, `partition_drop`);
  - `table` — target table;
  - `start_ts`, `end_ts`;
  - `rows_before`, `rows_after`, `rows_deleted`;
  - `duration_sec`;
  - `rows_deleted_per_second`.
- Additionally, for each run, store before/after snapshots of key status metrics (in the same file or in a separate JSON/CSV):
  - InnoDB status: `Innodb_rows_deleted`, `Innodb_row_lock_time`, history list length;
  - replication: `Seconds_Behind_*`, `*_Running`, and optionally relay log size;
  - table sizes: `DATA_LENGTH`, `INDEX_LENGTH`, `DATA_FREE`;
  - binlog: list/sizes of files before/after.
- For batch methods (if it does not overcomplicate the script), you can also log per-batch rows:
  - `batch_id`, `ts`, `rows_in_batch`, `batch_duration_ms`, `batch_rows_per_sec`, current `replication_lag_sec`.
