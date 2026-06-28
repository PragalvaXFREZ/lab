# talos

The OS and machine layer for devata. This is [Talos Linux](https://www.talos.dev/) configuration: how each node is provisioned and what kernel and system extensions the image carries.

This directory is version controlled here for history and review, but it is applied out of band with [`talosctl`](https://www.talos.dev/latest/reference/cli/), **not** by the GitOps controller. This is the GitOps boundary: the reconciler manages Kubernetes objects, it does not manage the operating system.

- [`machineconfigs/`](./machineconfigs) per node configuration.
- [`patches/`](./patches) reusable config patches applied across nodes.
- [`schematics/`](./schematics) Image Factory schematics: system extensions and kernel args baked into the boot image.
