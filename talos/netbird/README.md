# NetBird remote access

NetBird runs as a Talos extension service on each physical node. It is independent of Kubernetes, Cilium, Argo CD, and any additional LAN host.

## Version contract

- Current cluster: Talos v1.11.5 and Kubernetes v1.34.1.
- Target operating system: Talos v1.12.11.
- Kubernetes remains v1.34.1 during this change.
- NetBird extension: `ghcr.io/siderolabs/netbird:0.66.2`, selected by the Talos v1.12.11 extension catalog.

NetBird is not present in the Talos v1.11.5 extension catalog. Do not attempt to use the v1.12 extension with the current operating system and do not substitute a Kubernetes pod for recovery access.

NetBird makes each enrolled node multihomed. Kubelet must be restricted to `192.168.1.0/24` before the extension starts, otherwise it can publish the NetBird address as the node `InternalIP` and break control-plane, Cilium, and CSI traffic. Keep NetBird in its default kernel mode.

## NetBird account preparation

Complete these control-plane steps before changing a Talos node:

1. Create a NetBird Cloud account and enroll the administrator workstation interactively.
2. Create `devata-admins`, `devata-control-plane`, and `devata-workers` peer groups.
3. Put the workstation in `devata-admins`.
4. Add unidirectional policies from `devata-admins` to:
   - `devata-control-plane` on TCP 50000 and 6443;
   - `devata-workers` on TCP 50000;
   - both Talos groups over ICMP if diagnostic ping is wanted.
5. Disable the default full-mesh policy only after the explicit policies exist.
6. Create a one-off setup key immediately before enrolling each node. Auto-assign the control-plane key to `devata-control-plane` and each worker key to `devata-workers`.

Never place a setup key in Git, an issue, a pull request, shell history, or chat. A key is used for one node and is not reused.

## Image sources

| Node | Schematic | Talos v1.12.11 installer |
| --- | --- | --- |
| `talos-opt-7040` | `../schematics/baremetal-longhorn.yaml` | `factory.talos.dev/metal-installer/f141fc2a08d5a459a80d871faa48d7dc92bc354e4faf6cdbafe1cc0fac717991:v1.12.11` |
| `talos-k3t-9cz` | `../schematics/controlplane-netbird.yaml` | `factory.talos.dev/metal-installer/7326f0cbca7a0e700ac1efa3f32e88df9ebe5010e6e842a8ed36fdc99ee98ead:v1.12.11` |
| `talos-lqv-w4u` | `../schematics/nvidia-lts-longhorn.yaml` | `factory.talos.dev/metal-installer/6da7b4e2db4c4bdf73bf98fcdcb689b2abb21567c57082a8413742b96851ee33:v1.12.11` |

The Nitro image moves the NVIDIA LTS extension from the v1.11.5 catalog's 535 branch to the v1.12.11 catalog's supported 580 branch. Upgrade that node last and treat GPU behavior as a separate verification surface.

If the upstream Image Factory path is unreliable, mirror the exact installer into a reachable LAN registry before starting a node upgrade and replace only the command's image reference. Confirm the mirrored digest before use.

## Per-node enrollment

Use a `talosctl` client matching the running Talos v1.11.5 cluster to initiate the upgrade. Update the client to v1.12.11 after the cluster reaches that version.

For each node, build a private temporary full configuration from the live main document, every required auxiliary document, and `../patches/netbird.extensionserviceconfig.example.yaml`. Confirm the intended node twice before continuing.

First inspect the live machine configuration. If the constraint is missing, apply this patch once to pin kubelet to the physical LAN, then verify that Kubernetes still reports the node's LAN address:

```bash
NETBIRD_NODE=192.168.1.10
KUBERNETES_NODE=talos-opt-7040

talosctl --nodes "$NETBIRD_NODE" patch machineconfig \
  --patch @talos/patches/netbird.node-ip.patch.yaml \
  --mode=no-reboot

kubectl get node "$KUBERNETES_NODE" \
  --output jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}'
```

Do not continue unless the result is the node's `192.168.1.x` address. The committed worker machine patches carry the same constraint for future rendered configurations.

```bash
NETBIRD_CONFIG_PATH="$(mktemp)"
NETBIRD_DRY_RUN_PATH="$(mktemp)"
trap 'shred -u "$NETBIRD_CONFIG_PATH" "$NETBIRD_DRY_RUN_PATH"' EXIT
chmod 600 "$NETBIRD_CONFIG_PATH" "$NETBIRD_DRY_RUN_PATH"

talosctl --nodes "$NETBIRD_NODE" get machineconfig --output json \
  | jq -r '.spec' > "$NETBIRD_CONFIG_PATH"

case "$NETBIRD_NODE" in
  192.168.1.10)
    NETBIRD_EXTRA_DOCUMENTS=(
      talos/machineconfigs/optiplex-7040.ephemeral.yaml
      talos/machineconfigs/optiplex-7040.longhorn-volume.yaml
    )
    ;;
  192.168.1.8|192.168.1.9)
    NETBIRD_EXTRA_DOCUMENTS=()
    ;;
  *)
    echo "refusing unknown node" >&2
    exit 1
    ;;
esac

for NETBIRD_SOURCE_PATH in "${NETBIRD_EXTRA_DOCUMENTS[@]}" \
  talos/patches/netbird.extensionserviceconfig.example.yaml; do
  printf '\n---\n' >> "$NETBIRD_CONFIG_PATH"
  sed '/^#/d' "$NETBIRD_SOURCE_PATH" >> "$NETBIRD_CONFIG_PATH"
done

talosctl --nodes "$NETBIRD_NODE" apply-config \
  --file "$NETBIRD_CONFIG_PATH" \
  --mode=no-reboot \
  --dry-run > "$NETBIRD_DRY_RUN_PATH" 2>&1

${EDITOR:?set EDITOR} "$NETBIRD_DRY_RUN_PATH"

${EDITOR:?set EDITOR} "$NETBIRD_CONFIG_PATH"
if rg --quiet 'REPLACE_WITH_ONE_OFF_SETUP_KEY' "$NETBIRD_CONFIG_PATH"; then
  echo "setup-key placeholder remains" >&2
  exit 1
fi

talosctl --nodes "$NETBIRD_NODE" apply-config \
  --file "$NETBIRD_CONFIG_PATH" \
  --mode=no-reboot

shred -u "$NETBIRD_CONFIG_PATH" "$NETBIRD_DRY_RUN_PATH"
trap - EXIT
unset KUBERNETES_NODE NETBIRD_CONFIG_PATH NETBIRD_DRY_RUN_PATH NETBIRD_EXTRA_DOCUMENTS NETBIRD_NODE NETBIRD_SOURCE_PATH
```

Perform the dry run while the placeholder is still present so no real key appears in the diff. Keep the output private because unchanged context can contain existing machine-configuration secrets. It must add only one `ExtensionServiceConfig` document named `netbird`. On the OptiPlex, the diff must not delete or alter `VolumeConfig/EPHEMERAL` or `UserVolumeConfig/longhorn`. Applying the NetBird document alone removes those auxiliary documents and is prohibited.

## Rollout order

Upgrade one node at a time and stop at the first failed gate.

### 1. OptiPlex worker canary

Before the upgrade, confirm every attached Longhorn volume is healthy and every volume has two replicas with no failed replica. Enroll `192.168.1.10`, then run:

```bash
talosctl upgrade --nodes 192.168.1.10 \
  --image factory.talos.dev/metal-installer/f141fc2a08d5a459a80d871faa48d7dc92bc354e4faf6cdbafe1cc0fac717991:v1.12.11 \
  --wait
```

Do not continue until:

- the node is Ready and reports Talos v1.12.11;
- Kubernetes still reports `192.168.1.10` as the node `InternalIP`, and `kubectl logs` or `kubectl exec` can reach a pod on it;
- `talosctl get extensions` lists `netbird`, `intel-ucode`, `iscsi-tools`, and `util-linux-tools`;
- `talosctl service ext-netbird` is healthy and its logs contain no enrollment loop;
- `u-longhorn` is mounted at `/var/mnt/longhorn`;
- every attached Longhorn volume returns to healthy and every volume has two non-failed replicas;
- the workstation reaches the node's Talos API over NetBird from a genuinely external network.

### 2. Single control plane

Before upgrading `192.168.1.8`:

1. Confirm the Kubernetes API, etcd, and all Argo CD applications are healthy.
2. Save a fresh etcd snapshot and the current live machine configuration outside the cluster.
3. Verify the snapshot is non-empty and stored off the Talos node.
4. Keep local physical-console access available until NetBird recovery access is proven.
5. Enroll the node with its own one-off control-plane key.

```bash
talosctl upgrade --nodes 192.168.1.8 \
  --image factory.talos.dev/metal-installer/7326f0cbca7a0e700ac1efa3f32e88df9ebe5010e6e842a8ed36fdc99ee98ead:v1.12.11 \
  --wait
```

After it returns, validate etcd, the Kubernetes API, all applications, TCP 50000, and TCP 6443 through the NetBird peer address. Use a separate kubeconfig whose `server` is the NetBird address and whose `tls-server-name` is `talos-k3t-9cz`; the current API certificate already includes that hostname.

### 3. Nitro worker

Enroll and upgrade `192.168.1.9` only after the first two nodes pass. Use the NVIDIA installer from the table. Verify the NetBird service, Longhorn mount and replicas, NVIDIA extension versions, kernel module state, and device-plugin behavior before declaring the rollout complete.

## Rollback

Before the NetBird path is proven, rollback still depends on LAN or physical-console access.

- Stop after any failed gate. Do not upgrade the next node.
- Use `talosctl rollback --nodes <node> --wait` while its Talos API is reachable. The A-B image scheme restores the previous v1.11.5 image and removes the NetBird binary from the active system.
- A used one-off setup key has no remaining enrollment authority. Remove the failed peer from NetBird after rollback.
- On the OptiPlex, verify `u-longhorn` and `/var/mnt/longhorn` again after rollback.
- If the single control plane cannot recover through automatic or API rollback, use the saved machine configuration and etcd snapshot with the documented Talos disaster-recovery procedure.

Successful installation is not sufficient evidence. Remote access is complete only after it works from outside the home network while the workstation has no LAN route to Devata.
