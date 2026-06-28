# infra

The platform layer: the components that make the cluster usable, as opposed to the workloads that run on top of it. Everything here is shared across whatever apps the cluster runs.

- [`networking/`](./networking) the CNI and L2/L3 plumbing: cilium, metallb, gateways and routes.
- [`controllers/`](./controllers) cluster wide operators: cert-manager, sealed-secrets, and similar.
- [`observability/`](./observability) metrics, logs, and dashboards: the prometheus stack, loki, promtail.
- [`ingress/`](./ingress) how traffic gets in: gateways and the outbound cloudflared tunnel.
- [`storage/`](./storage) storage classes today, durable volumes and backup later.

A component is promoted here once it proves out in `lab-experiments/` and becomes real infrastructure. It moves, it is not copied.
