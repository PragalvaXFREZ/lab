# PostgreSQL drills

Two proofs for the shared cluster in `kubernetes/infra/storage/postgres/`: a primary loss that keeps every acknowledged commit, and a restore from R2 whose table checksums match the source. Nothing here is reconciled by Argo CD. Results belong in a dated report beside this README.

## Failover: no acknowledged commit is lost

1. Confirm the cluster is healthy and `SHOW synchronous_standby_names` on the primary names the standby. Record which pod is primary: `kubectl -n postgres get cluster postgres -o jsonpath='{.status.currentPrimary}'`.
2. Apply `failover-writer.yaml` and wait until `/work/acked` grows: `kubectl -n postgres exec failover-writer -- wc -l /work/acked`.
3. Kill the primary pod with no time for a clean shutdown: `kubectl -n postgres delete pod <primary> --grace-period=1`. Do not use `--force`: it removes the pod object while its container may still run on the same volume.
4. Wait for the writer to log `done`, and for the cluster to report a new primary and two ready instances.
5. Compare the acknowledged ids with the table on the new primary:

   ```bash
   kubectl -n postgres exec failover-writer -- cat /work/acked | LC_ALL=C sort > acked.txt
   kubectl -n postgres exec <new-primary> -c postgres -- \
     psql -X -A -t -d app -c 'SELECT id FROM failover_drill' | LC_ALL=C sort > present.txt
   LC_ALL=C comm -23 acked.txt present.txt
   ```

   The `comm` output must be empty: every acknowledged id is present. Ids that are present but not acknowledged are commits whose acknowledgement was lost with the connection, which is expected.
6. Delete the writer pod and drop the `failover_drill` table.

Repeat with the primary on the other node. Draining a node instead of deleting the pod exercises the switchover path, which must also lose nothing.

## Restore: checksums match

1. Record the source checksums of each database, for example `app`:

   ```bash
   kubectl -n postgres exec -i <primary> -c postgres -- \
     psql -X -A -t -v ON_ERROR_STOP=1 -d app < checksum.sql > before-app.txt
   ```

2. With no consumer writing, take a backup right after the checksum: `kubectl -n postgres create job --from=cronjob/postgres-backup postgres-backup-drill`, then confirm `upload: done` in its logs.
3. Apply `scratch-cluster.yaml` and wait for `scratch` to report a healthy state.
4. Load the backup credentials into the environment without printing them, with the OpenPGP private key in the local keyring, and run `./restore.sh results`. It downloads the newest object, checks its SHA-256 against the stored metadata, decrypts it locally, checks each dump against the manifest, restores into `scratch`, and writes `results/after-<file>.txt`.
5. Match each database through `results/manifest.tsv`, then `diff before-app.txt results/after-001.txt`. The output must be empty.
6. Delete the `postgres-restore-drill` namespace. The scratch volume is removed with it.

The restore uses `--no-owner --no-privileges`, so the checksum compares data, not ownership. Roles are declared in the `Cluster` spec, not in the backup.
