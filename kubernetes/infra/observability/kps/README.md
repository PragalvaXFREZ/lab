# kps (kube-prometheus-stack)

The [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) chart, running as release `kps` in the `monitoring` namespace: the Prometheus operator, Prometheus itself, Grafana, node-exporter, and kube-state-metrics. The second component migrated from a hand-installed Helm release into GitOps, and the first that is not plain: the chart ships CRDs that need `ServerSideApply=true`, and its recovered values carried the Grafana admin password.

That password never enters git. It lives in a manually created `grafana-admin` Secret in the cluster, and `values.yaml` points the chart at it through `grafana.admin.existingSecret`. Sealing that Secret into git encrypted is the sealed-secrets workstream (issue #8).

`values.yaml` here is the recovered Helm override, minus the password. The child Application is [`../../../clusters/devata/kps.yaml`](../../../clusters/devata/kps.yaml); it starts with automation off and is turned on once `argocd app diff` is empty. The full procedure is the adopting-kube-prometheus-stack note in the homelab vault.
