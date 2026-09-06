# LAN gateway

The Cilium Gateway API terminates public ACME certificates for Grafana, Hubble, and Uptime Kuma on the LAN. MetalLB assigns `192.168.1.244` to the generated LoadBalancer Service. DNS-only `A` records for `grafana.lab.pragalva.me`, `hubble.lab.pragalva.me`, and `kuma.lab.pragalva.me` point to that address.

The Gateway uses the `metallb.universe.tf` annotation prefix required by the installed MetalLB `v0.14.5` controller.

The Gateway routes to the `kps-grafana`, `hubble-ui`, and `uptime-kuma` Services through explicit cross-namespace grants. The Grafana and Hubble LoadBalancer types and direct addresses stay unchanged as the compatibility and rollback path. Uptime Kuma is ClusterIP only, so the Gateway is its sole LAN entry; its own README covers the port-forward fallback.

## Verification

```bash
kubectl -n gateway-system get gateway,httproute,certificate
kubectl -n monitoring get referencegrant allow-grafana-route
kubectl -n kube-system get referencegrant allow-hubble-route
kubectl -n uptime get referencegrant allow-kuma-route
curl -I http://grafana.lab.pragalva.me
curl -I https://grafana.lab.pragalva.me
curl -I https://hubble.lab.pragalva.me
curl -I https://kuma.lab.pragalva.me
```

The HTTP request must redirect to HTTPS, every HTTPS request must validate without `--insecure`, and all route conditions must be `Accepted=True` and `ResolvedRefs=True`. The Uptime Kuma dashboard uses a WebSocket; the browser must show live heartbeat updates through the Gateway, not only the initial page.

## Rollback

Revert the Gateway manifests and `gatewayAPI.enabled` value through Git. Remove the DNS records after Argo reconciles the revert. Grafana remains reachable at `http://192.168.1.242` and Hubble remains reachable at `http://192.168.1.243` throughout the migration.
