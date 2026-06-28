# devata

This repository is the declarative source of truth for **devata**, my home Kubernetes cluster, and the public log of how it is built. The aim is a portfolio grade repo where the whole cluster is defined as code, the learning sandbox stays clearly separated from authoritative state, and every workstream planned over the coming months already has an obvious place to land.

devata runs [Talos Linux](https://www.talos.dev/) and is reconciled with GitOps. The operating system is version controlled here but applied out of band with `talosctl`; everything from the platform up is Kubernetes state that a GitOps controller reconciles from this repository.

## Architecture

The repository is organised as three planes, kept separate on purpose, plus a sandbox that sits outside all of them.

1. **OS and machine** lives in [`talos/`](./talos). Node configuration, reusable patches, and Image Factory schematics. Version controlled for history and review, applied with `talosctl`. This is the GitOps boundary: the reconciler manages Kubernetes objects, not the operating system.

2. **Platform** lives in [`kubernetes/infra/`](./kubernetes/infra). The components that make the cluster usable: networking, controllers, observability, ingress, and storage.

3. **Workloads** live in [`kubernetes/apps/`](./kubernetes/apps). The things that run on top of the platform.

The **sandbox** in [`lab-experiments/`](./lab-experiments) is where things get broken on purpose. The GitOps controller never points at it, which is what makes it safe to experiment in without fighting the reconciler.

The single most important rule that follows from this: **the GitOps controller watches only `kubernetes/`.** Everything under that path is authoritative and is reconciled back to git if it drifts. Nothing else is.

## Repository map

```
lab/
├── README.md                  # this file: what devata is, the architecture, the map
├── docs/
│   ├── conventions.md         # the hygiene rules this repo lives by
│   └── decisions/             # architecture decision records (why, not just what)
│
├── talos/                     # OS and machine layer, applied by talosctl, NOT reconciled by GitOps
│   ├── machineconfigs/        # per node configuration
│   ├── patches/               # reusable config patches
│   └── schematics/            # Image Factory schematics (system extensions, kernel args)
│
├── kubernetes/                # authoritative cluster state, the ONLY path the GitOps controller watches
│   ├── bootstrap/             # the GitOps controller install and the single root app applied once by hand
│   ├── clusters/
│   │   └── devata/            # the app of apps and ApplicationSets for this cluster
│   ├── infra/                 # the platform layer
│   │   ├── networking/        # cilium, metallb, gateway and routes
│   │   ├── controllers/       # cert-manager, sealed-secrets, and similar operators
│   │   ├── observability/     # prometheus stack, loki, promtail, dashboards
│   │   ├── ingress/           # gateways and the cloudflared tunnel
│   │   └── storage/           # storage classes today, longhorn and velero later
│   └── apps/                  # workloads
│       └── showcase/          # the snapshot publisher, and future apps beside it
│
├── ansible/                   # host bootstrap and automation
│
├── lab-experiments/           # the sandbox, the reconciler NEVER points here, safe to break
│   └── kubernetes/            # practice manifests and one off experiments
│
├── kubernetes-fundamentals/   # learning notes
└── blogs/                     # published write ups
```

## Conventions

This repo is run declaratively, and the rules that keep it that way are written down in [`docs/conventions.md`](./docs/conventions.md) so they outlive any single session. The short version: declarative only, secrets are encrypted before they are committed, the OS layer is applied separately, and one concern lives in one directory and graduates rather than being copied.

The reasoning behind the structure itself is recorded as [ADR 0001](./docs/decisions/0001-repository-structure.md).

## Status

The skeleton and conventions are in place. The contents land next, each under its own issue: the GitOps backbone, Sealed Secrets, ingress and TLS, the outbound tunnel, the snapshot publisher, and storage durability.
