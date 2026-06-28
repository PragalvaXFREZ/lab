# storage

Persistent storage for the cluster. Storage classes to begin with, and durable replicated volumes with backup later: Longhorn for the volumes and Velero for the backups, with their Talos system extensions declared in `talos/schematics/`.

Parked until a volume is actually worth protecting, then lands under its own follow up issue.
