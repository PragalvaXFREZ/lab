# Velero

Velero writes Kubernetes resource backups and selected file-system volume backups to a private Cloudflare R2 bucket. The R2 credentials are committed only as a strict-scope SealedSecret.

The bucket has a 1 GB operating ceiling. No recurring `Schedule` resource is declared because R2 does not provide a per-bucket capacity limit. Backups are created on demand only after their bounded input and current bucket usage have been checked. File-system backup is opt-in per pod volume, which prevents an unbounded Prometheus TSDB from entering a backup accidentally. A Cloudflare budget notification may provide an additional warning, but it is not a storage quota and is not part of the enforcement model.

The node agent uses Kopia to read selected mounted volumes. Native volume snapshots are disabled because R2 is the durable target and Longhorn snapshots remain on the same cluster failure domain.

## Files

- `values.yaml` configures the R2 backup location, AWS-compatible plugin, Kopia node agent, and resource limits.
- `secrets/cloud-credentials.yaml` contains the encrypted R2 access and secret keys.
- `secrets/repository-credentials.yaml` contains the encrypted Kopia repository password required to restore file-system backups.
- `check-capacity.sh` measures R2 and rejects a planned backup that cannot retain a 100 MB safety reserve below the decimal 1 GB ceiling.

The chart is pinned to `11.4.0` with Velero `1.17.1` and AWS plugin `1.13.2`. Plugin `1.14.x` is not used because its empty object-tagging header is rejected by R2. Revisit the pin only after the upstream R2 compatibility regression is resolved.

## Verification

The backup storage location must report `Available`. A disposable PVC backup must complete through `PodVolumeBackup`, restore into a remapped namespace, and preserve its sentinel checksum. R2 usage is measured before and after the proof.

## Rollback

Removing the Argo CD Application removes the in-cluster Velero controllers and node agent. Backups in R2 remain independent of the cluster and can be attached to a replacement Velero installation with the same credentials and repository password.

## Capacity boundary

There is no automatic backup schedule. Before a backup, load the S3 access key and secret key into the standard `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables without printing them, then pass the maximum selected volume data to the guard:

```bash
./kubernetes/infra/storage/velero/check-capacity.sh 16777216
```

The example is the 16 MiB disposable restore proof. The guard passes only when current object bytes plus planned data plus a 100,000,000-byte Kopia metadata reserve remain below 1,000,000,000 bytes. A provider-side bucket quota is not available, so an unattended schedule or an input that cannot be bounded is outside this component's safety contract.
