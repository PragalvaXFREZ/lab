# apps

The workloads that run on top of the platform. Each app is its own folder, with its manifests and any encrypted secrets it needs co-located inside it.

New workloads are added as new folders here, which is what lets the cluster grow without touching the platform layer.

- [`showcase/`](./showcase) public evidence producers, including durable snapshots and aggregate traffic streams.
