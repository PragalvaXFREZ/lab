# storage

Persistent storage for the cluster. Longhorn remains the target for replicated volumes, with Velero providing backups later and the required Talos extensions declared in `talos/schematics/`.

The OptiPlex migration uses an interim local-path mapping under `local-path/`. It keeps the existing observability claims on the node's persistent XFS volume at `/var/mnt/longhorn` instead of Talos's ephemeral `/opt`. This mapping does not provide replication or replace the planned Longhorn installation.
