# Archived Uptime Kuma configuration

Retired on 2026-10-10 because of resource constraints and limited use. See [ADR 0006](../../docs/decisions/0006-archive-uptime-kuma.md).

These files are historical inputs outside Argo CD's watched path. `application.yaml` and `workload/` retain their former paths internally. Recovery requires moving them back to `kubernetes/clusters/devata/uptime-kuma.yaml` and `kubernetes/apps/uptime-kuma/`, restoring the Gateway and cloudflared configuration from Git history, and restoring monitor data from a backup.
