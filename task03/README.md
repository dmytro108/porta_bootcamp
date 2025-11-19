# Task 03: MySQL Cleanup Procedure

## Context:
You have a MySQL 8 server with replication of master-slave scheme. 
Create a cleanup procedure to remove records older than 10 days in a table with millions records (~1M per day).

## Goal: 
Do experiments to find out the fastest possible cleanup method.

## Methods to explore:
  - Method partitioned table `DROP/TRUNCATE PARTITION`
  - Method `TRUNCATE TABLE ...` 
  - Method "Copy to a new table" (`CREATE TABLE ... LIKE ...; INSERT INTO...; RENAME TABLE...; DROP TABLE...;`)
  - Method "Batch `DELETE ... WHERE ... LIMIT`"

## Metrics to measure and evaluate for each method:
 - `rows_deleted_per_second` (`rows_in_batch / time_of_batch`)
 - overall transaction time
 - increase in average query latency (SELECT/UPDATE)
 - increase in the number of blocking conflicts
 - InnoDB state - history list length shows a lag of purge
 - InnoDB state -number of deleted raws: `Innodb_rows_deleted`, `Innodb_row_lock_time`, etc.
 - Replication - `Seconds_Behind_Source` at replics
 - Replication - velocity of the application of `relay log`
 - table size before/after (DATA_LENGTH, INDEX_LENGTH)
 - size of binlog.

## Implementation plan
### SQL schema table with fields:
  - id (autoincrement, primary key)
  - date-time stamp 
  - name string 10 symbols
  - data integer
  id is 

### SQL script to create tables for various cleanup methods

### SQL script to insert 100000 records to each table:
  - id (autoincrement)
  - date-time stamp (generated for dates in between current date ... -20 days)
  - name (generated string 10 ascii symbols)
  - data (generated integer 0...10000000)

### Test scripts
- shell script immitating ongoing updates of all tables with new records which is running while clean up process.
  
- shell script which connects to the MySQL server and cleanups records older than 10 days for each method and gather statistics to evaluate.