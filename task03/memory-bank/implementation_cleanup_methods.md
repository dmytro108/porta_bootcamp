# Implementation – Phase 5: Cleanup Methods

## 6. Cleanup Method Implementations (SQL level)

6.1 **Partitioned table – `DROP/TRUNCATE PARTITION`**
- Table: `cleanup_partitioned`.
- Steps:
  - Identify partitions where the upper bound is older than `NOW() - INTERVAL 10 DAY`:
    - Query `information_schema.PARTITIONS` for `cleanup_partitioned`.
  - Build an `ALTER TABLE` statement to drop or truncate all such partitions, e.g.:
    - `ALTER TABLE cleanup_partitioned DROP PARTITION pYYYYMMDD, ...;`
  - Measure start and end time of this `ALTER` statement.

6.2 **Full `TRUNCATE TABLE` method**
- Table: `cleanup_truncate`.
- Steps:
  - Measure how long `TRUNCATE TABLE cleanup_truncate;` takes.
  - Note that this removes **all** data, not just data older than 10 days.
  - Highlight in documentation that this method is only valid when the business logic allows discarding the entire table contents.

6.3 **"Copy to a new table" method**
- Table: `cleanup_copy`.
- Steps:
  1. `CREATE TABLE cleanup_copy_new LIKE cleanup_copy;`
  2. `INSERT INTO cleanup_copy_new SELECT * FROM cleanup_copy WHERE ts >= NOW() - INTERVAL 10 DAY;`
  3. Atomically swap tables:
     - `RENAME TABLE cleanup_copy TO cleanup_copy_old, cleanup_copy_new TO cleanup_copy;`
  4. Drop the old table:
     - `DROP TABLE cleanup_copy_old;`
- Measure the entire sequence and log metrics.
- Be aware of DDL autocommit behavior and its replication impact.

6.4 **Batch `DELETE ... WHERE ... LIMIT` method**
- Table: `cleanup_batch`.
- Steps:
  - In a loop:
    - Issue a delete such as:
      - `DELETE FROM cleanup_batch WHERE ts < NOW() - INTERVAL 10 DAY ORDER BY ts LIMIT <batch_size>;`
    - Record per-batch:
      - Start time, end time, and rows affected.
    - Continue until `ROW_COUNT() = 0`.
- Parameters:
  - Configurable `batch_size` (e.g. 1000, 5000, 10000).
- Compute per-batch `rows_deleted_per_second` and aggregate totals.
