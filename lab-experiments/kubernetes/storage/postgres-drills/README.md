# PostgreSQL drills

Two proofs for the shared cluster in `kubernetes/infra/storage/postgres/`: a primary loss that keeps every acknowledged commit, and a restore from R2 whose table checksums match the source. Nothing here is reconciled by Argo CD. Results belong in a dated report beside this README; the first one is [`2026-11-27-report.md`](./2026-11-27-report.md).

## Failover: no acknowledged commit is lost

1. Confirm the cluster is healthy and `SHOW synchronous_standby_names` on the primary names the standby. Record which pod is primary: `kubectl -n postgres get cluster postgres -o jsonpath='{.status.currentPrimary}'`.
2. Apply `failover-writer.yaml`. It drops and recreates `failover_drill`, then inserts ids 1 to 3000, one autocommit transaction each, under a 10-second client timeout. Wait until the ledger grows: `kubectl -n postgres exec failover-writer -- wc -l /work/acked`.
3. Note the UTC time and kill the primary pod with no time for a clean shutdown: `date -u; kubectl -n postgres delete pod <primary> --grace-period=1`. Do not use `--force`: it removes the pod object while its container may still run on the same volume.
4. Wait for the summary line, and for the cluster to report a new primary and two ready instances:

   ```bash
   kubectl -n postgres logs failover-writer | grep summary
   kubectl -n postgres get cluster postgres -o jsonpath='{.status.currentPrimary}{"\n"}'
   ```

   The writer then sleeps for a day, so the ledger stays readable until the pod is deleted.
5. Compare the acknowledged ids with the table on the new primary:

   ```bash
   kubectl -n postgres logs failover-writer | grep ' insert .* failed'
   kubectl -n postgres exec failover-writer -- cat /work/acked | LC_ALL=C sort > acked.txt
   kubectl -n postgres exec <new-primary> -c postgres -- \
     psql -X -A -t -d app -c 'SELECT id FROM failover_drill' | LC_ALL=C sort > present.txt
   wc -l < acked.txt
   LC_ALL=C comm -23 acked.txt present.txt | wc -l
   ```

   The drill passes only if all three hold:

   - the acknowledged count (`wc -l < acked.txt`, also `acknowledged=` in the summary) is greater than zero;
   - at least one insert failed around the kill time: `failed=` in the summary is at least 1, and the timestamps of the failed inserts bracket the time noted in step 3;
   - zero acknowledged ids are missing from the table: the `comm ... | wc -l` line prints `0`.

   Ids that are present but not acknowledged are commits whose acknowledgement was lost with the connection, which is expected.
6. Delete the writer pod and drop the `failover_drill` table.

Repeat with the primary on the other node. Draining a node instead of deleting the pod exercises the switchover path, which must also lose nothing.

## Restore: checksums match

1. Record the source checksums of each database, for example `app`:

   ```bash
   kubectl -n postgres exec -i <primary> -c postgres -- \
     psql -X -A -t -v ON_ERROR_STOP=1 -d app < checksum.sql > before-app.txt
   ```

2. With no consumer writing, and away from the scheduled 03:17 UTC run so the retention bound holds, take a backup right after the checksum: `kubectl -n postgres create job --from=cronjob/postgres-backup postgres-backup-drill`, then confirm `upload: done` in its logs.
3. Apply `scratch-cluster.yaml` and wait for `scratch` to report a healthy state.
4. Load the backup credentials into the environment without printing them, with the OpenPGP private key in the local keyring, and run `./restore.sh results`. It downloads the newest object, checks its SHA-256 against the stored metadata, decrypts it locally, checks each dump against the manifest, restores into `scratch`, and writes `results/after-<file>.txt`.
5. Match each database through `results/manifest.tsv`, then `diff before-app.txt results/after-001.dump.txt`. The output must be empty, including the last `overall|` line.
6. Delete the `postgres-restore-drill` namespace. The scratch volume is removed with it.

The restore uses `--no-owner --no-privileges`, so the checksum compares data, not ownership. Roles are declared in the `Cluster` spec, not in the backup.
