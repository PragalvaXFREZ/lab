# 0005 - The ProBook leaves the cluster

- Status: accepted
- Date: 2026-10-05
- Supersedes: the part of [0004](./0004-control-plane-on-the-optiplex.md) that keeps the ProBook as a worker

## Context

ADR 0004 moved the control plane to the OptiPlex and kept the HP ProBook 640 G1 as the worker `talos-probook-640` with a `PreferNoSchedule` taint. The node has two cores, 3.3 GiB of memory, and a rotational disk.

After the move, the node ran only the eight pods that DaemonSets place on every node. No workload was scheduled there. The node used approximately 1.5 GiB of its memory to be a cluster member. It held no Longhorn replica, no etcd member, and no persistent data. The Longhorn manager could not start on it, because its image has no `iscsi-tools` extension.

The machine has a better use outside devata as a general-purpose Linux host.

## Decision

Remove the ProBook from devata. Devata has two nodes: the OptiPlex (control plane, workloads, Longhorn) and the Nitro (worker, Longhorn).

Remove the ProBook machine patch and the NetBird-only schematic from this repository. No node uses them.

Keep `longhornManager.nodeSelector`. A future node without a Longhorn disk has the same requirement.

## Consequences

- The cluster loses no state and no scheduled workload.
- Devata has no spare node. A drain of one node puts all workloads on the other node.
- `192.168.1.8` is no longer a devata address. The machine keeps the address as a host outside the cluster.
- The machine is on the same LAN as the Talos and Kubernetes APIs. It holds no devata credentials.
- A third node, when one is available, starts from a worker source configuration and its own patch, as `talos/machineconfigs/README.md` describes.
