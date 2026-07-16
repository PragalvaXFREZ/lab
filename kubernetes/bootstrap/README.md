# bootstrap

The bootstrap boundary. This directory holds the Argo CD installation and the single root Application applied by hand to start reconciliation.

The root Application remains the manual anchor. Once it is running, the `argocd` child Application adopts `argocd/` and keeps the controller installation aligned with Git without pruning its own resources.

## Apply

Start with a working `kubectl` context for the Talos cluster. Create the controller namespace, apply the pinned Argo CD installation, wait for its Application CRD, and then apply the root Application:

```sh
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k kubernetes/bootstrap/argocd
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
kubectl apply -f kubernetes/bootstrap/root.yaml
```

The root Application tracks `kubernetes/clusters/devata` on `main` with self-heal and pruning enabled.

## Verify

```sh
kubectl get application devata-root -n argocd
kubectl get applications -n argocd
```

The root and every child Application must report `Synced` and `Healthy`. Investigate any diff before changing automation or applying a resource by hand.
