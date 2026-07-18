# kps (kube-prometheus-stack)

The [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) chart, running as release `kps` in the `monitoring` namespace: the Prometheus operator, Prometheus itself, Grafana, node-exporter, and kube-state-metrics. The second component migrated from a hand-installed Helm release into GitOps, and the first that is not plain: the chart ships CRDs that need `ServerSideApply=true`, and its recovered values carried the Grafana admin password.

That password never enters git in plaintext. The encrypted `grafana-admin` SealedSecret lives under `secrets/`, and `values.yaml` points the chart at the Secret it reconciles through `grafana.admin.existingSecret`.

`values.yaml` here is the recovered Helm override, minus the password. The child Application is [`../../../clusters/devata/kps.yaml`](../../../clusters/devata/kps.yaml). The full adoption procedure is the adopting-kube-prometheus-stack note in the homelab vault.

The `resources/` directory contains persistent claims whose lifecycle is independent of the chart. Grafana uses a named Longhorn claim so its previous local-path claim can remain intact as a rollback point during storage transitions.

## Devata overview dashboard

`resources/devata-overview-dashboard.yaml` is the source of truth for Grafana's home dashboard. The Grafana sidecar discovers its `grafana_dashboard: "1"` label, uses the `grafana_folder` annotation to place it in the `Devata` folder, and reloads it when the ConfigMap changes. `grafana.ini` points the server-wide home view at the same provisioned JSON file.

The dashboard starts with aggregate signals that Prometheus already scrapes: node readiness, target health, firing alerts, workload state, node CPU and memory, Hubble traffic and drops, and CoreDNS response errors. It links to the chart-provided Kubernetes, node-exporter, Cilium, and Prometheus dashboards for component drill-down.

The provisioned dashboard is not editable in the Grafana UI. Change its JSON in git, validate the ConfigMap, and let Argo CD reconcile it. Argo CD, Longhorn, and Velero do not yet expose metrics to this Prometheus instance, so the overview deliberately omits direct panels for them until their metrics endpoints are scraped.
