# snapshot-publisher

The cluster describes itself to the public. An hourly CronJob reads devata's state through a read-only ServiceAccount, renders a public-safe JSON document, validates it against a schema, and pushes it to [PragalvaXFREZ/devata-snapshot](https://github.com/PragalvaXFREZ/devata-snapshot). The portfolio's [/homelab page](https://pragalva.me/homelab) fetches that one raw file and renders it, honoring the document's own freshness contract.

Push, not pull: CGNAT means nothing outside can reach in, and home infrastructure can lose power or uplink without warning. A pushed static file keeps serving its last state either way, and the consumer marks it stale past `freshness.maxAgeHours` instead of pretending an unreachable cluster is live. A second property falls out for free: every run commits even when only the timestamp changed, so the snapshot repo's commit history is the cluster's off-cluster uptime ledger, the only uptime memory devata has that survives a reboot.

Beside the snapshot, every run maintains `heartbeat.json`: a rolling window of the last 336 run timestamps (14 days at the hourly cadence). It exists because the portfolio page needs to read the ledger, and walking the commit log through the GitHub REST API rate-limits anonymous browsers at 60 requests an hour per address; a raw file rides the CDN with no such ceiling. The file carries nothing read from the cluster, only the job's own clock, so it sits outside the allowlist and the schema gate by construction. The commit history stays the audit trail: every beat in the file has a matching commit, and anyone skeptical can diff the two.

## The safety model

1. **Read-only on the cluster side.** The ClusterRole in `rbac.yaml` is the complete list of what the publisher may see: get and list on nodes, namespaces, services, persistentvolumeclaims, pods, the apps workload kinds, and Argo Applications. No secrets, no writes, no watch.
2. **Allowlist, never denylist.** `publish.sh` builds the document with `jq -n`, selecting safe fields into a new object. Nothing is copied and redacted, so a field Kubernetes adds next year cannot leak by default. Internal IPs and real node names are never read out of the source objects; node identity is a positional alias like `cp-1`.
3. **The schema is the gate.** The job validates its own output against `snapshot.schema.v1.json` (the copy in `configmap-schema.yaml` is the canonical one, because it is the one the running job enforces) and refuses to push on failure. `additionalProperties: false` everywhere means an accidental extra field fails the run instead of shipping.
4. **One credential, scoped to one repo.** The push uses a GitHub deploy key that can write to `devata-snapshot` and nothing else, committed as a SealedSecret. A deploy key was chosen over a fine-grained token because the blast radius is identical (contents of one public data repo) and a key does not expire, so the publisher cannot silently die into a permanently stale page. GitHub's SSH host keys are pinned in the scripts ConfigMap; there is no trust-on-first-use.
5. **Graceful staleness.** An unreachable cluster misses runs and the last good snapshot stays in place. Failing the run is always better than pushing garbage.

## Files

| File | What it is |
| --- | --- |
| `serviceaccount.yaml`, `rbac.yaml` | The read-only identity and its exact permissions |
| `configmap-scripts.yaml` | `publish.sh` (single source of truth, no loose copy exists) and the pinned `known_hosts` |
| `configmap-schema.yaml` | The v1 schema the gate enforces, embedded so Argo never tries to apply a loose `.json` |
| `sealedsecret-snapshot-push-credential.yaml` | The deploy key, encrypted to the cluster's sealed-secrets key |
| `cronjob.yaml` | Hourly, every non-default line commented |
| `image/` | Dockerfile for the toolbox image; built by the `publisher image` workflow on merge |

## Operating it

Fire a run without waiting for the clock:

```sh
kubectl create job snap-manual --from=cronjob/snapshot-publisher -n showcase
kubectl logs -n showcase job/snap-manual -f
```

Verify what the world sees:

```sh
curl -s https://raw.githubusercontent.com/PragalvaXFREZ/devata-snapshot/main/snapshot.json | jq .
curl -s https://raw.githubusercontent.com/PragalvaXFREZ/devata-snapshot/main/snapshot.json | grep -E '192\.168|talos-' || echo clean
```

Prove the gate rejects, rather than believing it does:

```sh
kubectl get cm snapshot-schema-v1 -n showcase -o jsonpath='{.data.snapshot\.schema\.v1\.json}' > /tmp/schema.json
curl -s https://raw.githubusercontent.com/PragalvaXFREZ/devata-snapshot/main/snapshot.json \
  | jq '. + {internalIp: "192.168.1.8"}' > /tmp/broken.json
check-jsonschema --schemafile /tmp/schema.json /tmp/broken.json
```

The CronJob was born with `suspend: true` and the Application with automation off. Both flipped in a follow-up PR after the first manual run was verified end to end against the safety model: render checked against the live cluster, gate proven to reject a stray field, leak grep clean, push confirmed at the raw URL. One known hardening item remains: the pod runs as root (Alpine's default) and the showcase namespace warns against the restricted PodSecurity profile; moving to runAsNonRoot is a future image change.
