# Longhorn workload migration

These disposable manifests support cold, checksum-verified moves between retained `local-path` volumes and two-replica Longhorn volumes. They are operator tools and are never reconciled by Argo CD.

Migrate one workload at a time. Stop its controller, archive and checksum the source, copy into a separately named Longhorn claim, verify the copied tree, then point the workload at the new claim. Keep the original local PV and the archive until the workload has passed both its application check and a real rollback.

The rollback manifests rebind the original retained local PVs. The forward-rebind manifests recover the tested Longhorn volumes after rollback without provisioning a blank replacement. PVC and PV names in these manifests are evidence-specific and must not be reused against a different cluster state.

Do not delete retained claims, PVs, archives, or Longhorn replicas during an ordinary rollback.
