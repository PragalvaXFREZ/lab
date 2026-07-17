# Velero restore proof

This disposable namespace bounds the file-system backup input to a 16 MiB Longhorn PVC. The pod volume is explicitly opted into Velero backup. The proof writes a sentinel after the pod is ready, records its SHA-256 checksum, backs up the namespace, deletes the source, and restores it under `velero-cap-proof-restored` with namespace mapping.

The restored sentinel checksum, `PodVolumeBackup` and `PodVolumeRestore` completion, and R2 byte counts belong in the dated result report. The namespace is disposable and is not reconciled by Argo CD.

## Run

Apply `manifest.yaml`, wait for the pod, and write an 8 MiB random payload plus a sentinel. Record a combined checksum before any backup begins.

Run the R2 capacity guard with `16777216` planned bytes, then apply `backup.yaml`. The Backup must reach `Completed`, and its `PodVolumeBackup` must also report `Completed`, before deleting the source namespace.

Apply `restore.yaml` after the source namespace has disappeared. Wait for the Restore and `PodVolumeRestore` to report `Completed`, wait for the pod in `velero-cap-proof-restored`, and compare the combined checksum with the source value.

Measure the complete R2 bucket again with the capacity guard using `0` planned bytes. Retain the proof backup only for its seven-day TTL, or delete it explicitly and confirm a full repository maintenance job before expecting object bytes to fall.

## Cleanup

Delete the restored namespace and both disposable Velero custom resources. Deleting a backup removes its Kopia snapshot reference, but object bytes are reclaimed later by repository maintenance.
