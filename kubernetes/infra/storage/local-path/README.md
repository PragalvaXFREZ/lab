# local-path persistence bridge

This Application owns the existing local-path provisioner's path mapping while Longhorn is not installed.

Claims scheduled to `talos-opt-7040` are created under `/var/mnt/longhorn/local-path`, which is backed by the node's dedicated XFS user volume. Claims scheduled to `talos-lqv-w4u` use the same path, which on that node lies inside the Talos EPHEMERAL volume: it survives reboots and upgrades but not a Talos wipe. Both nodes already bind-mount `/var/mnt/longhorn` into kubelet for Longhorn. Other nodes retain the legacy default `/opt/local-path-provisioner`, which the Talos documentation describes as read-only; do not expect a claim on such a node to provision.

This remains single-node storage without replication or automatic failover. The provisioner does not enforce claim sizes: a claim can grow until the filesystem it shares with Longhorn is full.
