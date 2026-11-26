# PostgreSQL

A shared PostgreSQL foundation managed by [CloudNativePG](../../controllers/cloudnative-pg/). It runs one `Cluster` named `postgres` in the `postgres` namespace, with one primary and one synchronous standby on different nodes, and a daily encrypted logical backup to the R2 bucket that Velero also uses.

Consumers connect to `postgres-rw.postgres.svc` on port 5432. Each consumer needs an ingress rule in `network-policy.yaml` and its own role and database, declared in this directory.

## Files

| File | Purpose |
| --- | --- |
| `cluster.yaml` | Two instances, PostgreSQL 18.7 minimal image, `local-path` storage, synchronous replication, the backup role. |
| `pod-monitor.yaml` | Scrapes the exporter on port 9187 of each instance. |
| `network-policy.yaml` | Default deny for every pod in the namespace, with the flows below allowed. |
| `backup-cronjob.yaml` | Daily dump, encryption and upload. |
| `bucket-usage-cronjob.yaml` | Bucket-size warning every six hours. |
| `backup/dump.sh`, `backup/upload.sh`, `backup/bucket-usage.sh` | The job scripts, mounted from a generated ConfigMap. |
| `sealedsecret-backup-*.yaml` | The three encrypted Secrets below. |
| `prometheus-rule.yaml` | Instance count, streaming, replication lag and backup age alerts. |

## Durability model

| Event | Committed data | Writes |
| --- | --- | --- |
| Primary pod killed, standby healthy | No acknowledged commit is lost: a commit returns only after the standby has flushed it. | Pause until the standby is promoted. |
| Standby node drained or down | Commits are acknowledged by the primary alone until the standby returns. A primary loss in that window loses those commits. | Continue. The operator drops the missing standby from the synchronous quorum (`dataDurability: preferred`). |
| Primary node drained | No loss. The primary budget blocks the eviction until the operator switches over to the standby. | Pause during the switchover. |
| Link between the nodes at 10 Mbps | No loss. The standby stays connected and healthy, so commits keep waiting for it. | Continue, but every commit waits for its WAL to cross the slow link; bulk writes are limited to about 1 MB/s. `PostgresReplicationLagHigh` reports replay falling behind. |
| OptiPlex down | No loss. | Stop. The OptiPlex is the only control plane node: without the API, no failover happens, and a primary on the Nitro that can reach neither the API nor the other instance fails its liveness check and restarts. |

`failoverDelay: 0` starts a failover as soon as the primary is unhealthy, so a flapping link between the nodes can trigger one. That is safe for data while replication is synchronous, but the former primary then rejoins through `pg_rewind`.

`podAntiAffinityType: required` keeps one instance per node. With two nodes, an instance whose node is down stays Pending; it cannot move, because its `local-path` volume is bound to that node.

The operator creates only the primary `PodDisruptionBudget` for a two-instance cluster. Draining the node of the standby is never blocked. Draining the node of the primary waits for the switchover. Draining the remaining node while the other is already down is blocked, because it would stop the last copy.

## Storage

The instances use `local-path`, so PostgreSQL replication is the only copy between nodes and no write crosses the link twice. On both nodes the data lives under `/var/mnt/longhorn/local-path`. On the OptiPlex this is the XFS user volume, separate from the EPHEMERAL partition that holds etcd but on the same NVMe disk. On the Nitro it lies inside EPHEMERAL, which survives reboots and upgrades but not a Talos wipe.

On the Nitro the directory shares the node's EPHEMERAL disk with the kubelet and Longhorn. `local-path` does not enforce the 5 GiB claim size, and only the node filesystem alerts cover the space it uses. `max_slot_wal_keep_size` caps the WAL that the primary retains for an absent standby at 1 GB. A standby that falls further behind cannot catch up by streaming; recreate it with `kubectl cnpg destroy postgres <instance-number>` so the operator clones it again from the primary.

## Backup contract

The CronJob dumps every database except `postgres` with `pg_dump --format=custom`, packs the dumps and a manifest of their SHA-256 digests into one tar, encrypts it to an OpenPGP public key, and uploads it as one object under the prefix in `postgres-backup-s3`. The cluster holds only the public key: neither the job nor anyone with the bucket credentials can read a stored backup.

The bound on what the schedule stores does not depend on how fast the database is written:

- an encrypted object above `MAX_OBJECT_BYTES` (20,000,000) is never uploaded, and the job fails;
- the job's objects are pruned to `KEEP` (7) before and after each upload, and the job never retries;
- so the job never holds more than 8 objects or 160,000,000 bytes under the prefix.

The bound assumes no manual run overlaps a scheduled one: `concurrencyPolicy: Forbid` covers only runs the CronJob starts itself. Only keys named `<prefix>/postgres-YYYYMMDDTHHMMSSZ.tar.gpg` belong to the job; any other object under the prefix is never counted or deleted, and is outside the bound.

Before each upload the job measures every object in the bucket and fails, without uploading, unless current bytes plus the new object plus a 100,000,000-byte reserve stay below the 1,000,000,000-byte ceiling, the same contract as `../velero/check-capacity.sh`.

The bucket-size signal is a failed `postgres-bucket-usage` Job. Every six hours it measures the whole bucket, including Velero's objects, and fails when it holds more than 700,000,000 bytes. The kube-prometheus-stack `KubeJobFailed` alert reports it; the failed Job expires after six hours, so the alert clears when the next run passes. That job has no database access.

The backup role reads every table through `pg_read_all_data` but cannot read large objects. A consumer that stores large objects makes the dump fail, and the backup alerts, until the role is granted access to them.

Recovery point: up to one day plus the job duration. Point-in-time recovery is not available.

The private key for decryption exists only off-cluster. A lost private key makes every stored backup unreadable.

## Secrets

Three Secrets in the `postgres` namespace, sealed into this directory as `sealedsecret-backup-s3.yaml`, `sealedsecret-backup-recipient.yaml` and `sealedsecret-backup-role.yaml`:

| Secret | Type | Keys |
| --- | --- | --- |
| `postgres-backup-s3` | Opaque | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_ENDPOINT_URL`, `S3_BUCKET`, `S3_PREFIX` |
| `postgres-backup-recipient` | Opaque | `recipient.asc`: the armored OpenPGP public key |
| `postgres-backup-role` | `kubernetes.io/basic-auth` | `username` (`backup`), `password` |

The OpenPGP private key never enters the cluster. Generate the key pair offline with a generic user ID, export only the public key for `postgres-backup-recipient`, and keep the private key with the off-cluster recovery material.

The operator creates `postgres-ca`, `postgres-app` and the replication certificates itself.

## Allowed flows

| From | To | Port |
| --- | --- | --- |
| operator (`cnpg-system`) | instances | 8000, 5432 |
| instances and CNPG job pods | each other | 5432, 8000 |
| Prometheus (`monitoring`) | instances | 9187 |
| backup job (`app.kubernetes.io/name: postgres-backup`) | instances | 5432 |
| instances | kube-dns, Kubernetes API | 53, any |
| backup job | kube-dns, `*.r2.cloudflarestorage.com` | 53, 443 |
| bucket-usage job (`app.kubernetes.io/name: postgres-bucket-usage`) | kube-dns, `*.r2.cloudflarestorage.com` | 53, 443 |

The API server's pod proxy to the status port of an instance on the other node is not admitted. It affects only diagnostics that use that proxy, such as parts of `kubectl cnpg status`.

## Verification

```bash
kubectl -n postgres get cluster postgres
kubectl -n postgres get pods -o wide -l cnpg.io/cluster=postgres
kubectl -n postgres get pdb
kubectl -n postgres exec postgres-1 -c postgres -- psql -Atc 'SHOW synchronous_standby_names'
kubectl -n postgres create job --from=cronjob/postgres-backup postgres-backup-manual
kubectl -n postgres logs job/postgres-backup-manual --all-containers
```

The Cluster must report `Cluster in healthy state` with two ready instances on different nodes, and `synchronous_standby_names` must name the standby. A manual backup must log `upload: done`. The failover and restore drills are in `lab-experiments/kubernetes/storage/postgres-drills/`.

## Rollback

The `Cluster` carries `Prune=false,Delete=false` for Argo CD, because deleting it deletes both volumes. To remove the component, take and verify a backup, delete the Application, then delete the `Cluster` by hand. Backups in R2 stay until their objects are deleted.

## Known limitations

- The OptiPlex is a single point of failure for writes, as above.
- A full link outage between the nodes behaves like a Nitro failure only while the operator runs on the OptiPlex. A primary on the Nitro then fails its isolation check, and the standby on the OptiPlex is promoted once the primary lease expires. Commits the isolated primary could not replicate were never acknowledged.
- `local-path` claims report no volume usage metrics; database size is visible as `cnpg_pg_database_size_bytes`.
- When the encrypted dump outgrows `MAX_OBJECT_BYTES`, backups stop and alert. Raising the bound requires recomputing the prefix bound above against the bucket ceiling.
