# storage

Persistent storage for the cluster. Longhorn provides replicated block volumes, while Velero sends independent backups off cluster. Required operating-system extensions remain declared under `talos/schematics/` and are applied outside Argo CD.

`longhorn/` owns the replicated storage controller and its non-default StorageClass. `local-path/` remains the default during workload-by-workload migration and provides the rollback claims retained on the OptiPlex XFS volume.
