# 0006 - Archive Uptime Kuma

- Status: accepted
- Date: 2026-10-10

## Context

Devata has limited resources. Uptime Kuma was not used much in my case, so keeping an always-on monitor and its storage did not justify the cost.

## Decision

Remove Uptime Kuma from the reconciled cluster, including its Gateway route, certificate hostname, cross-namespace grant, and cloudflared backend permission. Preserve the former manifests under `archive/uptime-kuma/` for reference and recovery.

Keep the existing Prometheus, Alertmanager, and off-cluster snapshot heartbeat. The portfolio keeps a grayscale entry marked Archived. The historical note remains in the private vault.

## Consequences

- Kuma no longer runs outbound checks or sends notifications.
- Back up the `uptime` namespace with Velero file-system backup before deleting its claim. Confirm the backup and pod-volume backup completed; the backup expires after 30 days.
- The former Application has no cascading-deletion finalizer. After Argo removes it, explicitly delete its orphaned Deployment, Service, network policy, recurring job, and PVC. Do not delete the namespace until the backup succeeds.
- Cloudflare tunnel, Access, and DNS settings are remotely managed. Removing the Gateway route makes the old hostname unable to reach Kuma; external entries can be removed separately.
- Recovery requires restoring the archived sources and exposure configuration, then restoring monitor data from the backup while it remains available.
