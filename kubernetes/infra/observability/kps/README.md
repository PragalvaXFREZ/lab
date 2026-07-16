# kps (kube-prometheus-stack)

The [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) chart, running as release `kps` in the `monitoring` namespace: the Prometheus operator, Prometheus itself, Grafana, node-exporter, and kube-state-metrics. The second component migrated from a hand-installed Helm release into GitOps, and the first that is not plain: the chart ships CRDs that need `ServerSideApply=true`, and its recovered values carried the Grafana admin password.

That password never enters git in plaintext. The encrypted `grafana-admin` SealedSecret lives under `secrets/`, and `values.yaml` points the chart at the Secret it reconciles through `grafana.admin.existingSecret`.

`values.yaml` here is the recovered Helm override, minus the password. The child Application is [`../../../clusters/devata/kps.yaml`](../../../clusters/devata/kps.yaml). The full adoption procedure is the adopting-kube-prometheus-stack note in the homelab vault.

The `resources/` directory contains persistent claims whose lifecycle is independent of the chart. Grafana uses a named Longhorn claim so its previous local-path claim can remain intact as a rollback point during storage transitions.
