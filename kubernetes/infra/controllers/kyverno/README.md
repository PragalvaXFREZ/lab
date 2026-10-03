# Kyverno

Kyverno is a policy engine. On devata it runs in audit mode: it checks objects against policies and writes the results to PolicyReports. It does not reject a request.

The chart is installed as an Argo CD child Application, including its CRDs. Three controllers run in the `kyverno` namespace: admission, background, and reports. The cleanup controller is off because no cleanup policy is in use.

## Safety boundaries

- **Webhooks fail open.** `forceFailurePolicyIgnore` sets `failurePolicy: Ignore` on every Kyverno webhook. If Kyverno is down, the API server continues to accept requests.
- **Three namespaces are outside the webhooks:** `kube-system`, `argocd`, and `kyverno`. A request for an object in these namespaces is never sent to Kyverno.
- **Policies are audit only.** Use only `policies.kyverno.io/v1` kinds with `validationActions: [Audit]`. Do not add a policy that denies, mutates, or generates.

Kyverno creates its webhook configurations at runtime. They are not in the chart and Argo CD does not manage them.

## Known limitations

- Because `argocd` is outside the webhooks, Kyverno does not see Argo CD objects at admission. The background scan still checks them and writes reports. A policy that matches only `UPDATE` with background scan off gives no result for objects in `argocd`.
- Kyverno cannot grant itself access to custom resources. The values file gives the three controllers read access to Applications, AppProjects, and ApplicationSets. A policy that matches a different custom kind needs the same grant, or it does not become ready.
- The background controller reads the list of known kinds when it starts. If a CRD is installed later, restart the background controller before a GeneratingPolicy uses that kind.

## Verification

```bash
kubectl -n kyverno get pods
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations \
  -l webhook.kyverno.io/managed-by=kyverno \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.webhooks[*].failurePolicy}{"\n"}{end}'
kubectl get validatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno \
  -o jsonpath='{.items[*].webhooks[*].namespaceSelector}'
kubectl auth can-i list applications.argoproj.io \
  --as=system:serviceaccount:kyverno:kyverno-reports-controller
kubectl get policyreports,clusterpolicyreports -A
```

Every `failurePolicy` must be `Ignore`, and the namespace selector must name all three namespaces.

## Rollback

Remove policies first, then revert the Kyverno child Application. That Application has the Argo CD resources finalizer, so the removal cascades: Argo CD deletes the controllers and the CRDs, and the CRD removal deletes all policies and reports. The other child Applications in this repository do not have this finalizer; their workloads stay when the Application is removed.

Then check that nothing stays behind:

```bash
kubectl get ns kyverno
kubectl get crd | grep kyverno
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno
```

If a webhook configuration stays, delete it. While it exists it fails open.
