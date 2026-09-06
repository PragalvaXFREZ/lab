# uptime-kuma

Uptime Kuma runs outbound HTTP and ICMP checks against endpoints the operator cares about and posts state changes to a Discord webhook. It is an operator convenience, not a service anyone else depends on: its own availability is bounded by devata's, and devata is a homelab behind a residential uplink. Anything that must alert when the homelab itself is down needs an external watcher, which this component deliberately does not try to be.

The component exists alongside kube-prometheus-stack on purpose. Prometheus and Alertmanager watch the cluster from inside. Kuma watches the world from the cluster's point of view, with a status page and a notification path that takes a minute to configure rather than a ruleset. The two do not share alert routes.

## Safety model

- **Outbound only, with an allowlist.** The CiliumNetworkPolicy permits DNS, TCP 80 and 443 to the world, and ICMP echo. Inbound is accepted only from the Cilium ingress identity, which is the LAN Gateway's Envoy. A monitor on another port fails until the policy grows an explicit entry.
- **Bounded memory.** The pod requests 128Mi and is limited to 256Mi. No CPU limit, because the checks are bursty and the node is otherwise idle.
- **Reduced privileges under a root image.** The upstream image runs as root, which the baseline Pod Security level allows. Privilege escalation is off, all capabilities are dropped, and only `NET_RAW` is added back so ping monitors can open raw sockets.
- **Repository-owned volume.** The claim is declared in `resources/pvc.yaml` so its StorageClass and labels stay under Git control. The chart is told to use it rather than create its own.

## Placement and storage

The pod is pinned to the Nitro worker by hostname, following the Velero precedent. That node has the most free memory and the volume replicates to both workers, so the pin is about resource budget, not data locality.

The 1Gi Longhorn volume holds the SQLite database. Kuma prunes heartbeat history by its own retention setting, so growth is bounded. The volume is not covered by a Velero schedule: Velero's R2 target has a documented capacity ceiling and a no-unattended-schedule contract. An on-demand Velero backup with file-system backup opted in for this pod volume is the supported off-cluster path.

## Files

| File | What it is |
| --- | --- |
| `values.yaml` | Chart overrides: existing claim, Recreate strategy, node pin, resources, security context |
| `resources/pvc.yaml` | The Longhorn claim |
| `resources/network-policy.yaml` | The egress allowlist and ingress restriction |
| `../../clusters/devata/uptime-kuma.yaml` | The Argo CD Application wiring chart, values, and resources |

The chart is `uptime-kuma` from `helm.irsigler.cloud`, pinned in the Application. Renovate proposes bumps.

## Verification

```sh
kubectl -n uptime get deploy,pod,pvc,ciliumnetworkpolicy
kubectl -n longhorn-system get volumes.longhorn.io
kubectl -n uptime port-forward svc/uptime-kuma 3001:3001
```

The pod must be `Running` on `talos-lqv-w4u` with the claim `Bound` to a Longhorn volume showing two healthy replicas. The first visit to the port-forward creates the admin account. A test HTTP monitor must turn green and a monitor against a port outside the allowlist must stay red, which proves the policy is enforced rather than merely present. A test notification to the Discord webhook must arrive.

## Rollback

Remove the Application. Argo CD prunes the Deployment, Service, policy, and claim; Longhorn deletes the volume because the StorageClass reclaim policy is `Delete`. Take an on-demand Velero backup first if the monitor configuration is worth keeping.

## Known limitations

- Single replica. A node drain restarts the pod and loses in-flight checks for the restart window.
- The admin credential and the Discord webhook live inside the SQLite database, not in a Secret. They are only as backed up as the volume is.
- ICMP monitors to IPv6 targets are not in the policy.
