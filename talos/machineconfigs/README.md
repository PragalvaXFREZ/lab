# machineconfigs

Per node Talos configuration patches and non-secret volume documents. Applied with `talosctl apply-config` together with a locally held cluster machine configuration.

Rendered machine configurations contain the cluster trust material and stay outside Git. The committed patches are the reviewable source for machine-specific networking, installation targets, node roles, and disk layout. A live node is not edited unless the corresponding patch lands here first.

## Node inputs

| Node | Machine | Role | Inputs |
| --- | --- | --- | --- |
| `talos-opt-7040` | Dell OptiPlex 7040 | control plane, workloads, Longhorn | `optiplex-7040.controlplane.patch.yaml`, `optiplex-7040.ephemeral.yaml`, `optiplex-7040.longhorn-volume.yaml` |
| `talos-lqv-w4u` | Acer Nitro 5 | worker, Longhorn | `nitro-5.machine.patch.yaml` |
| `talos-probook-640` | HP ProBook 640 G1 | worker | `probook-640.machine.patch.yaml` |

The OptiPlex uses three inputs:

- `optiplex-7040.controlplane.patch.yaml` for its hostname, address, install image, Longhorn kubelet mount, the shared API address, and the control plane settings.
- `optiplex-7040.ephemeral.yaml` to cap Talos `/var` at 40 GiB during first provisioning.
- `optiplex-7040.longhorn-volume.yaml` to create the XFS volume mounted at `/var/mnt/longhorn` from the remaining NVMe space.

The Acer Nitro 5 worker uses `nitro-5.machine.patch.yaml` to preserve its hostname, networking, NVIDIA kernel configuration, and registry mirror while adding the Longhorn kubelet mount and storage-node label. Its `/var/mnt/longhorn` directory remains inside the existing Talos EPHEMERAL volume. No partition change is part of that patch. Its active Image Factory source is `../schematics/nvidia-lts-longhorn.yaml`; the older `nvidia-lts535*.yaml` files remain as historical experiment inputs.

The ProBook worker uses `probook-640.machine.patch.yaml`. The node has a rotational disk and little memory. It has no Longhorn label and no `iscsi-tools` extension, so Longhorn does not place replicas on it. The `devata.pragalva.me/low-capacity` taint has the `PreferNoSchedule` effect: the scheduler uses the node only when the other nodes cannot take a pod.

The installer references target Talos v1.12.11 because that is the first supported adjacent minor whose extension catalog contains NetBird.

## Control plane contract

[ADR 0004](../../docs/decisions/0004-control-plane-on-the-optiplex.md) records the decision.

- **API address.** `cluster.controlPlane.endpoint` is `https://192.168.1.2:6443` on every node. `192.168.1.2` is a Talos shared IP (`machine.network.interfaces[].vip`). It is configured only on control plane nodes. The address must stay outside the DHCP pool of the router.
- **Node-local API access.** KubePrism listens on `127.0.0.1:7445` on every node. Kubelet and Cilium use it. They do not depend on the shared IP.
- **etcd peers.** `cluster.etcd.advertisedSubnets` is `192.168.1.0/24` on every control plane node. NetBird adds the `wt0` interface, and etcd can otherwise advertise the NetBird address. The NetBird policies do not permit TCP 2380 between nodes.
- **Scheduling.** `cluster.allowSchedulingOnControlPlanes` is `true` on the OptiPlex. The node keeps its workloads and its Longhorn replicas.

## Render a configuration

The source is the live main configuration document of a node with the same role. Remove the fields that belong to the source node, then apply the committed patch. Keep all files in a private directory with mode `0700`.

Fields to remove from a control plane source: `machine.network`, `machine.install`, `machine.nodeLabels`, `machine.certSANs`, `machine.kubelet.nodeIP`, and `cluster.apiServer.certSANs`.

Fields to remove from a worker source: `machine.network`, `machine.install`, `machine.nodeLabels`, `machine.kubelet.nodeIP`, `machine.kubelet.extraMounts`, `machine.kernel`, `machine.sysctls`, and `machine.registries`.

```bash
talosctl machineconfig patch base.yaml \
  --patch @talos/machineconfigs/<node>.patch.yaml \
  --output main.yaml
```

Append each auxiliary document of the target node after the main document: the volume documents, and the `ExtensionServiceConfig` named `netbird` from the live configuration of that node. Then validate and inspect the difference:

```bash
talosctl validate --config full.yaml --mode metal --strict
talosctl --nodes <node-ip> apply-config --file full.yaml --dry-run
```

Keep the dry-run output private. Unchanged context can contain trust material.

## Promote a worker to the control plane

Talos applies a change of `machine.type` from `worker` to `controlplane` in place, with one reboot. The system disk, the user volumes, and the NetBird identity stay.

Before the change:

1. Save an etcd snapshot and the live machine configuration of every node outside the cluster.
2. Make sure that each Longhorn volume with data to keep has a healthy replica on a different node.
3. Make sure that `talosctl etcd members` shows a `192.168.1.x` peer URL for each member. If a member shows a NetBird address, apply `../patches/etcd-lan-peers.patch.yaml` to that node first.
4. Render the configuration with `cluster.controlPlane.endpoint` set to the address of a control plane node that serves the API now. The shared IP does not answer until a node that has the `vip` setting runs etcd.

Apply the configuration and let the node reboot. Do not continue until:

- `talosctl etcd members` lists the new member with `LEARNER` `false` and a `192.168.1.x` peer URL;
- `talosctl etcd status` shows the same Raft index on all members and no errors;
- `curl --insecure https://192.168.1.2:6443/version` answers;
- the node is `Ready`, `/var/mnt/longhorn` is mounted, and Longhorn rebuilds the replicas on the node.

Then set `cluster.controlPlane.endpoint` to `https://192.168.1.2:6443` on each node with `talosctl patch machineconfig --mode=no-reboot`, and point the local `talosconfig` and `kubeconfig` at the new node or the shared IP.

A cluster with two etcd members stops when either member stops. Keep that state short.

## Demote a control plane node to a worker

Talos does not change `machine.type` from `controlplane` to `worker` in place. Reset the node, then apply a worker configuration.

```bash
talosctl --nodes <old-control-plane-ip> reset \
  --graceful=true --reboot \
  --system-labels-to-wipe STATE \
  --system-labels-to-wipe EPHEMERAL
```

A graceful reset drains the node and removes its etcd member before the wipe. Confirm with `talosctl etcd members` on a remaining control plane node that the member is gone. Delete the old Kubernetes `Node` object.

The node starts in maintenance mode and uses DHCP. Find its address by its MAC address, then apply the rendered worker configuration:

```bash
talosctl apply-config --insecure --nodes <dhcp-address> --file full.yaml
```

The reset removes the NetBird identity in `/var/lib/netbird`. Enroll the node again with a new one-off setup key as described in [`../netbird/`](../netbird).

## Rollback

- Before the promoted node joins etcd: apply the saved worker configuration of that node again.
- After it joins and before the old node is reset: remove the new member with `talosctl etcd remove-member`, then apply the saved worker configuration.
- After the old node is reset: there is no path back to the old member. Restore from the etcd snapshot with `talosctl bootstrap --recover-from` only if the new control plane is lost.
