# nvidia-device-plugin

The NVIDIA [k8s-device-plugin](https://github.com/NVIDIA/k8s-device-plugin) DaemonSet, the first component migrated from a hand-installed Helm release into GitOps. It advertises `nvidia.com/gpu` to the scheduler on nodes with a working GPU.

On devata it currently advertises nothing: the GTX 1650 Ti on `talos-lqv-w4u` is a confirmed hardware fault, so the DaemonSet runs but finds no usable device. That is exactly why it is the safe first adoption, a real chart whose failure cannot hurt the cluster.

`values.yaml` here is the recovered Helm override. The child Application is [`../../../clusters/devata/nvidia-device-plugin.yaml`](../../../clusters/devata/nvidia-device-plugin.yaml); it starts with automation off and is turned on once `argocd app diff` is empty. The full procedure is the migrating-the-imperative-stack chapter in the homelab vault.

The `nvidia` RuntimeClass the DaemonSet runs under is reconciled from [`runtimeclass/`](./runtimeclass) as a third source of the same Application, the kps secrets pattern. It graduated from the gpu-enable experiment in `lab-experiments/`.
