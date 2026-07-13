# Patroni Operational Command Reference

## Configuration Used in Examples

```bash
export PATRONI_CONFIG="/etc/patroni/patroni.yml"
export PATRONI_CLUSTER="postgresql-ha"
```

The `-c` option tells `patronictl` which Patroni configuration file to use.

## Check Patroni Version

```bash
patroni --version
```

```bash
patronictl version
```

## View Cluster Members

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  list "$PATRONI_CLUSTER"
```

Typical output includes:

- Member name
- Host address
- Role
- PostgreSQL state
- Timeline
- Replication lag
- Pending restart status

Watch the cluster continuously:

```bash
watch -n 2 \
  patronictl \
  -c "$PATRONI_CONFIG" \
  list "$PATRONI_CLUSTER"
```

## View Replication Topology

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  topology "$PATRONI_CLUSTER"
```

This displays the current primary and replica hierarchy.

## View Failover History

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  history "$PATRONI_CLUSTER"
```

The history includes PostgreSQL timeline changes caused by promotions.

## View Dynamic Cluster Configuration

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  show-config "$PATRONI_CLUSTER"
```

This reads the dynamic configuration stored in the distributed configuration store.

Values under `bootstrap.dcs` are used during initial cluster creation. Later cluster-wide changes should be made using the dynamic configuration.

## Edit Dynamic Configuration

Open the configuration in an interactive editor:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  edit-config "$PATRONI_CLUSTER"
```

Update one PostgreSQL parameter:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  edit-config "$PATRONI_CLUSTER" \
  --pg max_connections="250"
```

Update Patroni timing settings:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  edit-config "$PATRONI_CLUSTER" \
  --set loop_wait="15" \
  --set ttl="45"
```

Review the proposed changes before confirming them.

## Planned Switchover

A switchover is used when the cluster is healthy and leadership should be moved deliberately.

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  switchover "$PATRONI_CLUSTER" \
  --leader patroni-node-1 \
  --candidate patroni-node-2
```

Non-interactive form:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  switchover "$PATRONI_CLUSTER" \
  --leader patroni-node-1 \
  --candidate patroni-node-2 \
  --force
```

Before performing a switchover, verify:

- The candidate replica is healthy
- Replication is streaming
- Replication lag is acceptable
- The application can reconnect
- No long-running transaction depends on the current primary

## Manual Failover

A failover is normally used when the cluster is unhealthy or no valid primary exists.

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  failover "$PATRONI_CLUSTER" \
  --candidate patroni-node-2
```

Non-interactive form:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  failover "$PATRONI_CLUSTER" \
  --candidate patroni-node-2 \
  --force
```

A failover can cause data loss when the promoted replica has not received all WAL records from the former primary.

## Reinitialize a Replica

Rebuild an unhealthy replica from the current cluster:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  reinit "$PATRONI_CLUSTER" \
  patroni-node-3
```

Wait until the operation finishes:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  reinit "$PATRONI_CLUSTER" \
  patroni-node-3 \
  --wait
```

Non-interactive form:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  reinit "$PATRONI_CLUSTER" \
  patroni-node-3 \
  --wait \
  --force
```

Reinitialization replaces the replica's PostgreSQL data directory. It must not be used against the active primary.

## Restart PostgreSQL Through Patroni

Restart one member:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  restart "$PATRONI_CLUSTER" \
  patroni-node-2
```

Restart members requiring a pending restart:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  restart "$PATRONI_CLUSTER" \
  --pending
```

A rolling restart should normally restart replicas before the primary.

## Reload Patroni Configuration

Reload one member:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  reload "$PATRONI_CLUSTER" \
  patroni-node-2
```

A reload applies configuration changes that do not require a PostgreSQL restart.

## Pause Cluster Automation

Pause Patroni automatic cluster management during controlled maintenance:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  pause "$PATRONI_CLUSTER" \
  --wait
```

Resume cluster management:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  resume "$PATRONI_CLUSTER" \
  --wait
```

Pause mode should not be treated as a replacement for operational planning or fencing.

## Query PostgreSQL Through Patroni

Run a query against the current primary:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  query "$PATRONI_CLUSTER" \
  --role primary \
  --username postgres \
  --command "SELECT pg_is_in_recovery();"
```

Run a query against a replica:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  query "$PATRONI_CLUSTER" \
  --role replica \
  --username postgres \
  --command "SELECT pg_is_in_recovery();"
```

Expected result:

```text
Primary: false
Replica: true
```

## Patroni REST API Checks

Check general node status:

```bash
curl \
  --cacert /etc/patroni/tls/ca.crt \
  https://10.20.0.11:8008/
```

Check whether a node is the primary:

```bash
curl \
  --silent \
  --output /dev/null \
  --write-out "%{http_code}\n" \
  https://10.20.0.11:8008/primary
```

Check whether a node is an eligible replica:

```bash
curl \
  --silent \
  --output /dev/null \
  --write-out "%{http_code}\n" \
  https://10.20.0.12:8008/replica
```

A successful role-aware health check returns:

```text
200
```

A node with the wrong role or an unhealthy state returns a non-success status.

## Inspect Patroni Service Logs

Using systemd:

```bash
sudo systemctl status patroni
```

```bash
sudo journalctl \
  -u patroni \
  --since "30 minutes ago"
```

Follow logs continuously:

```bash
sudo journalctl \
  -u patroni \
  -f
```

## Inspect Patroni Process State

```bash
pgrep -af patroni
```

```bash
sudo ss \
  -lntp |
  grep -E '5432|8008'
```

Expected ports:

```text
5432 - PostgreSQL
8008 - Patroni REST API
```

## Important Operational Checks

Before failover or switchover:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  list "$PATRONI_CLUSTER"
```

Confirm:

- Exactly one primary exists
- Replicas are in streaming state
- Replication lag is acceptable
- All nodes are on compatible timelines
- etcd quorum is healthy
- HAProxy health checks are passing
- Application retry behavior is understood

After leadership changes:

```bash
patronictl \
  -c "$PATRONI_CONFIG" \
  topology "$PATRONI_CLUSTER"
```

Verify:

- The intended candidate became primary
- The former primary is stopped or rejoined as a replica
- HAProxy routes writes to the new primary
- Replicas follow the new timeline
- Application connections recover successfully

## Important Interview Points

- `patronictl list` displays cluster health and member roles.
- `patronictl topology` shows the replication hierarchy.
- `show-config` displays dynamic configuration stored in the DCS.
- `edit-config` changes cluster-wide dynamic settings.
- Switchover is planned and normally used on a healthy cluster.
- Failover is used when the cluster is unhealthy or the leader is unavailable.
- Reinitialization rebuilds a replica and replaces its local database data.
- Restart and reload are different operations.
- Existing database sessions are normally interrupted during leadership changes.
- Replication lag must be checked before promoting a replica.
- Patroni REST endpoints provide role-aware load-balancer health checks.
