# PostgreSQL HA and Replication Command Reference

## Connect to PostgreSQL

Connect directly to a PostgreSQL node:

```bash
psql \
  --host=10.20.0.11 \
  --port=5432 \
  --username=postgres \
  --dbname=postgres
```

Connect through the HAProxy read/write endpoint:

```bash
psql \
  --host=10.20.0.10 \
  --port=5432 \
  --username=postgres \
  --dbname=postgres
```

Connect through the optional read-only endpoint:

```bash
psql \
  --host=10.20.0.10 \
  --port=5433 \
  --username=postgres \
  --dbname=postgres
```

Require TLS:

```bash
psql \
  "host=10.20.0.10 port=5432 dbname=postgres user=postgres sslmode=verify-full sslrootcert=/path/to/ca.crt"
```

## Display Connection Information

Inside `psql`:

```sql
\conninfo
```

Show server address and port:

```sql
SELECT
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    current_database() AS database_name,
    current_user AS connected_user;
```

Show PostgreSQL version:

```sql
SELECT version();
```

## Identify Primary and Replica Roles

Run on any PostgreSQL node:

```sql
SELECT pg_is_in_recovery();
```

Expected results:

```text
false = primary
true  = replica
```

Display a readable node role:

```sql
SELECT
    CASE
        WHEN pg_is_in_recovery() THEN 'replica'
        ELSE 'primary'
    END AS node_role;
```

## Primary Replication Status

Run this query on the current primary:

```sql
SELECT
    pid,
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag
FROM pg_stat_replication
ORDER BY application_name;
```

Important columns:

- `state` commonly shows whether the replica is streaming.
- `sync_state` shows whether the replica is asynchronous, synchronous, or a potential synchronous candidate.
- `sent_lsn` is the WAL position sent by the primary.
- `write_lsn` is the WAL position written on the replica.
- `flush_lsn` is the WAL position flushed to durable storage.
- `replay_lsn` is the WAL position replayed by the replica.
- Lag interval columns provide recent timing observations and are not permanent guarantees of data-loss exposure.

Count connected replicas:

```sql
SELECT count(*) AS connected_replicas
FROM pg_stat_replication;
```

Display replication state by replica:

```sql
SELECT
    application_name,
    client_addr,
    state,
    sync_state
FROM pg_stat_replication
ORDER BY application_name;
```

## Replication Lag in Bytes

Run on the primary:

```sql
SELECT
    application_name,
    client_addr,
    pg_size_pretty(
        pg_wal_lsn_diff(
            pg_current_wal_lsn(),
            replay_lsn
        )
    ) AS replay_lag
FROM pg_stat_replication
ORDER BY application_name;
```

Display sent, written, flushed, and replayed lag:

```sql
SELECT
    application_name,
    pg_size_pretty(
        pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)
    ) AS send_lag,
    pg_size_pretty(
        pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn)
    ) AS write_lag,
    pg_size_pretty(
        pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)
    ) AS flush_lag,
    pg_size_pretty(
        pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)
    ) AS replay_lag
FROM pg_stat_replication;
```

A `NULL` LSN can occur when the corresponding replication stage has not yet reported a position.

## Standby WAL Receiver Status

Run on a replica:

```sql
SELECT
    pid,
    status,
    sender_host,
    sender_port,
    slot_name,
    written_lsn,
    flushed_lsn,
    latest_end_lsn,
    latest_end_time
FROM pg_stat_wal_receiver;
```

No returned row normally means that no WAL receiver process is currently active.

## Standby Replay Position

Run on a replica:

```sql
SELECT
    pg_last_wal_receive_lsn() AS received_lsn,
    pg_last_wal_replay_lsn() AS replayed_lsn,
    pg_last_xact_replay_timestamp() AS last_replayed_transaction;
```

Calculate WAL received but not yet replayed:

```sql
SELECT pg_size_pretty(
    pg_wal_lsn_diff(
        pg_last_wal_receive_lsn(),
        pg_last_wal_replay_lsn()
    )
) AS received_not_replayed;
```

Estimate time since the last replayed transaction:

```sql
SELECT
    now() - pg_last_xact_replay_timestamp()
        AS time_since_last_replay;
```

This value can be misleading on an idle database because no new transactions may exist to replay.

## Current WAL Position

Run on the primary:

```sql
SELECT pg_current_wal_lsn();
```

Display the current WAL file:

```sql
SELECT pg_walfile_name(pg_current_wal_lsn());
```

Force a WAL segment switch:

```sql
SELECT pg_switch_wal();
```

A manual WAL switch can be useful when testing archiving but should not be executed repeatedly without an operational reason.

## Replication Slots

List replication slots:

```sql
SELECT
    slot_name,
    slot_type,
    active,
    active_pid,
    restart_lsn,
    confirmed_flush_lsn,
    wal_status
FROM pg_replication_slots
ORDER BY slot_name;
```

Display inactive physical slots:

```sql
SELECT
    slot_name,
    active,
    restart_lsn
FROM pg_replication_slots
WHERE slot_type = 'physical'
  AND active = false;
```

An abandoned replication slot can retain WAL files and consume disk space.

Estimate retained WAL by slot:

```sql
SELECT
    slot_name,
    active,
    pg_size_pretty(
        pg_wal_lsn_diff(
            pg_current_wal_lsn(),
            restart_lsn
        )
    ) AS retained_wal
FROM pg_replication_slots
WHERE restart_lsn IS NOT NULL
ORDER BY slot_name;
```

Patroni can manage physical replication slots when:

```yaml
postgresql:
  use_slots: true
```

## Replication Configuration

Inspect important replication settings:

```sql
SELECT
    name,
    setting,
    unit,
    context,
    pending_restart
FROM pg_settings
WHERE name IN (
    'wal_level',
    'max_wal_senders',
    'max_replication_slots',
    'wal_keep_size',
    'hot_standby',
    'synchronous_commit',
    'synchronous_standby_names',
    'max_slot_wal_keep_size'
)
ORDER BY name;
```

Show archive configuration:

```sql
SELECT
    name,
    setting
FROM pg_settings
WHERE name IN (
    'archive_mode',
    'archive_command',
    'archive_timeout'
)
ORDER BY name;
```

## Synchronous Replication

Show the configured synchronous standby policy:

```sql
SHOW synchronous_standby_names;
```

Show transaction commit behavior:

```sql
SHOW synchronous_commit;
```

Inspect each replica's synchronization state:

```sql
SELECT
    application_name,
    state,
    sync_state,
    sync_priority
FROM pg_stat_replication
ORDER BY sync_priority, application_name;
```

Common `sync_state` values include:

```text
async
potential
sync
quorum
```

With Patroni, cluster-wide synchronous-mode changes should normally be made through Patroni dynamic configuration rather than editing PostgreSQL configuration independently on one node.

## Timeline and Control Information

Show whether recovery is active:

```sql
SELECT pg_is_in_recovery();
```

On a replica, show whether WAL replay is paused:

```sql
SELECT pg_is_wal_replay_paused();
```

Pause WAL replay for controlled testing:

```sql
SELECT pg_wal_replay_pause();
```

Resume WAL replay:

```sql
SELECT pg_wal_replay_resume();
```

Pausing replay intentionally creates lag and must only be performed during controlled testing.

Inspect control data from the operating-system shell:

```bash
sudo -u postgres \
  pg_controldata /var/lib/postgresql/16/main
```

Useful fields include:

```text
Database cluster state
Latest checkpoint location
Latest checkpoint timeline
Minimum recovery ending location
Data page checksum version
```

## Check Data Checksums

From SQL on supported PostgreSQL versions:

```sql
SHOW data_checksums;
```

From the server shell while considering the required PostgreSQL state:

```bash
sudo -u postgres \
  pg_checksums \
  --check \
  --pgdata=/var/lib/postgresql/16/main
```

## Active Connections

Display connection counts by state:

```sql
SELECT
    state,
    count(*) AS connections
FROM pg_stat_activity
GROUP BY state
ORDER BY state;
```

Display connections by database and user:

```sql
SELECT
    datname,
    usename,
    count(*) AS connections
FROM pg_stat_activity
GROUP BY datname, usename
ORDER BY connections DESC;
```

Show connection usage against the configured limit:

```sql
SELECT
    current_setting('max_connections')::integer
        AS max_connections,
    count(*) AS current_connections
FROM pg_stat_activity;
```

## Long-Running Queries

```sql
SELECT
    pid,
    usename,
    datname,
    client_addr,
    state,
    now() - query_start AS query_duration,
    wait_event_type,
    wait_event,
    query
FROM pg_stat_activity
WHERE state <> 'idle'
  AND pid <> pg_backend_pid()
ORDER BY query_start;
```

Show transactions open for more than five minutes:

```sql
SELECT
    pid,
    usename,
    datname,
    now() - xact_start AS transaction_duration,
    state,
    query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND now() - xact_start > interval '5 minutes'
ORDER BY xact_start;
```

Long-running transactions can delay vacuum cleanup and increase table bloat.

## Blocking and Blocked Sessions

```sql
SELECT
    blocked.pid AS blocked_pid,
    blocked.usename AS blocked_user,
    blocking.pid AS blocking_pid,
    blocking.usename AS blocking_user,
    blocked.query AS blocked_query,
    blocking.query AS blocking_query
FROM pg_stat_activity AS blocked
CROSS JOIN LATERAL
    unnest(pg_blocking_pids(blocked.pid))
        AS blocking_pid
JOIN pg_stat_activity AS blocking
    ON blocking.pid = blocking_pid;
```

Show waiting sessions:

```sql
SELECT
    pid,
    usename,
    wait_event_type,
    wait_event,
    query
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
ORDER BY query_start;
```

## Cancel or Terminate a Backend

Attempt to cancel the current query without disconnecting the session:

```sql
SELECT pg_cancel_backend(PID);
```

Terminate the complete database session:

```sql
SELECT pg_terminate_backend(PID);
```

Terminating sessions can roll back transactions and interrupt applications. Identify the session carefully before using these functions.

## Database and Table Size

Database sizes:

```sql
SELECT
    datname,
    pg_size_pretty(pg_database_size(datname)) AS database_size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;
```

Largest tables:

```sql
SELECT
    schemaname,
    relname,
    pg_size_pretty(
        pg_total_relation_size(
            quote_ident(schemaname) || '.' || quote_ident(relname)
        )
    ) AS total_size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(
    quote_ident(schemaname) || '.' || quote_ident(relname)
) DESC
LIMIT 20;
```

## WAL Statistics

```sql
SELECT
    wal_records,
    wal_fpi,
    wal_bytes,
    wal_buffers_full,
    wal_write,
    wal_sync,
    stats_reset
FROM pg_stat_wal;
```

Reset shared statistics only during controlled testing:

```sql
SELECT pg_stat_reset_shared('wal');
```

## Checkpoint Statistics

```sql
SELECT *
FROM pg_stat_bgwriter;
```

Review checkpoint-related settings:

```sql
SELECT
    name,
    setting,
    unit
FROM pg_settings
WHERE name IN (
    'checkpoint_timeout',
    'checkpoint_completion_target',
    'max_wal_size',
    'min_wal_size'
)
ORDER BY name;
```

## Autovacuum Status

Show active vacuum operations:

```sql
SELECT
    pid,
    datname,
    relid::regclass AS table_name,
    phase,
    heap_blks_total,
    heap_blks_scanned,
    heap_blks_vacuumed
FROM pg_stat_progress_vacuum;
```

Tables with the highest number of dead tuples:

```sql
SELECT
    schemaname,
    relname,
    n_live_tup,
    n_dead_tup,
    last_autovacuum,
    autovacuum_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 20;
```

## Reload PostgreSQL Configuration

Check whether configuration files contain syntax errors:

```sql
SELECT *
FROM pg_file_settings
WHERE error IS NOT NULL;
```

Reload PostgreSQL configuration:

```sql
SELECT pg_reload_conf();
```

Inspect settings waiting for a restart:

```sql
SELECT
    name,
    setting,
    pending_restart
FROM pg_settings
WHERE pending_restart = true
ORDER BY name;
```

With Patroni, restart and reload operations should normally be coordinated using `patronictl`.

## Authentication Rules

Display the parsed `pg_hba.conf` rules:

```sql
SELECT
    line_number,
    type,
    database,
    user_name,
    address,
    auth_method,
    error
FROM pg_hba_file_rules
ORDER BY line_number;
```

Display invalid rules:

```sql
SELECT *
FROM pg_hba_file_rules
WHERE error IS NOT NULL;
```

The Patroni configuration template uses:

```text
hostssl
scram-sha-256
```

for encrypted, password-authenticated client and replication connections.

## Base Backup

Create a physical base backup from the primary:

```bash
pg_basebackup \
  --host=10.20.0.11 \
  --port=5432 \
  --username=replicator \
  --pgdata=/var/lib/postgresql/16/main \
  --format=plain \
  --wal-method=stream \
  --checkpoint=fast \
  --progress \
  --write-recovery-conf
```

Create a base backup using a named replication slot:

```bash
pg_basebackup \
  --host=10.20.0.11 \
  --username=replicator \
  --pgdata=/var/lib/postgresql/16/main \
  --wal-method=stream \
  --slot=patroni_node_3 \
  --create-slot \
  --write-recovery-conf \
  --progress
```

Before using the target directory, verify that it is empty and that ownership and permissions are correct.

Patroni normally automates replica creation through its configured replica creation method.

## Verify a Base Backup

For a backup containing a backup manifest:

```bash
pg_verifybackup /path/to/basebackup
```

Backup verification does not replace a complete restoration test.

## Rewind a Former Primary

After failover, the old primary can have a timeline that diverges from the new primary.

A conceptual `pg_rewind` operation is:

```bash
pg_rewind \
  --target-pgdata=/var/lib/postgresql/16/main \
  --source-server="host=10.20.0.12 port=5432 dbname=postgres user=rewind_user sslmode=verify-full"
```

Requirements commonly include:

- The target PostgreSQL server is stopped.
- The target and source originated from the same PostgreSQL cluster.
- Data checksums or `wal_log_hints` were enabled before divergence.
- Required WAL records remain available.
- The rewind user has the required permissions.
- Configuration files are reviewed after the operation.

In this architecture, Patroni can invoke `pg_rewind` when:

```yaml
postgresql:
  use_pg_rewind: true
```

## Manual Promotion

PostgreSQL supports manual standby promotion:

```sql
SELECT pg_promote();
```

Or from the server shell:

```bash
pg_ctl \
  --pgdata=/var/lib/postgresql/16/main \
  promote
```

In a Patroni-managed cluster, do not normally promote PostgreSQL directly.

Use:

```bash
patronictl switchover
```

or:

```bash
patronictl failover
```

Direct promotion bypasses Patroni coordination and can create inconsistent cluster state or split-brain risk.

## PostgreSQL Service Logs

With systemd:

```bash
sudo systemctl status postgresql
```

```bash
sudo journalctl \
  -u postgresql \
  --since "30 minutes ago"
```

When Patroni directly manages the PostgreSQL process, Patroni logs are normally the first place to inspect:

```bash
sudo journalctl \
  -u patroni \
  --since "30 minutes ago"
```

## Operating-System Port Checks

```bash
sudo ss \
  -lntp |
  grep -E '5432|8008'
```

Test PostgreSQL readiness:

```bash
pg_isready \
  --host=10.20.0.11 \
  --port=5432
```

Test the HAProxy write endpoint:

```bash
pg_isready \
  --host=10.20.0.10 \
  --port=5432
```

A successful TCP or `pg_isready` response does not by itself prove that the node is the Patroni primary. Use Patroni role-aware checks as well.

## Suggested Failover Validation

Before failover:

```sql
SELECT pg_is_in_recovery();
```

```sql
SELECT
    application_name,
    state,
    sync_state,
    replay_lsn
FROM pg_stat_replication;
```

After failover:

```sql
SELECT
    inet_server_addr(),
    pg_is_in_recovery(),
    pg_current_wal_lsn();
```

Then confirm:

- The new node reports `pg_is_in_recovery() = false`.
- The old primary no longer accepts writes.
- Replicas follow the new primary.
- HAProxy routes write connections to the new primary.
- Application connections recover.
- Replication slots are healthy.
- No unexpected WAL retention exists.

## Important Interview Points

- `pg_is_in_recovery()` distinguishes a replica from a primary.
- `pg_stat_replication` is queried on the primary.
- `pg_stat_wal_receiver` is queried on a replica.
- `pg_wal_lsn_diff()` calculates the difference between WAL positions.
- Byte lag and time lag measure different aspects of replication delay.
- An idle database can make time-based replay lag appear misleading.
- Replication slots prevent required WAL from being removed but can fill storage if abandoned.
- Synchronous replication reduces data-loss risk but can affect latency and write availability.
- `pg_basebackup` creates a physical base backup and can initialize a standby.
- `pg_rewind` can help return a former primary as a replica after timeline divergence.
- Direct PostgreSQL promotion should normally be avoided when Patroni manages the cluster.
- High availability does not replace backups, WAL archiving, PITR, or restore testing.
