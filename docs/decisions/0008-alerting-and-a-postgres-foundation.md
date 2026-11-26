# 0008 - Alerting to Discord and a shared PostgreSQL foundation

- Status: accepted
- Date: 2026-11-27
- Completes: the CloudNativePG failover and recovery proof that [0007](./0007-host-infra-portal.md) left as a separate goal

## Context

Devata evaluated alert rules but delivered them nowhere: Alertmanager was disabled, and six alerts had fired for at least a week with no reader. Argo CD, Longhorn and Velero were not scraped. Nothing in the cluster watched the ProBook host that [0005](./0005-probook-leaves-the-cluster.md) moved outside it. The only database was the single-instance PostgreSQL of infra-portal, with no scheduled off-cluster backup.

Three constraints shaped the choices:

- Devata has two nodes and no spare. The OptiPlex holds the only etcd member and ran at 70 percent memory before this work.
- The off-cluster bucket is shared with Velero and has a 1 GB operating ceiling that the provider does not enforce. Anything scheduled must have a bound that does not depend on how much is written.
- A backup must be unreadable to someone who holds only the bucket credentials.

## Decision

### Alerting

- Run Alertmanager from kube-prometheus-stack as one replica without a volume. Routing lives in an `AlertmanagerConfig` that is loaded as the global configuration.
- Deliver only `warning` and `critical` alerts, with resolved notifications, to the `#homelab-alerts` Discord channel. The webhook exists in git only as a SealedSecret.
- Route `Watchdog`, `InfoInhibitor` and the hand-made practice namespaces that are not in git to a `null` receiver. Disable `KubeMemoryQuotaOvercommit`, which has no namespace label and measured only a practice quota.
- Turn routing on in two steps: Alertmanager with only the `null` receiver first, then the Discord receiver once the set of alerts it would deliver was empty.
- Give the hourly snapshot publisher Jobs a one day TTL, so one failed run does not hold `KubeJobFailed` for weeks.
- Scrape the three control plane targets from `ScrapeConfig` objects with static targets. Argo CD excludes `Endpoints`, so the chart's own path was never applied from git (#90).

### Scrapes and probes

- Scrape Argo CD through a ServiceMonitor owned by kube-prometheus-stack, and Longhorn and Velero through the ServiceMonitor of their charts. Drop the high-cardinality series that no rule or dashboard reads.
- Probe the ProBook with ICMP from a blackbox exporter. ICMP leaves no connection log on the target. The exporter uses an unprivileged ICMP socket through the `net.ipv4.ping_group_range` sysctl and holds no capability.
- Merge alert rules for these targets only after each expression returned nothing against the live series.

### PostgreSQL

- Run one CloudNativePG `Cluster` with two instances, one per node, as shared platform storage in `kubernetes/infra/storage/postgres/`.
- Replicate synchronously (`ANY 1`) with `dataDurability: preferred`: a commit waits for the standby while the standby is healthy, and the primary stays writable when the standby is gone.
- Store each instance on `local-path`, on its own node. PostgreSQL does the replication, so no write crosses the link between the nodes twice. Longhorn with two replicas was rejected for that reason.
- Back up with a daily logical dump, not with Barman. The dump is encrypted to an OpenPGP public key before it leaves the pod, uploaded as one object under a separate prefix of the Velero bucket, and kept seven deep. The cluster holds only the public key.
- Bound the backup by design: at most 8 objects of at most 20,000,000 bytes each, whatever the write rate. A guard on the whole bucket runs before each upload and keeps a 100,000,000 byte reserve below the ceiling.
- Alert on backup age (no success in 26 hours) and on bucket size (a Job that measures the whole bucket every six hours fails above 700,000,000 bytes).

Barman, in tree or as a plugin, was rejected on both constraints. The WAL it archives grows with the write rate, so it has no fixed bound. It offers only provider-side encryption, and the object store rejects the header for that.

## Evidence

All times are UTC on 2026-11-26.

### Alert delivery

Alertmanager's own counters are the record, because nothing in the cluster can read the channel. They prove that Discord accepted each request, not that a person read it.

| Time | Event |
| --- | --- |
| 20:21:01 | Discord receiver loaded. `alertmanager_notifications_total{integration="discord"}` is 0. |
| 20:21:52 | Test heartbeat stopped and a failing test Job created. |
| 20:26:15 | Counter 0 to 1: the heartbeat alert, after its two minute hold and the one minute group wait. |
| 20:26:49 | Heartbeat restarted. |
| 20:36:15 | Counter 1 to 2: the heartbeat alert resolved, after the ten minute group interval. |
| 20:38:38 | Counter 2 to 3: `KubeJobFailed`, after its fifteen minute hold. |
| 20:38:46 | Failed Job deleted. |
| 20:48:38 | Counter 3 to 4: `KubeJobFailed` resolved. |

Failed notifications stayed at 0 for every reason. Outside the two tests the counter did not move: three alerts fire at rest, and all three go to the `null` receiver.

### Backup read-back

Before any PostgreSQL object existed, one 71,844 byte object went through the same images and the same upload script as the scheduled backup. Downloaded on a workstation, its SHA-256 matched the one the pod reported, it was not readable without the private key, and it decrypted to the plaintext SHA-256 the pod had printed.

### Failover

A writer inserted 3,000 rows, one transaction each, through the read-write Service, and logged an id only after the commit was acknowledged. The primary pod was deleted with a one second grace period.

| Run | Primary before | Killed | New primary promoted | Failed inserts | Acknowledged | Present | Acknowledged but missing |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Nitro | 21:12:39 | 21:12:41 | 2 | 2,998 | 2,998 | 0 |
| 2 | OptiPlex | 21:19:34 | 21:19:35 | 2 | 2,998 | 2,998 | 0 |

In both runs the old primary came back as a synchronous standby without help.

### Restore

A checksum of every table and sequence was taken on the primary at 21:16:44. A backup made right after it stored a 317,604 byte object. That object was restored into a one-instance cluster in a scratch namespace. The checksum output of the restored database was byte-identical to the one taken before. Changing one row in the restored copy changed the checksum. The scratch namespace was deleted afterwards.

The dated report and the scripts are in [`lab-experiments/kubernetes/storage/postgres-drills/`](../../lab-experiments/kubernetes/storage/postgres-drills/).

### Debts recorded, not fixed

These two come from #91.

- **Nitro Ethernet link.** `enp3s0` on `talos-lqv-w4u` reported 1000 Mbps, full duplex, at every reading on the night of this work: 19:40, 21:00, 21:09, 21:12 and 21:18. `node_network_speed_bytes` shows 1000 Mbps with no change for the seven days Prometheus retains. The 10 Mbps downshift that #91 describes was not seen, and its cause was never found, so it can return. If it does, commits stay synchronous and become slow; they are not lost.
- **etcd snapshots.** etcd has one member, on the OptiPlex, with a 68 MB database of which 18 MB is in use. No snapshot is scheduled and none is stored off the node. The loss of the OptiPlex disk loses the cluster state. The PostgreSQL backup does not depend on etcd: an object in the bucket restores into any cluster with the private key.

## Consequences

- A stopped heartbeat or a failed Job reaches Discord with no manual check. Nothing outside the cluster watches `Watchdog`, so if the OptiPlex stops, nothing alerts.
- The operator of the chart version in use rejects a Discord webhook file, which is why the receiver reads a Secret reference. This can be revisited after a chart upgrade.
- An off-cluster restore can lose up to 24 hours, and there is no point-in-time recovery. Inside the cluster a single instance loss loses no acknowledged commit while the standby is healthy.
- If the OptiPlex stops, the API stops with it, no failover happens, and writes stop. The isolation check restarts a primary that can reach neither the API server nor the other instance.
- The private key exists only off the cluster. A lost key makes every backup unreadable.
- `local-path` does not enforce claim sizes. On the Nitro the data shares a filesystem with the kubelet and Longhorn, and only the node filesystem alerts guard it.
- etcd and a PostgreSQL instance share the OptiPlex NVMe. During the cluster bootstrap and during the failover run that wrote to the OptiPlex primary, the etcd backend commit p99 rose from 2 ms to about 0.5 s for a few minutes. `etcdHighCommitDurations` went pending and cleared before its ten minute hold. Keep the primary on the Nitro when there is a choice.
- OptiPlex memory use rose from 70 percent to about 80 percent. The API server grew when eleven new CRDs registered. Prometheus peaked at 838 Mi against a 900 Mi limit in the week before this work.
- The Velero capacity script sums only the first 1,000 objects of the bucket, which now holds more. The PostgreSQL scripts count every object. The Velero script is unchanged here.
- #90 is resolved by the `ScrapeConfig` objects. The Velero schedule, the etcd snapshot schedule and the link cause in #91 stay open.
