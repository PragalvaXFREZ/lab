# kubernetes

Authoritative cluster state. **This is the only path the GitOps controller watches.** Everything under here is reconciled back to git if it drifts, so nothing lands here that should not be reverted automatically.

- [`bootstrap/`](./bootstrap) the GitOps controller install and the single root application applied once by hand to start reconciliation.
- [`clusters/`](./clusters) per cluster entry points: the app of apps and ApplicationSets that tell the controller what to deploy.
- [`infra/`](./infra) the platform layer, the components that make the cluster usable.
- [`apps/`](./apps) the workloads that run on top of the platform.

For the rules that govern this path, see [`../docs/conventions.md`](../docs/conventions.md).
