# local-path persistence bridge

This Application owns the existing local-path provisioner's path mapping while Longhorn is not installed.

Claims scheduled to `talos-opt-7040` are created under `/var/mnt/longhorn/local-path`, which is backed by the node's dedicated XFS user volume. Other nodes retain the legacy default path for compatibility. This remains single-node storage without replication or automatic failover.
