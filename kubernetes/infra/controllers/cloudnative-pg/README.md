# CloudNativePG

CloudNativePG is the operator for PostgreSQL clusters on devata. It runs one controller in `cnpg-system`, watches every namespace, and owns the `postgresql.cnpg.io` CRDs and admission webhooks. Each PostgreSQL `Cluster` lives with the component that owns its lifecycle.

## Files

- `values.yaml` sets one replica, the resource budget, a preference for the control plane node, and the operator PodMonitor. In a partition between the two nodes only the side with the API server can fail over, so the operator belongs on that side.
- `../../../clusters/devata/cloudnative-pg.yaml` wires the pinned chart into the devata app of apps.

The chart is pinned to `0.29.2`, which ships operator `1.30.2`. Argo CD applies the chart CRDs with Server-Side Apply because the `Cluster` and `Pooler` CRDs exceed the size limit of the client-side `last-applied-configuration` annotation.

The webhooks use `failurePolicy: Fail`. While the controller pod is unavailable, creating or changing a `Cluster` is rejected and no failover happens. Running instances keep serving their current role.

No Barman Cloud plugin is installed. Off-cluster backups of managed clusters are logical dumps owned by each cluster component.

## Verification

```bash
kubectl -n cnpg-system get deploy,pods
kubectl get crd clusters.postgresql.cnpg.io
kubectl -n cnpg-system get podmonitor
```

The deployment must be Available, and Prometheus must report the `cnpg-system` PodMonitor target as up.

## Rollback

Remove every `Cluster` first. The CRDs are rendered by the chart, so deleting the Application with pruning deletes them, and Kubernetes then deletes every `Cluster` and the objects it owns. Never prune this Application while a `Cluster` exists.

## Upgrades

Read the release notes for every minor version between the pinned and the target version. An operator upgrade restarts the instance managers, replicas first and the primary last, following each cluster's `primaryUpdateMethod`.
