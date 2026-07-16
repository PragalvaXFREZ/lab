# machineconfigs

Per-node Talos configuration patches and non-secret volume documents. Applied with `talosctl apply-config` together with a locally held cluster machine configuration.

Rendered machine configurations contain the cluster trust material and stay outside Git. The committed patches are the reviewable source for machine-specific networking, installation targets, and disk layout. A live node is not edited unless the corresponding patch lands here first.

The Dell OptiPlex 7040 worker uses three inputs:

- `optiplex-7040.machine.patch.yaml` for its hostname, address, install image, and Longhorn kubelet mount.
- `optiplex-7040.ephemeral.yaml` to cap Talos `/var` at 40 GiB during first provisioning.
- `optiplex-7040.longhorn-volume.yaml` to create the XFS volume mounted at `/var/mnt/longhorn` from the remaining NVMe space.

The Acer Nitro 5 worker uses `nitro-5.machine.patch.yaml` to preserve its hostname, networking, NVIDIA kernel configuration, and registry mirror while adding the Longhorn kubelet mount and storage-node label. Its `/var/mnt/longhorn` directory remains inside the existing Talos EPHEMERAL volume. No partition change is part of that patch.
