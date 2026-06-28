# bootstrap

The one manual step. This holds the GitOps controller install and the single root application that is applied by hand once, after which the controller takes over and reconciles everything else from git.

Nothing here is reconciled by definition, because it is what starts the reconciler. Everything after bootstrap is declarative and self managing.
