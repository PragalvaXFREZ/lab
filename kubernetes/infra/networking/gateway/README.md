# LAN gateway

The Cilium Gateway API terminates public ACME certificates for Grafana and Hubble on the LAN. MetalLB assigns `192.168.1.244` to the generated LoadBalancer Service. DNS-only `A` records for `grafana.lab.pragalva.me` and `hubble.lab.pragalva.me` point to that address.

The Gateway routes to the existing `kps-grafana` and `hubble-ui` Services through explicit cross-namespace grants. Their LoadBalancer types and direct addresses stay unchanged as the compatibility and rollback path.

## Verification

```bash
kubectl -n gateway-system get gateway,httproute,certificate
kubectl -n monitoring get referencegrant allow-grafana-route
kubectl -n kube-system get referencegrant allow-hubble-route
curl -I http://grafana.lab.pragalva.me
curl -I https://grafana.lab.pragalva.me
curl -I https://hubble.lab.pragalva.me
```

The HTTP request must redirect to HTTPS, both HTTPS requests must validate without `--insecure`, and all route conditions must be `Accepted=True` and `ResolvedRefs=True`.

## Rollback

Revert the Gateway manifests and `gatewayAPI.enabled` value through Git. Remove the two DNS records after Argo reconciles the revert. Grafana remains reachable at `http://192.168.1.242` and Hubble remains reachable at `http://192.168.1.243` throughout the migration.
