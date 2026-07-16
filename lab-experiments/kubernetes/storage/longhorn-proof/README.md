# Longhorn durability proof

This disposable workload verifies the two-replica Longhorn StorageClass without placing test resources inside the GitOps reconciliation boundary.

## Create the proof volume

```bash
kubectl apply -f manifest.yaml
kubectl -n longhorn-proof wait --for=condition=Available deployment/longhorn-proof --timeout=5m
kubectl -n longhorn-proof exec deployment/longhorn-proof -- sh -c 'date -u +%FT%TZ > /data/sentinel && sha256sum /data/sentinel'
```

Confirm that the Longhorn volume is healthy and has one replica on each storage worker before disrupting a node.

## Reboot test

Cordon and drain the worker that hosts the proof pod, reboot it with `talosctl`, wait for Talos and Kubernetes readiness, uncordon it, and verify the sentinel checksum from the restarted pod.

## Node-failure test

Stop the Talos `cri` service on the hosting worker to simulate loss of its workload runtime while keeping Talos API access for recovery. Move the proof Deployment to the other worker, force-delete the unreachable old pod only after the node is NotReady, and verify the sentinel from the replacement pod. Start `cri`, wait for the node and both Longhorn replicas to recover, then verify the checksum again.

This test exercises a worker-runtime failure. It is not evidence of a physical power-loss or network-partition test.

## Cleanup

```bash
kubectl delete -f manifest.yaml
```

Wait for the namespace, PVC, PV, Longhorn volume, engine, and replica objects to disappear. The manifest is disposable and must not be moved under `kubernetes/`.
