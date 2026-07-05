# Light up the GPU — devata / talos-lqv-w4u (GTX 1650 Ti, Turing)

Driver: **proprietary, Production 570** (`570.172.08`). Open modules are alpha on Turing → not used.
Endpoint note: talosconfig's default endpoint is wrong, so every command passes `-e 192.168.1.9` explicitly.

Run each rung, then **verify it before moving on**. Each rung is reversible (rollback column).

## Rung 1 — image built ✅
Schematic POSTed to Image Factory. Installer image:
```
factory.talos.dev/installer/26124abcbd408be693df9fe852c80ef1e6cc178e34d7d7d8430a28d1130b4227:v1.11.5
```

## Rung 2 — upgrade the node (REBOOTS it; only DaemonSet pods evicted, all reschedule)
```bash
export TALOSCONFIG=~/talosconfig
talosctl upgrade -e 192.168.1.9 -n 192.168.1.9 \
  --image factory.talos.dev/installer/26124abcbd408be693df9fe852c80ef1e6cc178e34d7d7d8430a28d1130b4227:v1.11.5
```
**Verify:** `talosctl -e 192.168.1.9 -n 192.168.1.9 get extensions` lists the two nvidia extensions;
`talosctl -e 192.168.1.9 -n 192.168.1.9 ls /dev | grep nvidia` shows `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm`.
**Rollback:** `talosctl rollback -e 192.168.1.9 -n 192.168.1.9` (boots the prior A/B entry).

## Rung 3 — load the kernel modules (scoped to this node)
```bash
talosctl patch mc -e 192.168.1.9 -n 192.168.1.9 --patch @gpu-node-patch.yaml
```
**Verify:** `talosctl -e 192.168.1.9 -n 192.168.1.9 read /proc/modules | grep nvidia` shows nvidia, nvidia_uvm, etc.
**Rollback:** re-apply machine config without the patch (or `talosctl patch` removing the modules block).

## Rung 4 — RuntimeClass
```bash
kubectl apply -f runtimeclass.yaml
```
**Rollback:** `kubectl delete -f runtimeclass.yaml`

## Rung 5 — device plugin (advertises nvidia.com/gpu)
```bash
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin && helm repo update
helm install nvidia-device-plugin nvdp/nvidia-device-plugin \
  -n nvidia-device-plugin --create-namespace \
  --version 0.19.3 --set runtimeClassName=nvidia
```
**Verify:** `kubectl get node talos-lqv-w4u -o jsonpath='{.status.allocatable}'` now includes `"nvidia.com/gpu":"1"`.
**Rollback:** `helm uninstall nvidia-device-plugin -n nvidia-device-plugin`

## Final proof — end-to-end
```bash
kubectl apply -f smoke-test.yaml   # runs nvidia-smi in a pod requesting nvidia.com/gpu: 1
kubectl logs job/nvidia-smi
```
A successful `nvidia-smi` table = the whole stack (metal → driver → runtime → device plugin → scheduler) is lit.

---

Graduated: the two schematics now live in `talos/schematics/` (nvidia-production, nvidia-lts535) and the RuntimeClass is reconciled from `kubernetes/infra/controllers/nvidia-device-plugin/runtimeclass/`. This log stays as the record of how they were proven out.
