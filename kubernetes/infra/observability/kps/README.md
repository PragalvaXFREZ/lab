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
- **What is delivered.** `warning` and `critical` alerts go to the `discord` receiver, which posts to the `#homelab-alerts` channel, including a message when they resolve. `Watchdog` and `InfoInhibitor` go to `null`. Alerts from the hand-made practice namespaces `dev`, `bootcamp`, `example-namespace` and `networking-namespace` go to `null`; `default` is not in that list because the apiserver targets carry `namespace="default"`. Info and unlabelled alerts stay on the root `null` receiver.
- **Message.** The title carries the status, the number of firing alerts, the alert name and the severity. The body carries the namespace, the common summary, and one line per alert with its description, marked when resolved. Alertmanager truncates the title at 256 and the body at 4096 characters.
- **Webhook Secret.** The webhook URL lives only in the Secret `alertmanager-discord-webhook`, key `url`, in `monitoring`, reconciled from the SealedSecret `secrets/alertmanager-discord-webhook.yaml`. The operator reads it through `discordConfigs[].apiURL` and writes it into the generated configuration Secret; the Alertmanager status page shows it as `<secret>`. The operator in this chart version does not accept `webhook_url_file` for Discord, so the Secret is not mounted into the pod. If the Secret is missing or its value is not a valid URL, the operator stops reconciling the Alertmanager and the CR reports `Reconciled` false: a running pod keeps its previous configuration, and no pod is created if none exists yet. The Secret has to exist before this routing reaches the cluster.
- **Grouping.** One group per alert name and namespace, a 1m first wait, 10m between updates to a group, and a 24h repeat.
- **Inhibition.** The chart's default inhibit rules, unchanged: critical inhibits warning and info, warning inhibits info, both per alert name and namespace, and `InfoInhibitor` inhibits info alerts in a namespace with nothing more severe firing.
- **Disabled rule.** `KubeMemoryQuotaOvercommit` is disabled in `defaultRules.disabled`. It sums every ResourceQuota in the cluster, carries no namespace, and today measures only a practice quota that is not in git.
- **Other AlertmanagerConfig objects.** The chart selects AlertmanagerConfig objects in every namespace. Any such object adds routes for its own namespace on top of this configuration.
- **Verify.** The Alertmanager CR reports `Reconciled` true. In Prometheus, `prometheus_notifications_alertmanagers_discovered` is 1 and `PrometheusNotConnectedToAlertmanagers` resolves. `alertmanager_config_last_reload_successful` is 1. The Alertmanager UI lists the firing alerts and the receiver each one routes to. Delivery shows in Alertmanager's own metrics: `alertmanager_notifications_total{integration="discord"}` grows with each message and `alertmanager_notifications_failed_total{integration="discord"}` stays flat. A template error or a rejected webhook counts as a failed notification, not as a message.
- **Rollback.** Reverting the commit that added the `discord` receiver returns delivery to `null`; the Secret can stay. Reverting the commit that enabled Alertmanager removes it; Argo CD prunes the Alertmanager and its routing object, and Prometheus keeps evaluating rules.
- **Limits.** Silences and the notification log are kept in an emptyDir and are lost when the pod restarts; after a restart, every alert that is still firing counts as new. There is one replica. There is no dead man's switch outside the cluster: nothing receives `Watchdog`, so if the control plane node stops, Prometheus stops with it and nothing alerts. `AlertmanagerFailedToSendAlerts` routes to the same Discord receiver, so a broken webhook shows only in the metrics above and in the Alertmanager log.

## Scrape targets

Prometheus selects every ServiceMonitor, PodMonitor, and PrometheusRule in the cluster without a label. Probes and ScrapeConfigs need the `release: kps` label.

`resources/argocd-service-monitor.yaml` scrapes the Argo CD metrics Services in the `argocd` namespace: `argocd-metrics`, `argocd-server-metrics`, `argocd-repo-server`, `argocd-applicationset-controller`, and `argocd-notifications-controller-metrics`. The job label is the Service name. It lives here rather than beside the Argo CD installation because the bootstrap is applied before the ServiceMonitor CRD exists and the `argocd` Application does not prune. It drops the pre-registered gRPC server series and per-request histograms, which are most of what Argo CD exports.

Longhorn, Velero, and the blackbox exporter declare their own scrape objects beside their charts. To confirm every Argo CD target is up:

```promql
up{namespace="argocd"}
```

Reverting a file in `resources/` removes the object, because the kps Application prunes.

## Alert rules

`resources/` also holds the PrometheusRules for components whose own Applications have no suitable directory source: `argocd-prometheus-rule.yaml`, `longhorn-prometheus-rule.yaml`, and `velero-prometheus-rule.yaml`. Argo CD's source is the bootstrap kustomization, Longhorn has no directory source, and Velero's only directory source holds its encrypted credentials. kps also owns the CRDs these rules need. Every rule waits long enough to ignore a normal sync, a single pod restart, or one slow scrape, and none fires on a healthy cluster.

- Argo CD: an automatically synced Application not `Synced`, or any Application not `Healthy`, for 30 minutes.
- Longhorn: a faulted volume for 10 minutes; a degraded volume for 30 minutes; a node or disk not ready for 15 minutes; a node or disk not schedulable, or a disk over 85 percent full, for 30 minutes. Detached volumes report robustness `unknown`, so they match only when Longhorn keeps a detached volume `faulted` because no replica is usable.
- Velero: a failed, rejected, or partially failed backup in the last hour; the backup storage location unavailable for 30 minutes.

The chart's default `TargetDown` rule already covers every new scrape target: it fires when more than 10 percent of the targets of any job are down for 10 minutes. To list what is firing:

```promql
ALERTS{alertstate="firing", alertname=~"ArgoCD.*|Longhorn.*|Velero.*"}
```

## Prometheus memory

The Prometheus memory limit covers the process and the page cache it reads its blocks through. With too little room for cache, the rules that look back 3 and 30 days over the API server histograms re-read blocks from disk on every evaluation, run longer than their interval, and `PrometheusMissingRuleEvaluations` fires. The API server exports one histogram series per resource, verb and bucket, so each new CRD adds series; `kubeApiServer.serviceMonitor.metricRelabelings` drops the size and watch histograms that no rule or dashboard reads.

- **Verify.** `prometheus_rule_group_last_duration_seconds` stays below each group's interval, and `sum(increase(prometheus_rule_group_iterations_missed_total[10m]))` is 0. `container_memory_cache{namespace="monitoring", container="prometheus"}` shows the cache the container keeps.
- **Limits.** A dropped series stays in the head until the next truncation, about two to three hours.

## Devata overview dashboard

`resources/devata-overview-dashboard.yaml` is the source of truth for Grafana's home dashboard. The Grafana sidecar discovers its `grafana_dashboard: "1"` label, uses the `grafana_folder` annotation to place it in the `Devata` folder, and reloads it when the ConfigMap changes. `grafana.ini` points the server-wide home view at the same provisioned JSON file.

The dashboard starts with aggregate signals that Prometheus already scrapes: node readiness, target health, firing alerts, workload state, node CPU and memory, Hubble traffic and drops, and CoreDNS response errors. It links to the chart-provided Kubernetes, node-exporter, Cilium, and Prometheus dashboards for component drill-down.

The provisioned dashboard is not editable in the Grafana UI. Change its JSON in git, validate the ConfigMap, and let Argo CD reconcile it. Prometheus scrapes Argo CD, Longhorn, and Velero, but the overview has no direct panels for them yet.
