# cloudflared

Runs two outbound-only connectors for the remotely managed `devata` Cloudflare Tunnel. The tunnel publishes
Grafana and Hubble without opening an inbound port on the home network.

## Request path

Cloudflare owns the public DNS records and routes each public hostname through the tunnel. `cloudflared` sends
both routes to the Cilium Gateway over HTTPS using the existing LAN hostname for certificate verification and
HTTP host routing.

| Public hostname | Origin SNI and HTTP host | Authentication |
| --- | --- | --- |
| `grafana.pragalva.me` | `grafana.lab.pragalva.me` | Grafana login |
| `hubble.pragalva.me` | `hubble.lab.pragalva.me` | Cloudflare Access with connector JWT enforcement |

The origin service for both routes is
`https://cilium-gateway-lan-gateway.gateway-system.svc.cluster.local:443`. The existing `.lab` DNS records
continue to resolve directly to `192.168.1.244`, preserving LAN access and rollback independently of
Cloudflare.

## Trust boundary

- The tunnel token is committed only as a SealedSecret and mounted as a read-only file.
- The pods do not receive Kubernetes API credentials and run as a non-root user with a read-only filesystem.
- Egress permits cluster DNS, Cilium's `ingress` identity, the Grafana backend on TCP `3000`, the Hubble UI
  backend on TCP `8081`, and Cloudflare on TCP or UDP `7844` with TCP `443` for management and fallback.
  Cilium Gateway hairpin traffic crosses the `ingress` identity before reaching a routed backend, so the
  policy allows those identities directly instead of relying on the selectorless Gateway Service.
- Prometheus is the only permitted inbound consumer of the connector metrics endpoint.
- Cloudflare route configuration remains remotely managed until the external boundary is imported into
  OpenTofu. The dashboard configuration is therefore an explicit temporary manual dependency.

## Verification

1. Confirm both pods are Ready and scheduled on different nodes.
2. Confirm `cloudflared_tunnel_ha_connections` is greater than zero for both pods.
3. Open `https://grafana.pragalva.me` outside the LAN and confirm Grafana requires its own login.
4. Open `https://hubble.pragalva.me` in a private window and confirm Cloudflare Access rejects an unauthorized
   request before Hubble is reached.
5. Delete one pod and confirm the endpoint remains available while the Deployment restores two replicas.
6. Scale the Deployment to zero only during an approved rollback test and confirm both public endpoints fail
   while the `.lab` endpoints remain reachable on the LAN. Restore two replicas immediately afterward and
   confirm Argo reports no drift.

## Rollback

Disable the two published application routes in Cloudflare, then revert this Argo child application. Removing
the connectors severs public access without changing the Gateway, the `.lab` DNS records, or LAN access. Rotate
the tunnel token if it may have been exposed.
