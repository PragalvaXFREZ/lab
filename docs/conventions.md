# Conventions

These are the rules this repository lives by. They are written down so they outlive any single session and so a first time reader can tell authoritative state from a sandbox at a glance.

## Hygiene rules

- **Declarative only.** If a change is not in a file in this repo, it does not really exist. Hand applied state is drift to be removed, not a source of truth.

- **The GitOps controller watches only `kubernetes/`.** Everything under that path is treated as authoritative and is reconciled back to git if it drifts. Nothing goes there that should not be reverted automatically.

- **The sandbox is never reconciled.** `lab-experiments/` is for breaking things on purpose. Keeping it out of the watched path is what makes it safe to experiment without fighting the reconciler.

- **Secrets are encrypted before they are committed.** Plaintext secrets never enter git. They are committed encrypted, with the controller key in cluster, and co-located with the workload that needs them. The controller private key is backed up off cluster and is the one thing that never lives in this repo.

- **The OS layer is tracked here but applied separately.** `talos/` is under version control for history and review, but it is applied by `talosctl`, not by the GitOps controller.

- **One concern per directory, graduate rather than duplicate.** A manifest that proves out in the sandbox and becomes real infrastructure moves into `kubernetes/infra/`, it is not copied. A component reused across clusters moves up into a shared path.

- **The README is the front door.** Keep the top-level README limited to purpose, architecture, trust boundaries, repository navigation, validation, and links to evidence. Do not put dated progress, status summaries, next steps, or session history there.

## The GitOps boundary

There is one line that the rest of the structure protects: the reconciler manages Kubernetes objects, it does not manage the operating system.

- `talos/` is the machine layer. It is reviewed and versioned here, then applied with `talosctl`. The reconciler never touches it.
- `kubernetes/` is the cluster layer. It is the only path the reconciler watches, and everything in it is authoritative.
- `lab-experiments/` is outside both. Nothing reconciles it, so nothing fights you when you break it.

## Documentation boundaries

- The root README orients a first-time reader and exposes the stable operating contract.
- Component READMEs explain responsibility, inputs, safety boundaries, operation, verification, rollback, and known limitations in present tense.
- Architecture decision records explain why a durable choice was made and are superseded rather than rewritten.
- GitHub issues carry work queues and acceptance criteria. Git and pull requests carry change history.
- Runtime values belong in generated snapshots, badges, and status surfaces. Do not copy them into prose that must be remembered during the next change.
- Session notes, chronological progress, and private planning stay outside this repository.

When a change invalidates a public claim, update or remove that claim in the same pull request.

## Directory ownership

The layout grows by addition rather than reshuffling. Work belongs to the directory that owns its lifecycle:

- GitOps bootstrap belongs in `kubernetes/bootstrap/`; cluster composition belongs in `kubernetes/clusters/devata/`.
- Cluster-wide operators belong in `kubernetes/infra/controllers/`; encrypted workload credentials stay beside their consumer.
- Cluster networking and gateways belong in `kubernetes/infra/networking/`; outbound exposure components belong in `kubernetes/infra/ingress/`.
- Public evidence produced by the cluster belongs in `kubernetes/apps/showcase/`.
- Storage controllers and classes belong in `kubernetes/infra/storage/`; required Talos extensions belong in `talos/schematics/`.
- Another cluster gets its own folder under `kubernetes/clusters/`, reusing shared platform and workload definitions where their contracts match.
- Workloads get their own folders under `kubernetes/apps/`.

The structure passes when new work has one obvious owner and does not require moving unrelated directories.

## Decisions

Choices that are not obvious from the layout alone are recorded as architecture decision records in [`decisions/`](./decisions). When a decision changes, a new record supersedes the old one rather than editing history.
