# cert-manager

cert-manager issues public certificates for LAN services by completing ACME DNS-01 challenges through Cloudflare. The controller is installed once as an Argo CD child Application, including its CRDs.

The scoped Cloudflare token is stored only as the `cloudflare-api-token` SealedSecret in the `cert-manager` namespace. The token requires `Zone:DNS:Edit` and `Zone:Zone:Read` for `pragalva.me`.

Prometheus scrapes the controller through its ServiceMonitor. Alerts cover certificates that remain unready, renewal timestamps overdue by more than one hour, and certificates within 14 days of expiration.

## Verification

```bash
kubectl -n cert-manager get pods
kubectl get clusterissuer letsencrypt-production
kubectl -n gateway-system get certificate lan-services-tls
kubectl -n cert-manager logs deploy/cert-manager --since=10m
kubectl -n monitoring get prometheusrule cert-manager-certificate-health
```

## Rollback

Disable new certificate consumers first. Revert the cert-manager child Application only after no Gateway references its Secrets. The SealedSecret remains recoverable from Git, and the Sealed Secrets controller key remains the off-cluster recovery boundary.
