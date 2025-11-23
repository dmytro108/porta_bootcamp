# Implementation – Phase 7: Documentation & Usage

## 9. Cron Integration (Optional/Production-like Usage)

9.1 **Existing crontab entry**
- Current `crontab` file contains:
  - `59 23 */10 * * mysql /home/mysql/db-cleanup.sh`
- Decide whether to:
  - Keep this as a production-style example only, or
  - Actually use it for periodic automatic cleanup once tests are stable.

9.2 **Cron-safe behavior**
- Ensure `db-cleanup.sh` has sensible defaults when run without arguments, e.g.:
  - Default `--method batch` with a conservative `--batch-size`.
- Document that experiments should typically be run manually, not via cron.

## 10. Documentation and Usage

10.1 **README updates**
- Extend `task03/README.md` to describe:
  - How to initialize the database:
    - `mysql < task03/db-schema.sql`.
  - How to populate test data:
    - `./db-load.sh --rows 100000`.
  - How to start background traffic:
    - `./db-traffic.sh &`.
  - How to run each cleanup method individually or all together using `db-cleanup.sh`.

10.2 **Example commands**
- Run all methods sequentially:
  - `./db-cleanup.sh --method all`.
- Run only batch delete with a specific batch size:
  - `./db-cleanup.sh --method batch --batch-size 5000`.
- Run only partition-based cleanup:
  - `./db-cleanup.sh --method partition`.

10.3 **Interpreting results**
- Describe how to use logs in `task03/results/` to compare methods:
  - Compare `rows_deleted_per_second` and total transaction time.
  - Observe impact on:
    - Query latency during cleanup.
    - InnoDB history list length and purge behavior.
    - Replication lag (`Seconds_Behind_Source`).
    - Table sizes and binlog growth.
- Encourage running multiple trials to account for variance and caching effects.
