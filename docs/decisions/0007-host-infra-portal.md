# 0007 - Host infra-portal from its own repository

- Status: accepted
- Date: 2026-11-05

## Context

infra-portal is a web application for member profiles and blogs, served at `infra.pragalva.me`. It is the
first first-party application on devata that accepts input from people other than the operator. Other
people also read it as a worked example, so its code must be readable without knowledge of devata.

## Decision

- The application source, tests, image build, and migrations live in
  [PragalvaXFREZ/infra-portal](https://github.com/PragalvaXFREZ/infra-portal). Its CI publishes
  `ghcr.io/pragalvaxfrez/infra-portal`.
- This repository holds only how devata runs it, in `kubernetes/apps/infra-portal/`: the pinned image
  digest, PostgreSQL, sealed secrets, network policy, and the cross-namespace grant. The route, the
  certificate hostname, and the cloudflared permission live with their platform components.
- A release is a pull request here that changes the image digest. A merge in the application repository
  never changes the cluster by itself.
- PostgreSQL runs as a single-instance StatefulSet on a Longhorn volume with two replicas, not through
  CloudNativePG. The CloudNativePG failover and recovery proof remains a separate goal.
- Migrations run as an Argo CD Sync hook between PostgreSQL and the Deployment.

## Consequences

- A release needs two pull requests: one in the application repository, one here.
- Rollback is a revert of the digest change. A migration is not rolled back by a revert, so migrations must
  stay additive.
- There is no scheduled off-cluster backup, consistent with the Velero capacity contract. Longhorn
  replicas protect against the loss of one node, not against deletion or corruption. Take an on-demand
  Velero file-system backup or a `pg_dump` before a risky migration.
- The site is public. Invite-only GitHub sign-in protects writing, and the database accepts connections
  only from the application and its migration job.
