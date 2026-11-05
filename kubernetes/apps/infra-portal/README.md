# infra-portal

Member profiles and blogs at `https://infra.pragalva.me`. The application is built in
[PragalvaXFREZ/infra-portal](https://github.com/PragalvaXFREZ/infra-portal); this folder only runs it.
[ADR 0007](../../../docs/decisions/0007-host-infra-portal.md) records the split.

## Request path

```
browser -> Cloudflare -> cloudflared -> Cilium Gateway (infra.lab.pragalva.me) -> Service infra-portal:80 -> pod :8000
```

## Files

| File | Purpose |
| --- | --- |
| `postgres.yaml` | Single-instance PostgreSQL 18, 2 GiB Longhorn volume. Sync wave 0. |
| `migrate-job.yaml` | Alembic migrations as an Argo CD Sync hook. Sync wave 1. |
| `deployment.yaml` | The application and its Service. Sync wave 2. |
| `network-policy.yaml` | Default deny for every pod, with the flows below allowed. |
| `reference-grant.yaml` | Lets the HTTPRoute in `gateway-system` reach the Service. |
| `sealedsecret-db.yaml` | `POSTGRES_PASSWORD` and `DATABASE_URL`. |
| `sealedsecret-session.yaml` | `SESSION_SECRET` for the session cookie. |
| `sealedsecret-github.yaml` | `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET`. Optional: without it, the site runs and sign-in returns 503. |

## Allowed flows

| From | To | Port |
| --- | --- | --- |
| Gateway (`ingress` identity) | app | 8000 |
| app | kube-dns | 53 |
| app | postgres | 5432 |
| app | `github.com`, `api.github.com` | 443 |
| migration job | kube-dns, postgres | 53, 5432 |

PostgreSQL opens no outbound connections.

## Release

1. A merge to `main` in the application repository publishes a new image. The CI run summary prints the
   reference: `ghcr.io/pragalvaxfrez/infra-portal:sha-<short>@sha256:<digest>`.
2. Change the image in both `deployment.yaml` and `migrate-job.yaml` to that reference, in one pull
   request.
3. After merge, Argo CD runs the migration hook and then rolls the Deployment.

## Secrets

Seal from a file outside every repository, so values never appear in the shell history or in git:

```bash
kubectl create secret generic infra-portal-github -n infra-portal --dry-run=client -o yaml \
  --from-env-file="$HOME/.config/infra-portal/github.env" \
  | kubeseal --context pragalva@devata --format yaml > sealedsecret-github.yaml
```

`~/.config/infra-portal/github.env` holds `GITHUB_CLIENT_ID=` and `GITHUB_CLIENT_SECRET=` lines from the production GitHub OAuth
app, whose callback URL is `https://infra.pragalva.me/auth/github/callback`.

## Verification

```bash
kubectl -n infra-portal get statefulset,deployment,pod,pvc
kubectl -n infra-portal logs job/infra-portal-migrate
kubectl -n gateway-system get httproute infra-portal -o jsonpath='{.status.parents[0].conditions}'
curl -fsS https://infra.pragalva.me/readyz
```

`/readyz` must return `{"status":"ok","database":"reachable"}`. Stop PostgreSQL only in a planned test:
`/readyz` must turn to 503 and `/livez` must stay 200, and the app pod must not restart.

## Backup and rollback

- Before a risky migration: `kubectl -n infra-portal exec statefulset/postgres -- pg_dump -U portal portal > portal.sql`.
- Roll back a release by reverting the image change. Migrations are additive, so the old version runs on
  the newer schema.
- Remove the workload by deleting the Application. The PVC uses the `Delete` reclaim policy, so take a
  dump first.
