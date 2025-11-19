# Implementation – Phase 2: Data Generation & Load

## 3. Data Generation and Initial Population

3.1 **Row volume and distribution**
- Insert **100,000 rows** into each table for the base scenario.
- Keep scripts flexible to scale up (e.g. to millions of rows) when needed.
- Timestamp `ts` distribution:
  - Uniform or random between `NOW() - INTERVAL 20 DAY` and `NOW()`.
  - Ensures that a significant portion (roughly half) of the rows are older than 10 days.
- `name`:
  - Random 10-character ASCII string (A–Z or alphanumeric).
- `data`:
  - Random integer between `0` and `10,000,000`.

3.2 **Data generator implementation**
- Add a shell script `task03/db-load.sh` that:
  - Sources the `.env` file for connection details.
  - Takes optional arguments like `--rows 100000` and `--db cleanup_bench`.
  - Generates synthetic data and loads it into each test table.

3.3 **Loading strategy**
- Prefer a fast bulk-loading approach:
  - Generate a CSV file (e.g. `task03/data/events_seed.csv`) with the required columns (excluding `id`, which is auto-generated).
  - Use `LOAD DATA LOCAL INFILE` (or `mysqlimport`) into each table.
- To ensure fair comparison:
  - Reuse the same CSV for all tables so they start with identical data.

3.4 **`db-load.sh` script behavior (pseudoflow)**
- Validate connection.
- Generate (or reuse) a CSV with N rows.
- For each table (`cleanup_partitioned`, `cleanup_truncate`, `cleanup_copy`, `cleanup_batch`):
  - Truncate/clean the table if necessary.
  - `LOAD DATA` from the CSV.
- Print summary of inserted rows per table.
