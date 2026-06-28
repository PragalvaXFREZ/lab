# Conventions

These are the rules this repository lives by. They are written down so they outlive any single session and so a first time reader can tell authoritative state from a sandbox at a glance.

## Hygiene rules

- **Declarative only.** If a change is not in a file in this repo, it does not really exist. Hand applied state is drift to be removed, not a source of truth.

- **The GitOps controller watches only `kubernetes/`.** Everything under that path is treated as authoritative and is reconciled back to git if it drifts. Nothing goes there that should not be reverted automatically.

- **The sandbox is never reconciled.** `lab-experiments/` is for breaking things on purpose. Keeping it out of the watched path is what makes it safe to experiment without fighting the reconciler.

- **Secrets are encrypted before they are committed.** Plaintext secrets never enter git. They are committed encrypted, with the controller key in cluster, and co-located with the workload that needs them. The controller private key is backed up off cluster and is the one thing that never lives in this repo.

- **The OS layer is tracked here but applied separately.** `talos/` is under version control for history and review, but it is applied by `talosctl`, not by the GitOps controller.

- **One concern per directory, graduate rather than duplicate.** A manifest that proves out in the sandbox and becomes real infrastructure moves into `kubernetes/infra/`, it is not copied. A component reused across clusters moves up into a shared path.

- **The README is the front door.** Anyone landing on the repo should understand the architecture and where to look from the top level README alone.

## The GitOps boundary

There is one line that the rest of the structure protects: the reconciler manages Kubernetes objects, it does not manage the operating system.

- `talos/` is the machine layer. It is reviewed and versioned here, then applied with `talosctl`. The reconciler never touches it.
- `kubernetes/` is the cluster layer. It is the only path the reconciler watches, and everything in it is authoritative.
- `lab-experiments/` is outside both. Nothing reconciles it, so nothing fights you when you break it.

## How the structure absorbs new work

The layout is meant to grow by addition, not by reshuffling. Each planned workstream already has a home:

- GitOps backbone goes into `kubernetes/bootstrap/` and `kubernetes/clusters/devata/`.
- Secrets management is a controller in `kubernetes/infra/controllers/`, with encrypted secrets beside each app.
- Ingress and TLS are a gateway in `kubernetes/infra/networking/` plus cert-manager in `controllers/`.
- The outbound tunnel is `cloudflared` in `kubernetes/infra/ingress/`.
- The showcase publisher is an app in `kubernetes/apps/showcase/`.
- Storage durability is longhorn and velero in `kubernetes/infra/storage/`, with their Talos extensions in `talos/schematics/`.
- A second cluster is a new folder under `kubernetes/clusters/` beside `devata`, reusing the same `infra/` and `apps/`.
- New workloads are new folders under `kubernetes/apps/`.

The test the structure has to pass: none of that requires moving an existing directory.

## Decisions

Choices that are not obvious from the layout alone are recorded as architecture decision records in [`decisions/`](./decisions). When a decision changes, a new record supersedes the old one rather than editing history.
