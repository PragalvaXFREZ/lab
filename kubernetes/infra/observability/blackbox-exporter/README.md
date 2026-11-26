# blackbox-exporter

The [prometheus-blackbox-exporter](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-blackbox-exporter) chart, running as one replica in the `monitoring` namespace. Prometheus uses it to probe the ProBook host outside the cluster at `192.168.1.8` (see [ADR 0005](../../../../docs/decisions/0005-probook-leaves-the-cluster.md)).

The child Application is [`../../../clusters/devata/blackbox-exporter.yaml`](../../../clusters/devata/blackbox-exporter.yaml). It installs the chart with `values.yaml` and applies the plain manifests in `resources/`.

## Files

- `values.yaml` defines the `icmp` and `tcp_connect` modules, the security context, and resource limits.
- `resources/probe.yaml` is the `Probe` that Prometheus selects through its `release: kps` label. It probes every 60 seconds as job `probook`.
- `resources/prometheus-rule.yaml` alerts when every probe fails for 10 minutes, and when no probe result exists for 15 minutes.

## Modules

The Probe uses the `icmp` module. The `tcp_connect` module is configured as an alternative: swap the `module` and target lines in `resources/probe.yaml` for the commented ones.

The exporter tries an unprivileged ICMP socket before a raw one. The pod sets `net.ipv4.ping_group_range` to the exporter group, so ICMP works without a capability and the container keeps the chart default security context: UID and GID 1000, non-root, read-only root filesystem, and every capability dropped. The `tcp_connect` module needs no special privilege.

## Verification

```bash
kubectl -n monitoring get deploy,svc blackbox-exporter
kubectl -n monitoring get probe probook
```

`probe_success{job="probook"}` must return `1` in Prometheus. To see the prober's own log of one attempt, port-forward the Service and request `/probe?target=192.168.1.8&module=icmp&debug=true`.

## Rollback

Revert the change in git. Argo CD prunes the exporter, the Probe, and its rule. No state is kept.
