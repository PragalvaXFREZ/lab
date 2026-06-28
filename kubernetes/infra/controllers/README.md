# controllers

Cluster wide operators that other components and apps rely on: cert-manager for TLS, sealed-secrets for encrypted secrets, and similar.

This is the home for the secrets controller. Encrypted secrets themselves live beside the workloads that need them, not here; this directory is for the controller that decrypts them.

Lands under its own follow up issues (Sealed Secrets, then cert-manager).
