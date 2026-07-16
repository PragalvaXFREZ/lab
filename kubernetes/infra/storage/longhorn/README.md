# Longhorn

Longhorn provides replicated block storage for workloads that need to survive a worker failure. Argo CD installs the pinned Helm chart and keeps its Kubernetes resources reconciled.

## Safety model

The `longhorn` StorageClass is deliberately non-default. Existing workloads remain on `local-path` until they are backed up and migrated individually. New Longhorn volumes use the V1 data engine and two replicas.

Longhorn creates a default disk only on nodes labeled `node.longhorn.io/create-default-disk=true`. Each eligible Talos node exposes `/var/mnt/longhorn` to kubelet with shared mount propagation and includes the `iscsi-tools` and `util-linux-tools` system extensions.

The OptiPlex path is a dedicated XFS user volume. The Nitro path is inside Talos EPHEMERAL storage, so it survives ordinary reboots and upgrades but not a Talos wipe. Two-replica volumes remain limited by the smaller eligible disk and require both workers to be available for full redundancy.

## Files

- `values.yaml` pins the V1 engine, two-replica policy, non-default StorageClass, and storage path.
- `../../../clusters/devata/longhorn.yaml` wires the chart into the devata app of apps and grants the namespace the privileged Pod Security level Longhorn requires.
- `../../../../talos/schematics/` and `../../../../talos/machineconfigs/` describe the operating-system prerequisites applied outside Argo CD.

## Verification

```bash
kubectl -n longhorn-system get pods
kubectl get storageclass longhorn -o yaml
kubectl -n longhorn-system get nodes.longhorn.io
kubectl -n longhorn-system get settings.longhorn.io default-replica-count default-data-path v1-data-engine v2-data-engine
```

The `local-path` StorageClass must retain the default annotation until migrations and rollback checks are complete. A disposable claim must show two healthy replicas on different workers before a workload is migrated.

## Rollback

Revert each workload to its retained `local-path` claim before removing Longhorn. Disable every Longhorn disk, wait for replicas to evacuate or delete disposable volumes, and confirm no workload PVC uses the `longhorn` StorageClass. Then remove the child Application. Talos extensions and mount declarations can remain because they are inert without Longhorn.

Do not delete Longhorn CRDs, replica directories, or Talos volumes as part of an ordinary rollback.
