# 0004 - Control plane on the OptiPlex

- Status: accepted
- Date: 2026-10-05

## Context

Devata has one control plane node. Until this decision it was an HP ProBook 640 G1 with two cores, 3.3 GiB of memory, and a rotational SATA disk. etcd requires fast synchronous writes, and the node could not supply them. Over seven days, the etcd WAL fsync p99 was 0.12 s against a guideline of 0.01 s, the worst one-hour p99 reached the 8.192 s histogram ceiling, and etcd recorded approximately 32,900 slow applies. `kube-apiserver` used 1.36 GiB, and available memory fell to 343 MiB. `kube-scheduler` and `kube-controller-manager` lost their leader leases and restarted.

The address of that node was also the address of the cluster. Cilium, the worker machine configurations, and the administrator clients used `192.168.1.8:6443`. The live control plane configuration named `192.168.1.2`, an address that no machine held. etcd advertised the NetBird address of the node as its peer URL.

Devata has three machines. The other two are the Dell OptiPlex 7040 (four cores, 7.8 GiB, NVMe, wired desktop) and the Acer Nitro 5 (sixteen threads, 7.3 GiB, NVMe). Both hold Longhorn replicas. A fourth machine is expected but has no date.

## Decision

Run the control plane on the OptiPlex. The OptiPlex also stays a workload node and a Longhorn node, with `allowSchedulingOnControlPlanes`. The Nitro keeps its sixteen threads for workloads. The ProBook becomes a worker with a `PreferNoSchedule` taint and holds no persistent data.

Promote the OptiPlex in place. Talos applies a change of machine type from worker to control plane with one reboot, so the Longhorn volume on the node is not wiped.

Separate the cluster address from the machine:

- `192.168.1.2` is a Talos shared IP on the control plane node, and it is the cluster endpoint on every node.
- Components that run on a node use KubePrism on `127.0.0.1:7445`.
- etcd advertises only `192.168.1.0/24` addresses.

Keep one control plane node. Three members require three machines with fast disks, and devata has two.

## Consequences

- etcd runs on NVMe. The control plane has approximately 4 GiB more memory available than before.
- The OptiPlex carries the API server, etcd, workloads, and Longhorn replicas. Its memory use rises by approximately 1.6 GiB. A Longhorn rebuild and etcd share one disk.
- The loss of the OptiPlex stops the API and removes one of two Longhorn replica locations at the same time. Recovery uses an etcd snapshot and the procedure in `talos/machineconfigs/`.
- A later move of the control plane, or a change to three members, needs no change to Cilium, to the worker configurations, or to the clients.
- `192.168.1.2` must stay outside the DHCP pool of the router.
- The ProBook can leave the cluster with no effect on state.
