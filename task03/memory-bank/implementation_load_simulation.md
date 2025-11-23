# Implementation – Phase 3: Load Simulation

## 4. Ongoing Application Load Simulator

4.1 **Load simulation goals**
- Emulate a system continuously inserting new records while cleanup is running.
- Optionally add read and update queries to capture latency impact and lock contention.

4.2 **Implementation: `db-traffic.sh`**
- Create `task03/db-traffic.sh` that:
  - Sources the `.env` file for connection details.
  - Runs in a loop (until stopped) inserting rows into all tables or a selected subset.
  - Uses `ts = NOW()` for new records.
  - Generates random `name` and `data` values.

4.3 **Load characteristics**
- Make insertion rate configurable:
  - Environment variables or parameters (e.g. `ROWS_PER_SECOND`, `TABLE_SET`).
- Optionally run separate background loops for:
  - Writes: continuous `INSERT` into each table.
  - Reads: repeated `SELECT` queries like:
    - `SELECT * FROM <table> WHERE ts >= NOW() - INTERVAL 5 MINUTE ORDER BY ts DESC LIMIT 10;`
  - Optional `UPDATE` queries updating `data` or `name` for recent rows.

4.4 **Usage pattern**
- For each experiment run:
  - Start `db-traffic.sh` in the background to simulate concurrent activity.
  - Then invoke the cleanup script (`db-cleanup.sh`) for the chosen method(s).
