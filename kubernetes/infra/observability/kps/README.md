# kps (kube-prometheus-stack)

The [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) chart, running as release `kps` in the `monitoring` namespace: the Prometheus operator, Prometheus itself, Alertmanager, Grafana, node-exporter, and kube-state-metrics. The second component migrated from a hand-installed Helm release into GitOps, and the first that is not plain: the chart ships CRDs that need `ServerSideApply=true`, and its recovered values carried the Grafana admin password.

That password never enters git in plaintext. The encrypted `grafana-admin` SealedSecret lives under `secrets/`, and `values.yaml` points the chart at the Secret it reconciles through `grafana.admin.existingSecret`.

`values.yaml` here is the recovered Helm override, minus the password. The child Application is [`../../../clusters/devata/kps.yaml`](../../../clusters/devata/kps.yaml). The full adoption procedure is the adopting-kube-prometheus-stack note in the homelab vault.

The `resources/` directory contains objects whose lifecycle is independent of the chart: the Grafana claim, the overview dashboard, the control plane scrape targets, and the Alertmanager routing. Grafana uses a named Longhorn claim so its previous local-path claim can remain intact as a rollback point during storage transitions.

## Control plane scrape targets

`resources/control-plane-scrape.yaml` is the source of truth for the kube-scheduler, kube-controller-manager and etcd scrape targets. It holds one `ScrapeConfig` per component, each with a static target on the control plane node. The chart's own path for these components is a selector-less Service with a hand-listed `Endpoints` object, and Argo CD excludes `Endpoints`, so the chart's Service, Endpoints and ServiceMonitor for all three are turned off in `values.yaml`. `enabled` stays `true` for each component, because the chart gates the matching alert rules and dashboards on it.

- **Labels.** `jobName` sets `job` to `kube-scheduler`, `kube-controller-manager` and `kube-etcd`, which the chart's rules and dashboards select on. A static `namespace: kube-system` label keeps alerts for these targets in the namespace they had before. The `service` and `endpoint` labels that a ServiceMonitor adds are not present; no chart rule or dashboard filters on them.
- **Authentication.** The two HTTPS targets use the `service-account-token` scrape class defined in `prometheus.prometheusSpec.scrapeClasses`, which sends the token of the Prometheus ServiceAccount. Certificate verification is skipped because these components serve self-signed certificates. The class is not a default class, so no other target receives the token. etcd serves plain HTTP metrics on 2381 without authentication.
- **Change.** Each address appears once, in its `ScrapeConfig`. Changing it in git changes the scrape after Argo CD syncs; no manual command is needed.
- **Verify.** In Prometheus, `count by (job) (up{job=~"kube-scheduler|kube-controller-manager|kube-etcd"} == 1)` returns 1 for each job, and the targets page lists them under `scrapeConfig/monitoring/<name>`. The `ScrapeConfig` objects show no rejection in the operator log.
- **Rollback.** Revert the commit. The chart then renders its Services and ServiceMonitors again, but Argo CD still does not apply the chart's `Endpoints`, so the targets stay missing until `Endpoints` objects are created by hand. Fixing forward in this file is the faster path.
- **Limits.** A second control plane node needs its address added to each of the three `ScrapeConfig` objects.

## Alertmanager

Alertmanager receives every alert that Prometheus fires, groups it, applies inhibit rules, and routes it to a receiver. It runs as one replica with a small memory limit and no volume.

- **Routing.** `resources/alertmanager-routing.yaml` is the source of truth. `alertmanagerSpec.alertmanagerConfiguration` in `values.yaml` loads it as the global configuration, so the chart's own `alertmanager.config` is rendered but not read. The operator prefixes receiver names with `monitoring/alertmanager-routing/`.
- **What is delivered.** Every route ends in the `null` receiver, so nothing leaves the cluster. `Watchdog` and `InfoInhibitor` go to `null`. Alerts from the hand-made practice namespaces `dev`, `bootcamp`, `example-namespace` and `networking-namespace` go to `null`; `default` is not in that list because the apiserver targets carry `namespace="default"`. The last route takes `warning` and `critical` alerts and is the one a real receiver replaces. Info and unlabelled alerts stay on the root `null` receiver.
- **Grouping.** One group per alert name and namespace, a 1m first wait, 10m between updates to a group, and a 24h repeat.
- **Inhibition.** The chart's default inhibit rules, unchanged: critical inhibits warning and info, warning inhibits info, both per alert name and namespace, and `InfoInhibitor` inhibits info alerts in a namespace with nothing more severe firing.
- **Disabled rule.** `KubeMemoryQuotaOvercommit` is disabled in `defaultRules.disabled`. It sums every ResourceQuota in the cluster, carries no namespace, and today measures only a practice quota that is not in git.
- **Other AlertmanagerConfig objects.** The chart selects AlertmanagerConfig objects in every namespace. Any such object adds routes for its own namespace on top of this configuration.
- **Verify.** The Alertmanager CR reports `Reconciled` true. In Prometheus, `prometheus_notifications_alertmanagers_discovered` is 1 and `PrometheusNotConnectedToAlertmanagers` resolves. `alertmanager_config_last_reload_successful` is 1. The Alertmanager UI lists the firing alerts and the receiver each one routes to.
- **Rollback.** Revert the commit. Argo CD prunes the Alertmanager and its routing object; Prometheus keeps evaluating rules.
- **Limits.** Silences and the notification log are kept in an emptyDir and are lost when the pod restarts; after a restart, every alert that is still firing counts as new. There is one replica. Nothing outside the cluster watches `Watchdog`, so if the control plane node stops, nothing alerts.

## Devata overview dashboard

`resources/devata-overview-dashboard.yaml` is the source of truth for Grafana's home dashboard. The Grafana sidecar discovers its `grafana_dashboard: "1"` label, uses the `grafana_folder` annotation to place it in the `Devata` folder, and reloads it when the ConfigMap changes. `grafana.ini` points the server-wide home view at the same provisioned JSON file.

The dashboard starts with aggregate signals that Prometheus already scrapes: node readiness, target health, firing alerts, workload state, node CPU and memory, Hubble traffic and drops, and CoreDNS response errors. It links to the chart-provided Kubernetes, node-exporter, Cilium, and Prometheus dashboards for component drill-down.

The provisioned dashboard is not editable in the Grafana UI. Change its JSON in git, validate the ConfigMap, and let Argo CD reconcile it. Argo CD, Longhorn, and Velero do not yet expose metrics to this Prometheus instance, so the overview deliberately omits direct panels for them until their metrics endpoints are scraped.
