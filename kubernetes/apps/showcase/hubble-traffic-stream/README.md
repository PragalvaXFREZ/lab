# Hubble traffic stream

This workload sends two aggregate Hubble rates from Devata to a public relay every five seconds. It exists only to make the portfolio traffic chart near-live. The hourly `snapshot.json` traffic block remains the durable fallback.

The producer queries the same Prometheus series as the Devata overview dashboard, creates a new three-field document, and makes one authenticated outbound HTTPS request. It has no Service, listening port, Kubernetes API token, or inbound policy allowance.

Six consecutive collection or delivery failures terminate the process so Kubernetes and Argo CD expose a broken stream instead of reporting a healthy Deployment that only logs errors.

```json
{
  "timestamp": "2026-07-31T10:12:05Z",
  "flowsPerSecond": 146.4,
  "dropsPerSecond": 0.048
}
```

The relay at `telemetry.pragalva.me` runs as a Cloudflare Worker backed by one SQLite Durable Object. It rejects unknown fields, stale or future timestamps, replays, writes faster than one every three seconds, and invalid bearer credentials. Accepted rows expire six hours after their sample timestamp. Retention queries use the timestamp primary-key index so the five-second producer does not scan the full history on every write. Browsers read `/v1/history` and receive new samples through a hibernating WebSocket at `/v1/stream`.

## Trust boundary

- Prometheus stays reachable only inside the cluster.
- The producer reads one fixed aggregate query and transforms the response into the closed payload above.
- A Cilium policy permits only DNS for the relay name, Prometheus on TCP 9090, and `telemetry.pragalva.me` on TCP 443.
- The producer credential is a SealedSecret in Git and a masked GitHub environment secret used to configure the Worker.
- The relay accepts writes only with that credential. Browser endpoints are read-only and allow the portfolio origin.
- Individual flows, labels, identities, addresses, ports, and node names never enter the outbound document.

## Repository contents

| Path | Responsibility |
| --- | --- |
| `deployment.yaml` | Single non-root producer; `Recreate` prevents overlapping writers during rollout |
| `network-policy.yaml` | Deny inbound and allow only the required Prometheus, DNS, and relay egress |
| `sealedsecret-producer-token.yaml` | Encrypted producer credential |
| `image/` | Dependency-free Go producer and tests |
| `relay/` | Worker, Durable Object, closed-contract tests, and deployment configuration |

Subdirectories are source code, not Kubernetes manifests. Argo CD's directory source applies only the YAML files at this directory's top level.

## First deployment

The child Application is intentionally created without automated sync. Before merging, configure the `hubble-traffic-relay` GitHub environment with `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, and `HUBBLE_RELAY_PRODUCER_TOKEN`. The API token needs Workers Scripts edit and Workers Routes edit access for the `pragalva.me` zone.

After merge, the workflow deploys the relay and producer image. Confirm the new GHCR package is public, then stage the workload:

```sh
curl -fsS https://telemetry.pragalva.me/health | jq .
argocd app sync hubble-traffic-stream
kubectl rollout status deployment/hubble-traffic-streamer -n showcase
kubectl logs deployment/hubble-traffic-streamer -n showcase -f
```

Verify the public contract and inspect it for prohibited fields:

```sh
curl -fsS https://telemetry.pragalva.me/v1/history | tee /tmp/hubble-history.json | jq .
grep -Ei 'pod|service|namespace|node|ip|port|label|192\.168|10\.|172\.' /tmp/hubble-history.json || echo clean
```

Send a request with a bad credential and expect `401`:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'Authorization: Bearer rejected' \
  -H 'Content-Type: application/json' \
  --data '{"timestamp":"2026-07-31T10:12:05Z","flowsPerSecond":1,"dropsPerSecond":0}' \
  https://telemetry.pragalva.me/v1/samples
```

After the live payload, rejection, retention, and egress policy are proven, add automated prune and self-heal to the child Application. Update the portfolio only after that gate.

## Credential rotation

Generate one token without writing it to disk. Seal it to the fixed Secret name and namespace using `kubernetes/infra/controllers/sealed-secrets/pub-cert.pem`, and set the same value as the `HUBBLE_RELAY_PRODUCER_TOKEN` environment secret. Deploy the Worker secret first, then merge the SealedSecret update. The producer retries safely during the brief rejection window.

## Rollback

Remove the child Application from `kubernetes/clusters/devata/` and let Argo prune the producer. Delete the Worker after the pod is gone. The portfolio continues to use the hourly traffic block in `snapshot.json`; no inbound cluster route is involved.
