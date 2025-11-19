# Task 03 – Implementation Index

This folder contains the detailed implementation specification for Task 03, split into separate documents for easier maintenance.

## High-level phases

- **Phase 1 – Environment & Schema**: connection configuration, replication assumptions, and test table schema design.
- **Phase 2 – Data Generation & Load**: synthetic data model, CSV generation, and bulk load process.
- **Phase 3 – Load Simulation**: background write/read workload to run during cleanups.
- **Phase 4 – Metrics & Instrumentation**: what and how to measure for each method.
- **Phase 5 – Cleanup Methods**: exact SQL patterns for each cleanup strategy.
- **Phase 6 – Orchestration & Automation**: `db-cleanup.sh`, helper scripts, and cron integration.
- **Phase 7 – Documentation & Usage**: how to run experiments and interpret results.

## Documents

- `implementation_env_schema.md` – environment, connection settings, replication setup, and SQL schema design (tables, indexes, partitioning, maintenance of partitions).
- `implementation_data_load.md` – data generation strategy, `db-load.sh` behavior, CSV format, and bulk loading approach.
- `implementation_load_simulation.md` – `db-traffic.sh` design, workload characteristics, and usage patterns during tests.
- `implementation_metrics.md` – MySQL/replication metrics, table/binlog size tracking, latency/locking measurements, and logging format.
- `implementation_cleanup_methods.md` – per-method SQL flows for partition drop/truncate, full truncate, copy-to-new-table, and batch delete.
- `implementation_orchestration.md` – `db-cleanup.sh` orchestration, helper functions, optional SQL helpers, and cron integration.
- `implementation_usage.md` – updates required in `README.md`, example commands, and how to compare and interpret results.

Each file is self-contained but assumes the shared context defined in `task03/README.md` and the common database name `cleanup_bench`.
