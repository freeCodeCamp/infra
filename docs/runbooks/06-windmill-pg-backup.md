# Windmill — PostgreSQL backup + restore

**Type:** Operator. Nightly automation + ad-hoc dump + DR restore. **Cluster:** `gxy-management`. Namespace: `windmill`. **Spec:** chart at `k3s/gxy-management/apps/windmill/manifests/base/`. Backup CronJob writes to Cloudflare R2 (S3-API) under `r2:<bucket>/windmill/gxy-management/`.

There are three artefact paths to know:

| Path                 | Producer                            | Destination                           | Use                                 |
| -------------------- | ----------------------------------- | ------------------------------------- | ----------------------------------- |
| Nightly automated    | `windmill-backup` CronJob (02:00)   | `r2:<bucket>/windmill/<galaxy>/`      | Disaster recovery — restore-from-R2 |
| Ad-hoc operator      | `just backup-windmill <cluster>`    | `.backups/` local + same R2 prefix    | Pre-upgrade safety net              |
| Restore verification | `just test-windmill-backup-restore` | mktemp (download + gunzip + sentinel) | Confidence check, no restore        |

All three share one sops envelope (`infra-secrets/k3s/gxy-management/windmill-backup.secrets.env.enc`) carrying PG + R2 credentials. The envelope schema is in [`../../k3s/gxy-management/apps/windmill/manifests/base/secrets/.backup-secrets.env.sample`](../../k3s/gxy-management/apps/windmill/manifests/base/secrets/.backup-secrets.env.sample). The container-side CronJob and the operator-side `just` recipes both consume the envelope via rclone's `RCLONE_CONFIG_R2_*` env-variable pattern — no on-disk `rclone.conf` is read (`RCLONE_CONFIG=/dev/null`).

## A — Verify the nightly backup is current

Operator-runnable read-only probe. Surfaces CronJob schedule, last-success timestamp, recent job pods, and local artefact list:

```sh
just inspect-windmill-backup gxy-management
```

Expected: `lastSuccessful` within the past 26 hours (matches the cron cadence + an hour of slack). Local `.backups/` is operator-generated only — empty on a fresh clone.

## B — Round-trip verify the artefact

Downloads the newest R2 backup to a tempdir, runs `gunzip -t` for integrity, asserts the postgres "cluster dump complete" sentinel. Does **not** restore.

```sh
just test-windmill-backup-restore gxy-management
```

Expected: `OK: <filename> (<bytes> bytes) gunzip-clean + sentinel present`.

If the sentinel check fails the backup is unusable; bump priority on `06.D` (forced re-dump) before reaching for it in a real DR.

## C — Take an ad-hoc operator backup

Pre-upgrade safety net. `just backup-windmill` runs `pg_dumpall` inside the PostgreSQL pod, copies the gzipped dump to `.backups/`, validates the sentinel locally, then mirrors the same artefact to the CronJob's R2 prefix so it shows up alongside the nightly objects.

```sh
just backup-windmill gxy-management
```

Recovery procedure does not differ between a nightly artefact and an ad-hoc artefact — they live in the same bucket prefix and share the schema.

## D — Force a fresh nightly run

When the next scheduled run is too far away (e.g., before a planned upgrade) and the verify-CronJob path showed staleness:

```sh
cd k3s/gxy-management
export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
kubectl -n windmill create job --from=cronjob/windmill-backup windmill-backup-manual-$(date +%Y%m%d-%H%M%S)
```

Wait for the job to complete, then re-run §B to verify the artefact.

## E — Restore from R2

**Destructive.** Restoring overwrites the live windmill PostgreSQL state. Take an ad-hoc dump (§C) first if the current state is salvageable.

Workspace authoritative shape: `~/DEV/fCC-U/windmill/workspaces/platform/f/**` — committed wmill source-of-truth. The PG dump is only needed for runtime-only data (job runs history, schedule pointer state, etc.). Schedules + scripts will reseed from a `wmill sync push` after restore.

```sh
cd k3s/gxy-management
export KUBECONFIG="$(pwd)/.kubeconfig.yaml"

# Decrypt R2 creds + DB password from the same envelope the CronJob uses.
set -a
source <(sops -d --input-type dotenv --output-type dotenv \
  ../../../../infra-secrets/k3s/gxy-management/windmill-backup.secrets.env.enc)
set +a

# Plug envelope vars into rclone's RCLONE_CONFIG_R2_* env pattern. No
# on-disk rclone.conf is touched (RCLONE_CONFIG=/dev/null).
export RCLONE_CONFIG=/dev/null
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACL=private
export RCLONE_CONFIG_R2_ENDPOINT="$R2_ENDPOINT"
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_KEY"

# Pick the artefact to restore. `rclone lsf` returns lexicographically;
# the timestamp prefix in the filename means tail = newest.
PREFIX="windmill/gxy-management"
TARGET=$(rclone lsf "r2:${R2_BUCKET}/${PREFIX}/" --include '*.sql.gz' | sort | tail -1)
echo "Target: $TARGET"

# Download + integrity check (mirrors `test-windmill-backup-restore`).
mkdir -p .backups/restore
rclone copyto "r2:${R2_BUCKET}/${PREFIX}/${TARGET}" ".backups/restore/${TARGET}"
gunzip -t ".backups/restore/${TARGET}"
gunzip -c ".backups/restore/${TARGET}" | tail -1 \
  | grep -q 'PostgreSQL database cluster dump complete'

# Quiesce windmill — scale workers + server to 0 so no writes interleave
# with the restore. Per `gxy-management.md §B.3.2` the live chart
# carries the quiesce procedure verbatim; this runbook just calls it.
kubectl -n windmill scale --replicas=0 deploy/windmill-server deploy/windmill-worker

# Copy the dump into the postgres pod and replay.
PG_POD=$(kubectl -n windmill get pod -l app=windmill-postgresql-demo-app \
  -o jsonpath='{.items[0].metadata.name}')
kubectl cp ".backups/restore/${TARGET}" "windmill/${PG_POD}:/tmp/${TARGET}"
kubectl -n windmill exec "$PG_POD" -- bash -c \
  "gunzip -c /tmp/${TARGET} | PGPASSWORD=\"\${POSTGRES_PASSWORD}\" psql -U postgres"

# Unquiesce.
kubectl -n windmill scale --replicas=1 deploy/windmill-server
kubectl -n windmill scale --replicas=2 deploy/windmill-worker

# Smoke: hit windmill UI through the Gateway.
just verify-app gxy-management windmill
```

## F — Retention

Nightly CronJob keeps 7 days of `.sql.gz` under the prefix; older objects are deleted at the end of each successful run (`backup-cronjob.yaml` GC loop). Ad-hoc dumps land in the same prefix and follow the same GC — operator dumps are not preserved beyond 7 days unless copied elsewhere by hand.

## References

- Chart: [`../../k3s/gxy-management/apps/windmill/manifests/base/backup-cronjob.yaml`](../../k3s/gxy-management/apps/windmill/manifests/base/backup-cronjob.yaml)
- Image build: [`../../docker/images/postgres-rclone/Dockerfile`](../../docker/images/postgres-rclone/Dockerfile)
- Envelope schema: [`../../k3s/gxy-management/apps/windmill/manifests/base/secrets/.backup-secrets.env.sample`](../../k3s/gxy-management/apps/windmill/manifests/base/secrets/.backup-secrets.env.sample)
- Secrets-layout contract: [`../architecture/rfc-secrets-layout.md`](../architecture/rfc-secrets-layout.md)
- Flight manual chapter: [`../flight-manuals/gxy-management.md`](../flight-manuals/gxy-management.md) §G
