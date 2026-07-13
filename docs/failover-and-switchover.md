# PostgreSQL HA Failover and Switchover Runbook

## Purpose

This runbook describes the operational procedures for planned switchover, unplanned failover, post-promotion validation, and recovery of a former PostgreSQL primary in a Patroni-managed cluster.

## Cluster Assumptions

- Three PostgreSQL nodes managed by Patroni
- Three-member etcd cluster
- HAProxy read/write endpoint on port `5432`
- HAProxy read-only endpoint on port `5433`
- Patroni REST API on port `8008`
- PostgreSQL streaming replication enabled
- TLS enabled for PostgreSQL and etcd communication

## Node Layout

| Component | Address | Purpose |
|---|---|---|
| HAProxy | `10.20.0.10` | Stable database endpoint |
| Patroni Node 1 | `10.20.0.11` | PostgreSQL cluster member |
| Patroni Node 2 | `10.20.0.12` | PostgreSQL cluster member |
| Patroni Node 3 | `10.20.0.13` | PostgreSQL cluster member |
| etcd Member 1 | `10.20.0.21` | DCS quorum member |
| etcd Member 2 | `10.20.0.22` | DCS quorum member |
| etcd Member 3 | `10.20.0.23` | DCS quorum member |

## Pre-Change Health Checks

Before performing a switchover or failover, confirm that the cluster, replication, routing, and distributed configuration store are healthy.

### 1. Check Patroni Cluster State

    patronictl \
      -c /etc/patroni/patroni.yml \
      list postgresql-ha

Confirm:

- Exactly one member has the `Leader` role.
- Replica members show a running or streaming state.
- Replication lag is within the accepted threshold.
- No unexpected pending restart is reported.

### 2. Check Replication Topology

    patronictl \
      -c /etc/patroni/patroni.yml \
      topology postgresql-ha

The topology should show one primary with the expected replicas following it.

### 3. Check etcd Quorum Health

    ETCDCTL_API=3 etcdctl \
      --endpoints="https://10.20.0.21:2379,https://10.20.0.22:2379,https://10.20.0.23:2379" \
      --cacert=/etc/etcd/tls/ca.crt \
      --cert=/etc/etcd/tls/client.crt \
      --key=/etc/etcd/tls/client.key \
      endpoint health

At least two of the three etcd members must be available to retain quorum.

### 4. Confirm the PostgreSQL Role

Run on the node being inspected:

    SELECT
        inet_server_addr() AS server_address,
        CASE
            WHEN pg_is_in_recovery() THEN 'replica'
            ELSE 'primary'
        END AS node_role;

Confirm that only one node reports the `primary` role.

### 5. Check Replication from the Primary

Run on the current primary:

    SELECT
        application_name,
        client_addr,
        state,
        sync_state,
        replay_lag
    FROM pg_stat_replication
    ORDER BY application_name;

Confirm that:

- All expected replicas are connected.
- The replication state is `streaming`.
- Replication lag is acceptable.
- The synchronization state matches the intended design.

### 6. Check HAProxy Role Routing

Check each Patroni node’s primary endpoint:

    for host in 10.20.0.11 10.20.0.12 10.20.0.13; do
      printf "%s: " "$host"
      curl \
        --silent \
        --output /dev/null \
        --write-out "%{http_code}\n" \
        "http://${host}:8008/primary"
    done

Exactly one node should return HTTP status `200`.

Check the stable write endpoint:

    pg_isready \
      --host=10.20.0.10 \
      --port=5432

### Pre-Change Decision

Do not continue with a planned switchover when:

- etcd quorum is unavailable.
- More than one node reports primary status.
- No healthy promotion candidate exists.
- Replication lag exceeds the approved threshold.
- HAProxy health checks do not reflect Patroni roles.
- Backup or WAL-archive health is uncertain.

## Planned Switchover

A switchover deliberately transfers the PostgreSQL primary role from a healthy leader to a healthy replica.

Common reasons include:

- Operating-system maintenance
- PostgreSQL configuration changes
- Infrastructure maintenance
- Controlled availability testing
- Moving leadership to a preferred node

### 1. Record the Current State

    date -u

    patronictl \
      -c /etc/patroni/patroni.yml \
      list postgresql-ha

    patronictl \
      -c /etc/patroni/patroni.yml \
      topology postgresql-ha

Record:

- Current leader
- Selected candidate
- PostgreSQL timeline
- Replica lag
- etcd health
- Change or incident reference

### 2. Confirm the Candidate

The candidate should:

- Be a healthy Patroni member
- Be in the expected replica state
- Have acceptable replication lag
- Not have the `nofailover` tag
- Be able to connect to etcd
- Have sufficient CPU, memory, storage, and network capacity

Example candidate check:

    patronictl \
      -c /etc/patroni/patroni.yml \
      list postgresql-ha

For this example:

    Current leader: patroni-node-1
    Candidate:      patroni-node-2

### 3. Perform the Switchover

Run:

    patronictl \
      -c /etc/patroni/patroni.yml \
      switchover postgresql-ha \
      --leader patroni-node-1 \
      --candidate patroni-node-2

Review the displayed cluster information and confirm the operation when prompted.

Avoid `--force` during normal operations because the interactive confirmation provides an additional safety check.

### 4. Confirm the New Leader

    patronictl \
      -c /etc/patroni/patroni.yml \
      list postgresql-ha

    patronictl \
      -c /etc/patroni/patroni.yml \
      topology postgresql-ha

Expected state:

- `patroni-node-2` is the new leader.
- `patroni-node-1` rejoins as a replica.
- `patroni-node-3` remains a replica.
- Exactly one leader exists.

### 5. Validate the HAProxy Write Endpoint

    psql \
      --host=10.20.0.10 \
      --port=5432 \
      --username=postgres \
      --dbname=postgres \
      --command="SELECT inet_server_addr(), pg_is_in_recovery();"

Expected result:

    pg_is_in_recovery = false

The returned server address should match the new primary.

### 6. Validate the Read-Only Endpoint

    psql \
      --host=10.20.0.10 \
      --port=5433 \
      --username=postgres \
      --dbname=postgres \
      --command="SELECT inet_server_addr(), pg_is_in_recovery();"

Expected result:

    pg_is_in_recovery = true

### 7. Confirm Replication After Switchover

Run on the new primary:

    SELECT
        application_name,
        client_addr,
        state,
        sync_state,
        replay_lag
    FROM pg_stat_replication
    ORDER BY application_name;

Confirm:

- Both expected replicas reconnect.
- Replication returns to `streaming`.
- Lag returns to an acceptable level.
- The former primary is no longer writable.
- The application reconnects through HAProxy.

### Switchover Success Criteria

The switchover is successful when:

- The selected candidate becomes primary.
- Exactly one primary exists.
- HAProxy routes new writes to the new primary.
- Replica connections recover.
- The former primary rejoins safely as a replica.
- Application errors and reconnect time remain within the accepted RTO.

## Unplanned Failover

Failover is used when the current PostgreSQL primary is unavailable or the cluster no longer has a valid leader.

Possible triggers include:

- PostgreSQL process failure
- Patroni service failure
- Compute Engine instance failure
- Operating-system failure
- Primary-zone failure
- Loss of the Patroni leader lock
- Network isolation of the current primary

### 1. Confirm the Failure

Check cluster state:

    patronictl \
      -c /etc/patroni/patroni.yml \
      list postgresql-ha

Check topology:

    patronictl \
      -c /etc/patroni/patroni.yml \
      topology postgresql-ha

Check the former primary:

    sudo systemctl status patroni

    sudo journalctl \
      -u patroni \
      --since "15 minutes ago"

Confirm that the issue is not only an HAProxy or application connectivity failure.

### 2. Confirm etcd Quorum

    ETCDCTL_API=3 etcdctl \
      --endpoints="https://10.20.0.21:2379,https://10.20.0.22:2379,https://10.20.0.23:2379" \
      --cacert=/etc/etcd/tls/ca.crt \
      --cert=/etc/etcd/tls/client.crt \
      --key=/etc/etcd/tls/client.key \
      endpoint health

At least two of the three etcd members must be healthy before Patroni can safely coordinate a new leader election.

Do not force a promotion while the former primary may still be accepting writes.

### 3. Review Available Candidates

    patronictl \
      -c /etc/patroni/patroni.yml \
      list postgresql-ha

Select a candidate that:

- Is running and reachable
- Has the lowest acceptable replication lag
- Is on a compatible PostgreSQL timeline
- Does not have `nofailover: true`
- Can communicate with etcd
- Has sufficient infrastructure capacity

### 4. Perform the Manual Failover

Example:

    patronictl \
      -c /etc/patroni/patroni.yml \
      failover postgresql-ha \
      --candidate patroni-node-2

Review the displayed cluster information before confirming.

Use `--force` only in an automated or carefully controlled recovery workflow:

    patronictl \
      -c /etc/patroni/patroni.yml \
      failover postgresql-ha \
      --candidate patroni-node-2 \
      --force

### 5. Confirm the New Leader

    patronictl \
      -c /etc/patroni/patroni.yml \
      list postgresql-ha

    patronictl \
      -c /etc/patroni/patroni.yml \
      topology postgresql-ha

Confirm:

- Exactly one node is leader.
- The selected candidate became primary.
- Remaining healthy nodes follow the new primary.
- The former primary is stopped, isolated, or rejoining as a replica.

### 6. Validate the Write Endpoint

    psql \
      --host=10.20.0.10 \
      --port=5432 \
      --username=postgres \
      --dbname=postgres \
      --command="SELECT inet_server_addr(), pg_is_in_recovery();"

Expected:

    pg_is_in_recovery = false

### 7. Validate Replication

Run on the new primary:

    SELECT
        application_name,
        client_addr,
        state,
        sync_state,
        replay_lag
    FROM pg_stat_replication
    ORDER BY application_name;

Confirm that healthy replicas reconnect and return to the `streaming` state.

### Failover Success Criteria

Failover is successful when:

- Exactly one writable primary exists.
- HAProxy routes new write connections to the new primary.
- etcd quorum remains available.
- At least one replica follows the new primary.
- The former primary cannot accept independent writes.
- Application connectivity recovers within the accepted RTO.
- Any potential data loss is measured and documented.

### Critical Safety Warning

Never manually start or promote the former primary before confirming that it is following the new timeline.

An uncontrolled return of the former primary can create:

- Split brain
- Divergent PostgreSQL timelines
- Conflicting transactions
- Application data inconsistency

## Former Primary Recovery

After failover, the former primary may have diverged from the new PostgreSQL timeline. It must not return as an independent writable node.

First, inspect the cluster:

    patronictl \
      -c /etc/patroni/patroni.yml \
      list postgresql-ha

When `use_pg_rewind` is enabled, Patroni can attempt to synchronize the former primary with the new leader:

    postgresql:
      use_pg_rewind: true

When rewind is not possible, rebuild the former primary as a replica:

    patronictl \
      -c /etc/patroni/patroni.yml \
      reinit postgresql-ha \
      patroni-node-1 \
      --wait

After recovery, confirm:

- The former primary has rejoined as a replica.
- It reports `pg_is_in_recovery() = true`.
- Replication state is `streaming`.
- Replication lag returns to an acceptable level.
- Exactly one writable primary exists.

## Final Operational Checklist

- Exactly one PostgreSQL primary exists.
- etcd retains quorum.
- HAProxy routes writes only to the current primary.
- Healthy replicas receive read-only traffic.
- Replication is streaming.
- The former primary has safely rejoined.
- Application connectivity has recovered.
- Any RTO or RPO impact has been documented.
