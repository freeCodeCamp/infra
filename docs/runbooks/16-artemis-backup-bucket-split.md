# 16 — Artemis backup bucket split (one-off migration)

**Audience:** operator. **Trigger:** run once, before the next artemis chart release.

Both artemis backup CronJobs wrote their dumps into `universe-static-apps-01`, the bucket artemis serves deploys from. ADR-019:86 forbids one shared bucket across stateful pillars. The chart now reads `backup.bucket` and `pgBackup.bucket` and both point at `management-cnpg-backups`, which does not exist yet.

**Do not release before step 5.** `RCLONE_CONFIG_R2_NO_CHECK_BUCKET: "true"` stops rclone from creating the bucket. A release against a missing bucket fails every nightly run with `NoSuchBucket`, and `backoffLimit: 2` marks the Job Failed.

Related: [05](05-r2-keys-rotation.md) mints the tokens. [02](02-deploy-artemis-service.md) §5 seals them. [03](03-artemis-postdeploy-check.md) §4b verifies the monitors. [08](08-artemis-pg-restore-drill.md) §H is the drill that closes this work.

## Prerequisites

| #   | Condition                                                               | Check                                           |
| --- | ----------------------------------------------------------------------- | ----------------------------------------------- |
| 1   | `wrangler` is authenticated against the freeCodeCamp Cloudflare account | `wrangler whoami`                               |
| 2   | `rclone` is on PATH                                                     | `rclone version`                                |
| 3   | The serve token `R2_*` and the dotenv SOT decrypt                       | [04](04-secrets-decrypt.md)                     |
| 4   | GitHub Actions `workflow_dispatch` is available to you                  | `.github/workflows/docker--postgres-rclone.yml` |

## 1. Create the bucket

The location hint is permanent. Cloudflare: "Location Hints are only honored the first time a bucket with a given name is created. If you delete and recreate a bucket with the same name, the original bucket's location will be used." — https://developers.cloudflare.com/r2/reference/data-location/

The nodes run in DigitalOcean `fra1`, so the hint is `weur` (Western Europe).

```sh
wrangler r2 bucket create management-cnpg-backups --location weur
wrangler r2 bucket list | grep management-cnpg-backups
```

The name has no `-01` suffix. ADR-019:173 names `management-cnpg-backups`.

## 2. Mint the backup-only token

Follow [05](05-r2-keys-rotation.md) §1b. The token is scoped to `management-cnpg-backups` only. Do not widen the serve token; ADR-016:23 names the blast radius.

## 3. Seal the token

Store the three values as `R2_BACKUP_ENDPOINT`, `R2_BACKUP_ACCESS_KEY_ID` and `R2_BACKUP_SECRET_ACCESS_KEY` in the dotenv SOT, then in the YAML overlay. Do not write them over `R2_ENDPOINT`, `R2_ACCESS_KEY_ID` or `R2_SECRET_ACCESS_KEY`; those three are the serve token. [02](02-deploy-artemis-service.md) §5 carries the mirror glob.

The chart refuses to render a backup CronJob while any `R2_BACKUP_*` value is absent.

## 4. Rebuild the `postgres-rclone` image

The backup script posts a Sentry cron check-in with `curl`. Every image built before 2026-09-11 purged `curl` at build, so on those images the check-in is a silent no-op and a failed backup still pages nobody.

1. Run the `workflow_dispatch` build of `.github/workflows/docker--postgres-rclone.yml`.
1. Read the new digest from the registry, not from the build log.
1. Repin `pgBackup.image` and `backup.image` in `k3s/gxy-management/apps/artemis/charts/artemis/values.yaml`. Both lines carry the same digest.
1. Commit the repin.

## 5. Move the artefacts

Move, do not copy. A copy leaves `pg_dumpall` output with role definitions in the serve bucket forever, because the 7-day prune now runs against the new bucket only.

The two tokens reach different buckets, so the move needs two rclone remotes. The serve token reads `old:`. The backup token writes `new:`.

```sh
export RCLONE_CONFIG=/dev/null
for R in OLD NEW; do
  eval "export RCLONE_CONFIG_${R}_TYPE=s3 RCLONE_CONFIG_${R}_PROVIDER=Cloudflare RCLONE_CONFIG_${R}_ACL=private RCLONE_CONFIG_${R}_NO_CHECK_BUCKET=true"
done
export RCLONE_CONFIG_OLD_ENDPOINT="$R2_ENDPOINT"
export RCLONE_CONFIG_OLD_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_OLD_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_NEW_ENDPOINT="$R2_BACKUP_ENDPOINT"
export RCLONE_CONFIG_NEW_ACCESS_KEY_ID="$R2_BACKUP_ACCESS_KEY_ID"
export RCLONE_CONFIG_NEW_SECRET_ACCESS_KEY="$R2_BACKUP_SECRET_ACCESS_KEY"

rclone ls old:universe-static-apps-01/artemis/gxy-management
rclone move --progress \
  old:universe-static-apps-01/artemis/gxy-management \
  new:management-cnpg-backups/artemis/gxy-management
rclone ls new:management-cnpg-backups/artemis/gxy-management
rclone ls old:universe-static-apps-01/artemis/gxy-management   # must print nothing
```

One move covers `artemis/gxy-management/pg/`; it is a subtree of the source path.

**Hazard: the first nightly run can delete everything you just moved.** `rclone` keeps the original mtime and the prune step reads it with `--min-age`, so any artefact older than `retention` (`7d`) is deleted on the first successful run. That is the intended retention, but it is not obvious after a migration. Keep one dump outside R2 until step 8 passes.

Then run `unset` on all twelve variables above.

## 6. Release

Release the artemis chart on `gxy-management` with the recipe in [02](02-deploy-artemis-service.md) §Deploy.

## 7. Verify

```sh
export KUBECONFIG=k3s/gxy-management/.kubeconfig.yaml
kubectl -n artemis get cronjob artemis-backup artemis-pg-backup \
  -o custom-columns=NAME:.metadata.name,LAST:.status.lastSuccessfulTime
kubectl -n artemis get job -l app.kubernetes.io/component=pg-backup
```

Both `lastSuccessfulTime` values must advance past the release. A CronJob that has never run can be triggered once:

```sh
kubectl -n artemis create job --from=cronjob/artemis-pg-backup pg-backup-manual-$(date +%s)
```

Then confirm the two Sentry cron monitors exist per [03](03-artemis-postdeploy-check.md) §4b. A green Job with no monitor means the image digest from step 4 did not reach the cluster.

## 8. Re-run the drill

Run [08](08-artemis-pg-restore-drill.md) §H again and write the new date into the §H status line. Runbook 08 requires a re-rehearsal after any backup CronJob change, and this migration changed the bucket, the token and the image in one release.

§H does not wait for this migration. Run it first against the live `universe-static-apps-01` artefacts with the serve token — that is what §B and §H3 default to — and run it a second time here.

## Rollback

Steps 1 to 4 are additive and need no rollback. After step 5 the old bucket no longer holds the artefacts, so the rollback is the reverse `rclone move`. After step 6, revert the chart commits and release again; the backup destination returns to the serve bucket and ADR-019:86 is violated again, so treat this as a last resort.
