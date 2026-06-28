# 0001 - Repository structure

- Status: accepted
- Date: 2026-06-28

## Context

This repository is moving from a notebook of homelab experiments to the declarative source of truth for the devata cluster. A series of workstreams is planned over the coming months: a GitOps backbone, secrets management, ingress and TLS, an outbound tunnel, storage durability, and real workloads. If the layout is settled only as that content arrives, the repo grows by repeated restructuring, and every reader has to relearn where things are.

The repo also has to do double duty. It is both authoritative cluster state and a public, portfolio grade record of the learning behind it. Those two things must not blur together: authoritative state has to be safe for a reconciler to enforce, while the learning sandbox has to be safe to break.

## Decision

Settle the skeleton and the conventions first, before the bulk of the content arrives, so the repo grows by addition rather than by reshuffle.

The repository is organised as three planes plus a sandbox:

- **OS and machine** in `talos/`, version controlled but applied with `talosctl`.
- **Platform** in `kubernetes/infra/`: networking, controllers, observability, ingress, storage.
- **Workloads** in `kubernetes/apps/`.
- **Sandbox** in `lab-experiments/`, outside all of the above.

The load bearing rule is the GitOps boundary: the controller watches only `kubernetes/`, which is therefore the only authoritative, reconciled path. `talos/` is the operating system layer and is applied out of band. `lab-experiments/` is never reconciled, which is what makes it safe to experiment in.

The full set of hygiene rules lives in [`../conventions.md`](../conventions.md).

The existing `ansible-1/` directory was renamed to `ansible/` to match this layout, since the target names a single `ansible/` area for host bootstrap and automation. Pre-existing learning directories (`kubernetes-fundamentals/`, `blogs/`, and the bash scripting notes) are left in place; they are records, not authoritative state.

## Consequences

- Each planned workstream has a home that already exists, so adding it does not require moving a directory. That is the explicit test the structure is meant to pass.
- A first time reader can tell authoritative state (`kubernetes/`) from the sandbox (`lab-experiments/`) and from the machine layer (`talos/`) at a glance.
- The skeleton ships as directories carrying short purpose READMEs and nothing the reconciler could not safely revert. The actual components land later, each under its own issue.
- A second cluster is a new folder under `kubernetes/clusters/`, reusing the same `infra/` and `apps/`, rather than a fork of the structure.
