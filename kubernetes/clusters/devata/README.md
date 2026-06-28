# devata

The entry point the GitOps controller reconciles for the devata cluster: the app of apps and the ApplicationSets that wire up which components from `infra/` and which workloads from `apps/` run here.

This is where a change to what devata runs begins. Adding a platform component or a workload means referencing it from here, not applying it by hand.
