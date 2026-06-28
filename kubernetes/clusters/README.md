# clusters

One folder per cluster. Each holds that cluster's entry point for the GitOps controller: the app of apps and any ApplicationSets that select which pieces of `infra/` and `apps/` it runs.

A second cluster is added as a new folder here beside `devata`, reusing the same shared `infra/` and `apps/` rather than forking them.

- [`devata/`](./devata) the home cluster.
