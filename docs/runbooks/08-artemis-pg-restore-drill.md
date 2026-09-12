# Artemis — Postgres backup restore drill

**Type:** Operator. Disaster-recovery rehearsal (read-mostly; writes only to a throwaway scratch pod). **Cluster:** `gxy-management`. Namespace: `artemis`. **Spec:** chart at `k3s/gxy-management/apps/artemis/`. Stateful floor: ADR-019 §Stateful-pillar backup pattern + ADR-020 (durable-execution model).

**Last rehearsed:** 2026-08-25 — PASSED. It goes **stale when the bucket split is released**, not before: `94b7b97a` only commits the change, and the rule below requires a re-rehearsal once it reaches the cluster. Triggered by the `postgres-rclone` client-version fix (Helm rev 62, image `@sha256:fbedc38a…`, `pg_dumpall 16.15` matching the live `postgres:16.14-alpine`). Drilled artefact `artemis-20260825-134826.sql.gz`, written by the fixed image. §C `ERRORCOUNT=2` — the two expected `--clean` superuser errors, zero `transaction_timeout`. §D both tenants restored, 6/6 artemis tables, `sites=69` matching the live registry exactly.

**The pair is not rehearsed.** Both runs below drilled the `artemis-postgresql` StatefulSet. `postgresCluster.cutover` is `true` since 2026-09-11, so the live `artemis` database is on the CloudNativePG pair and no drill has read its artefact. §H is the procedure. Until §H records a date, the pair has a backup that nobody has restored.

Prior: 2026-06-05 — R8 drill PASSED (dossier `2026-06-02-artemis-durable-exec-cutover` §S 2026-06-05 11:25; both tenants restored, 6/6 artemis tables present, `sites` count matched the live registry, §F RPO/RTO floor demonstrated).

> The 2026-06-05 rehearsal predated the Windmill retirement (2026-07-07), at which point the artemis backup CronJob inherited an image built for a PG 18 server. The skew went undetected for seven weeks because §C ran `ON_ERROR_STOP=0` and the only gate was §D's row counts — which pass regardless, since the data still lands. The §C error gate exists because of that gap.

The artemis durable-exec substrate is a single-node bundled Postgres StatefulSet (`artemis-postgresql`) shared by two tenants — the `artemis` database (deploy/GC bookkeeping) and the `hatchet` database (engine state). Its availability floor is **not replication** — it is the nightly logical backup to R2 plus this rehearsed restore (chart `values.yaml` `postgres:` block; ADR-020 §3). This runbook restores the newest R2 dump into a throwaway scratch Postgres, sanity-checks row counts, and records the RPO/RTO the artefact actually delivers.

It is a **drill**: sections A to F touch neither the live `artemis-postgresql` StatefulSet nor the live databases. The scratch pod is a standalone `postgres:16-alpine` with no tenant labels, so neither the live PG nor the postgres NetworkPolicy is involved. A destructive production restore is section **G**, and it is the reason this drill exists.

`08.A` confirms a backup exists; `08.B` pulls + integrity-checks the artefact; `08.C` restores into a scratch PG; `08.D` is the row-count sanity gate; `08.E` tears the scratch pod down; `08.F` is the RPO/RTO statement; `08.G` is the destructive production restore; `08.H` drills the CloudNativePG pair.

**Sections A to F drill the `artemis-postgresql` StatefulSet only.** They read the `pg_dumpall` artefact under `artemis/gxy-management/`, which holds the `hatchet` database and, before the cutover, the `artemis` database. `postgresCluster.cutover` is `true` since 2026-09-11, so the live `artemis` database is on the CloudNativePG pair and its artefact is a different file in a different prefix. Drill the pair with `08.H`. ADR-019:177 records that R8 has not passed against the pair.

## Prerequisites

| Requirement                                   | Verify                                                                  |
| --------------------------------------------- | ----------------------------------------------------------------------- |
| infra repo checkout                           | `ls $HOME/DEV/fCC/infra/justfile`                                       |
| infra-secrets at canonical relative path      | `ls ../infra-secrets/k3s/gxy-management/artemis.values.yaml.enc`        |
| Org age key present                           | see `04-secrets-decrypt.md` §Preconditions                              |
| `rclone`, `sops`, `kubectl`, `gunzip` on PATH | `rclone version && sops --version`                                      |
| Durable-exec profile live                     | `kubectl -n artemis get sts artemis-postgresql` returns the StatefulSet |
| Nightly backup CronJob present                | `kubectl -n artemis get cronjob artemis-backup`                         |

The backup artefacts live under the R2 prefix `artemis/gxy-management/`, named `artemis-<YYYYMMDD-HHMMSS>.sql.gz`. These literals come straight from the chart's `backup-cronjob.yaml` (`R2_PREFIX="artemis/${GALAXY}"`, `FILENAME="artemis-${TIMESTAMP}.sql.gz"`) and `backup.galaxy` / `backup.bucket` in the values files.

> **Which bucket, right now.** The live CronJobs still write to **`universe-static-apps-01`** with the serve token. Every block below uses that. This drill needs nothing else and runs today.
>
> **After the migration only.** The chart is committed to write to `management-cnpg-backups` with a backup-only token, because `universe-static-apps-01` is the bucket artemis serves deploys from and ADR-019:86 forbids one shared bucket — "never one shared bucket". That change is unreleased. [16-artemis-backup-bucket-split.md](16-artemis-backup-bucket-split.md) creates the bucket, mints the token and moves the artefacts. Once it has run, swap two things in the §B block: decrypt `R2_BACKUP_ENDPOINT`, `R2_BACKUP_ACCESS_KEY_ID` and `R2_BACKUP_SECRET_ACCESS_KEY` instead of the three serve keys, and set `BUCKET=management-cnpg-backups`. The backup token reaches only the new bucket and the serve token only the old one, so a half-swap fails with `AccessDenied` (ADR-016:23).

## A — Confirm a backup exists and is current

```sh
cd $HOME/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG="$(pwd)/.kubeconfig.yaml"

# CronJob health: schedule + last successful run.
kubectl -n artemis get cronjob artemis-backup \
  -o jsonpath='schedule={.spec.schedule}{"\n"}lastSuccessful={.status.lastSuccessfulTime}{"\n"}'
```

Expect `schedule=0 2 * * *` and `lastSuccessful` within the past ~26 hours (nightly cadence + slack). If `lastSuccessful` is empty or stale, force a run before drilling:

```sh
kubectl -n artemis create job --from=cronjob/artemis-backup \
  artemis-backup-manual-$(date +%Y%m%d-%H%M%S)
# wait for the Job to Complete, then re-check lastSuccessful.
```

## B — Pull + integrity-check the newest artefact

Decrypt the R2 keys from the YAML overlay (the overlay is YAML, not dotenv — see `04-secrets-decrypt.md` §2) and wire them into rclone's `RCLONE_CONFIG_R2_*` env pattern (no on-disk `rclone.conf`; `RCLONE_CONFIG=/dev/null`):

```sh
cd $HOME/DEV/fCC/infra

eval "$(sops decrypt --input-type yaml --output-type yaml \
  ../infra-secrets/k3s/gxy-management/artemis.values.yaml.enc \
  | yq -r '.secretEnv |
    "export R2_ENDPOINT=\(.R2_ENDPOINT)
     export R2_ACCESS_KEY_ID=\(.R2_ACCESS_KEY_ID)
     export R2_SECRET_ACCESS_KEY=\(.R2_SECRET_ACCESS_KEY)"')"

export RCLONE_CONFIG=/dev/null
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACL=private
export RCLONE_CONFIG_R2_ENDPOINT="$R2_ENDPOINT"
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"

BUCKET=universe-static-apps-01
PREFIX=artemis/gxy-management

# Timestamp prefix in the filename means tail = newest.
TARGET=$(rclone lsf "r2:${BUCKET}/${PREFIX}/" --include '*.sql.gz' | sort | tail -1)
[ -n "$TARGET" ] || { echo "FAIL: no .sql.gz under r2:${BUCKET}/${PREFIX}/"; exit 1; }
echo "Target: $TARGET"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
rclone copyto "r2:${BUCKET}/${PREFIX}/${TARGET}" "${TMP}/${TARGET}"

# Integrity: gzip well-formed + pg_dumpall completion sentinel.
gunzip -t "${TMP}/${TARGET}" || { echo "FAIL: gunzip integrity"; exit 1; }
gunzip -c "${TMP}/${TARGET}" | tail -10 \
  | grep -q 'PostgreSQL database cluster dump complete' \
  || { echo "FAIL: completion sentinel missing"; exit 1; }
echo "OK: ${TARGET} gunzip-clean + sentinel present"
```

If the sentinel is missing the artefact is unusable (truncated dump) — stop and force a fresh nightly run (`08.A`) before continuing.

## C — Restore into a scratch Postgres

Bring up a throwaway `postgres:16-alpine` pod (matching the chart's `postgres.image.tag`) in the `artemis` namespace. It carries no tenant labels, so the postgres NetworkPolicy and the live StatefulSet are untouched. Restore replays the dump locally inside that pod; no connection to the live PG is made.

```sh
cd $HOME/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG="$(pwd)/.kubeconfig.yaml"

SCRATCH=artemis-restore-drill
# The artemis namespace enforces PodSecurity `restricted`; a bare
# `kubectl run` is rejected. The overrides satisfy the profile —
# uid/gid 70 = the postgres user in the alpine image.
kubectl -n artemis run "$SCRATCH" --image=postgres:16-alpine --restart=Never \
  --env=POSTGRES_PASSWORD=drill-only-throwaway \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":70,"runAsGroup":70,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"artemis-restore-drill","image":"postgres:16-alpine","env":[{"name":"POSTGRES_PASSWORD","value":"drill-only-throwaway"}],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
kubectl -n artemis wait --for=condition=Ready "pod/${SCRATCH}" --timeout=120s

# Copy the verified dump in and replay it as the superuser. The dump is
# `pg_dumpall --clean --if-exists`, so it recreates roles + BOTH tenant
# databases (artemis + hatchet) in one pass.
kubectl -n artemis cp "${TMP}/${TARGET}" "${SCRATCH}:/tmp/${TARGET}"
kubectl -n artemis exec "$SCRATCH" -- bash -c \
  "gunzip -c /tmp/${TARGET} | psql -U postgres -v ON_ERROR_STOP=0 >/tmp/restore.log 2>&1; tail -5 /tmp/restore.log"

# Error gate. ON_ERROR_STOP=0 lets the replay finish, so the log — not the
# exit code — is the evidence. Exactly two errors are expected, both from
# `--clean` replaying as the connecting superuser; anything else is a
# finding, not noise.
kubectl -n artemis exec "$SCRATCH" -- bash -c \
  'grep -c "^ERROR:" /tmp/restore.log; grep "^ERROR:" /tmp/restore.log | sort -u'
```

Expected, and the only two tolerated:

```
ERROR:  current user cannot be dropped
ERROR:  role "postgres" already exists
```

**Any third distinct error fails this drill.** The one that has actually occurred is `ERROR: unrecognized configuration parameter "transaction_timeout"` — emitted when the `postgres-rclone` image's `pg_dumpall` is newer than the server it dumped, so the dump carries a GUC the target does not know. That is a client/server version-skew signal: check `postgresql-client-*` in `docker/images/postgres-rclone/Dockerfile` against `postgres.image.tag` in the artemis chart values.

A row-count gate alone cannot catch this — the data still lands. The error count is the only place the skew shows.

## D — Row-count sanity gate

Confirm the two tenant databases came back and the artemis-owned tables hold plausible row counts. The `artemis` database owns six tables created by the migration runner (`internal/pg/migrations/`): `deploys`, `aliases`, `tombstones`, `outbox`, `sites`, `repo_requests`. The `hatchet` database is engine-owned (its schema is opaque to artemis) — for it, assert the database merely exists.

```sh
# Both tenant databases present?
kubectl -n artemis exec "$SCRATCH" -- \
  psql -U postgres -c '\l' | grep -E 'artemis|hatchet'

# Per-table row counts in the artemis tenant.
kubectl -n artemis exec "$SCRATCH" -- psql -U postgres -d artemis -c "
  SELECT 'deploys'       AS table, count(*) FROM deploys
  UNION ALL SELECT 'aliases',      count(*) FROM aliases
  UNION ALL SELECT 'tombstones',   count(*) FROM tombstones
  UNION ALL SELECT 'outbox',       count(*) FROM outbox
  UNION ALL SELECT 'sites',        count(*) FROM sites
  UNION ALL SELECT 'repo_requests',count(*) FROM repo_requests;
"
```

Pass criteria:

- Both `artemis` and `hatchet` databases listed by `\l`.
- All six artemis tables resolve (no `relation does not exist`) — proves the schema restored.
- The restore log holds no third distinct `ERROR:` beyond the two named in §C.
- `sites` count is non-zero and roughly matches the live registry size on a populated cluster (cross-check against `universe sites ls --json | jq '.count'`). On a freshly bootstrapped cluster zeros are acceptable — the gate is that the tables exist and the dump replayed.
- `deploys` is EXPECTED to be zero until the T24 backfill has run and the stage-2 worker is live — the deploy hot path never writes PG (design 0001 §M1 "deploy hot path untouched"); the index populates asynchronously. `outbox` non-zero at stage-1 is likewise expected (site.changed events accumulate until the relay starts).

If a table is missing or `\l` shows only one database, the dump is partial — treat the artefact as unusable and force a fresh nightly run.

## E — Tear down the scratch pod

```sh
kubectl -n artemis delete pod "$SCRATCH" --grace-period=0 --force
```

The scratch pod has no PVC (ephemeral container filesystem), so deletion reclaims everything. The local `$TMP` dir is removed by the `08.B` EXIT trap when the shell exits.

## F — RPO / RTO statement (ADR-019 stateful floor)

The drill validates the **M1 stateful floor** for artemis-PG, not the GA (CNPG-sweep) floor.

| Metric  | M1 value (what this artefact delivers) | Basis                                                                                                                                                                                                                                                                |
| ------- | -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **RPO** | \<= 24 hours                           | Nightly logical dump at 02:00 (`backup.schedule: 0 2 * * *`). Worst case loses up to a day of deploy/GC bookkeeping written since the last successful dump. This is the bundled single-node profile — there is NO WAL-continuous archive at M1.                      |
| **RTO** | \<= 60 minutes                         | Galaxy rebuild + restore of the newest R2 dump into a fresh `artemis-postgresql` StatefulSet, per ADR-019 §Stateful-pillar backup pattern. The drill above (steps B-D) is the rehearsal of the restore leg; the StatefulSet re-provision is the remaining wall-time. |

The serve plane (Caddy + R2) is unaffected by a PG outage — only new deploys + retention GC pause (ADR-016 consequence; ADR-020 §3 "HA scope = artemis only").

**Superseded for the `artemis` database on 2026-09-11.** The CloudNativePG pair is live, so the M1 row above describes the StatefulSet only. Ruling R2 of the `artemis-pg-pair` wave sets the pair's floor and supersedes ADR-019 §85 and ADR-023 §51.

| Metric                | `artemis-pg` value         | Basis                                                                                                                                                        |
| --------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **RPO**               | daily                      | The `artemis-pg-backup` CronJob at 02:00 UTC. There is still no WAL-continuous archive. Replication protects against instance loss, not against a bad write. |
| **RTO**               | the standby promotion time | Measure it in [15-artemis-pg-failover-drill.md](15-artemis-pg-failover-drill.md) §B and record the number there.                                             |
| **Retention ceiling** | 7 days                     | `pgBackup.retention: 7d`. An artefact older than that is deleted from R2 and cannot be restored.                                                             |

A daily RPO means a logical restore still loses up to a day. The pair removes the single-node failure mode; it does not remove the backup window.

Rehearse this drill before declaring artemis-PG GA, and after any change to the backup CronJob, the `postgres-rclone` image, or the bundled PG version.

## G — Production restore (destructive)

Run this only after a real data loss, and only with an announced window. Sections A to F are the rehearsal; this is the act.

### Decide which instance

Two Postgres instances now run in namespace `artemis`. Answer this first, because the artefact and the procedure differ.

| target                           | holds                                                            | artefact                                                                         | restore path                                   |
| -------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------- | ---------------------------------------------- |
| `artemis-postgresql` StatefulSet | the `hatchet` database, and the `artemis` database until cutover | `artemis-<ts>.sql.gz`, a `pg_dumpall` of both tenants                            | scale to zero, replay as superuser, scale back |
| `artemis-pg` CloudNativePG pair  | the `artemis` database after cutover                             | `artemis-<ts>.sql.gz` plus `artemis-roles-<ts>.sql` under `artemis/<galaxy>/pg/` | replay into the primary as the `artemis` owner |

Read `postgresCluster.cutover` in `k3s/gxy-management/apps/artemis/values.production.yaml` to learn which instance artemis is using right now. `false` means the StatefulSet. Restoring the wrong instance loses the window and changes nothing.

### Into the StatefulSet

1. Announce. Deploys and GC stop. Serving continues from R2.
1. `kubectl -n artemis scale statefulset artemis-postgresql --replicas=0`, then back to 1 once the volume is clear. See [12-node-drain-maintenance.md](12-node-drain-maintenance.md) for the disruption posture.
1. Replay the `pg_dumpall` artefact as the superuser, exactly as §C does against the scratch pod.
1. Verify with §D, then confirm recovery per [11-artemis-pg-outage-drill.md](11-artemis-pg-outage-drill.md).

### Into the CloudNativePG pair

The pair keeps `enableSuperuserAccess: false`, so the `postgres` role has a NULL password and no client can authenticate as it. The backup job therefore runs as the `artemis` owner and writes two files, not one.

1. Resolve the primary by label. Never name a pod ordinal — the primary moves after a failover.

   ```sh
   kubectl -n artemis get pod -l cnpg.io/cluster=artemis-pg,cnpg.io/instanceRole=primary -o name
   ```

1. Replay `artemis-roles-<ts>.sql` first. Each statement is a `DO` block guarded by `IF NOT EXISTS`, so a replay into a cluster that already has `artemis` or `streaming_replica` is safe.

1. **The exported roles carry no password.** The job cannot read `rolpassword` without superuser. Set each password again from the sops overlay after the replay, or the owner cannot log in.

1. Replay `artemis-<ts>.sql.gz`. It is `pg_dump --clean --if-exists` of the `artemis` database alone. It does not carry `hatchet`.

1. Verify with §D's row counts against the `artemis` database, then confirm `/healthz` and a live deploy.

A restore into a rebuilt pair is a different case again: let `bootstrap.initdb` create the database and the owner from `artemis-pg-app`, then replay the dump. Do not hand-create the owner role.

## H — Drill the pair (`artemis-pg`)

**Status: not yet run. Run on: —**

This is the R8 rehearsal for the CloudNativePG pair. ADR-019:177 records that R8 has passed only against the legacy StatefulSet dump. The 2026-06-05 and 2026-08-25 runs both drilled `artemis-gxy-management`, not the pair.

`postgresCluster.cutover` is `true`, so the live `artemis` database — registry, deploys, outbox, audit log, tombstones — is on the pair. The StatefulSet artefact no longer carries it.

### What is different from A to F

|                     | StatefulSet artefact                        | pair artefact                                          |
| ------------------- | ------------------------------------------- | ------------------------------------------------------ |
| R2 prefix           | `artemis/gxy-management/`                   | `artemis/gxy-management/pg/`                           |
| producer            | `artemis-backup` CronJob                    | `artemis-pg-backup` CronJob                            |
| files               | `artemis-<ts>.sql.gz`                       | `artemis-<ts>.sql.gz` **and** `artemis-roles-<ts>.sql` |
| command             | `pg_dumpall --clean --if-exists`            | `pg_dump --clean --if-exists -d artemis`               |
| databases           | `artemis` + `hatchet`                       | `artemis` only                                         |
| completion sentinel | `PostgreSQL database cluster dump complete` | `PostgreSQL database dump complete`                    |
| roles               | inside the dump, with passwords             | a separate file, **without** passwords                 |

Use the §B sentinel from the right row. The pair's dump is `pg_dump`, not `pg_dumpall`, so the word `cluster` is absent and the §B check fails on a good artefact.

### H1 — Confirm the pair's backup is current

```sh
cd $HOME/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG="$(pwd)/.kubeconfig.yaml"

kubectl -n artemis get cronjob artemis-pg-backup \
  -o jsonpath='schedule={.spec.schedule}{"\n"}lastSuccessful={.status.lastSuccessfulTime}{"\n"}'
```

Expect `schedule=0 2 * * *` and `lastSuccessful` within the past ~26 hours. Force a run the same way §A does, with `--from=cronjob/artemis-pg-backup`.

### H2 — Record the live counts first

The gate compares the restored counts against the live pair. Read the live numbers **before** the restore, from the primary.

```sh
PRIMARY=$(kubectl -n artemis get pod \
  -l cnpg.io/cluster=artemis-pg,cnpg.io/instanceRole=primary \
  -o jsonpath='{.items[0].metadata.name}')

kubectl -n artemis exec "$PRIMARY" -- psql -U postgres -d artemis -tAc "
SELECT 'deploys', count(*) FROM deploys
UNION ALL SELECT 'sites', count(*) FROM sites;"
```

Write both numbers down. The drill is a comparison, and a count read after the restore proves nothing.

Reference, read from the primary `artemis-pg-2` on 2026-09-12 07:36 UTC: `deploys=331`, `sites=73`, `aliases=123`, `outbox=314`, `tombstones=32`, `repo_requests=23`. All six tables are populated, so a zero in any of them is a finding, not an empty-cluster case. Prior read 2026-09-11 12:26 UTC: `deploys=327`, `outbox=305`, `tombstones=29`, the other three unchanged.

### H3 — Pull the two artefacts

Run §B's rclone block unchanged for the credentials and the `RCLONE_CONFIG_R2_*` exports, then substitute the prefix and pull both files:

```sh
# Same credentials block as §B.
BUCKET=universe-static-apps-01
PREFIX=artemis/gxy-management/pg

DUMP=$(rclone lsf "r2:${BUCKET}/${PREFIX}/" --include 'artemis-*.sql.gz' | sort | tail -1)
[ -n "$DUMP" ] || { echo "FAIL: no dump under r2:${BUCKET}/${PREFIX}/"; exit 1; }
STAMP=${DUMP#artemis-}; STAMP=${STAMP%.sql.gz}
ROLES="artemis-roles-${STAMP}.sql"
echo "Target: $DUMP + $ROLES"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
rclone copyto "r2:${BUCKET}/${PREFIX}/${DUMP}"  "${TMP}/${DUMP}"
rclone copyto "r2:${BUCKET}/${PREFIX}/${ROLES}" "${TMP}/${ROLES}"

gunzip -t "${TMP}/${DUMP}" || { echo "FAIL: gunzip integrity"; exit 1; }
gunzip -c "${TMP}/${DUMP}" | tail -10 \
  | grep -q 'PostgreSQL database dump complete' \
  || { echo "FAIL: completion sentinel missing"; exit 1; }
[ -s "${TMP}/${ROLES}" ] || { echo "FAIL: roles file empty"; exit 1; }
echo "OK: ${DUMP} + ${ROLES}"
```

The two files share one timestamp because the CronJob writes them in one run. A dump with no matching roles file means the run failed between the two uploads — take the previous pair.

### H4 — Restore into a scratch Postgres

Bring the scratch pod up exactly as §C does. The image is `postgres:16-alpine` and it is correct for the pair: the live `Cluster` runs `ghcr.io/cloudnative-pg/postgresql:16.14-standard-bookworm` and `SHOW server_version` reports `16.14 (Debian 16.14-1.pgdg12+1)`, re-measured 2026-09-12. Re-read the live `imageName` before the drill and match the major version:

```sh
kubectl -n artemis get cluster artemis-pg -o jsonpath='{.spec.imageName}{"\n"}'
```

Then replay the roles file first, create the database, and replay the dump as its owner.

```sh
SCRATCH=artemis-restore-drill
# ... §C's `kubectl run` block, unchanged ...

kubectl -n artemis cp "${TMP}/${ROLES}" "${SCRATCH}:/tmp/${ROLES}"
kubectl -n artemis cp "${TMP}/${DUMP}"  "${SCRATCH}:/tmp/${DUMP}"

kubectl -n artemis exec "$SCRATCH" -- bash -c "
  set -e
  psql -U postgres -v ON_ERROR_STOP=1 -f /tmp/${ROLES}
  psql -U postgres -v ON_ERROR_STOP=1 -c 'CREATE DATABASE artemis OWNER artemis'
  gunzip -c /tmp/${DUMP} | psql -U postgres -d artemis -v ON_ERROR_STOP=0 \
    >/tmp/restore.log 2>&1
  tail -5 /tmp/restore.log
"

kubectl -n artemis exec "$SCRATCH" -- bash -c \
  'grep -c "^ERROR:" /tmp/restore.log; grep "^ERROR:" /tmp/restore.log | sort -u'
```

The roles file replays under `ON_ERROR_STOP=1`. Every statement is a `DO` block guarded by `IF NOT EXISTS`, so a correct file raises nothing and any error is a finding.

The dump replays under `ON_ERROR_STOP=0` so the replay finishes and the log, not the exit code, is the evidence. **Expect zero `^ERROR:` lines.** This is a stricter gate than §C's, and the reason is the dump command: `pg_dump --clean --if-exists` writes `DROP ... IF EXISTS`, which raises `NOTICE: ... does not exist, skipping` on a fresh database, not `ERROR:`. The two tolerated errors in §C come from the `pg_dumpall` role section, which the pair's dump does not carry. **Any `ERROR:` line fails this drill.**

One error has a known meaning. `ERROR: unrecognized configuration parameter "<name>"` on a `SET` is client/server version skew: the `pg_dump` in `pgBackup.image` is newer than the scratch server. Check `postgresql-client-*` in `docker/images/postgres-rclone/Dockerfile` against the scratch image tag. The two are inside PostgreSQL 16 today — the backup client is 16.15, the pair is 16.14 — so no unknown GUC is expected.

The roles carry no password, so the restored `artemis` role cannot log in. That is correct for a drill and is the defect a production restore must repair — see §G.

### H5 — Compare against the live counts

```sh
kubectl -n artemis exec "$SCRATCH" -- psql -U postgres -d artemis -tAc "
SELECT 'deploys', count(*) FROM deploys
UNION ALL SELECT 'aliases', count(*) FROM aliases
UNION ALL SELECT 'tombstones', count(*) FROM tombstones
UNION ALL SELECT 'outbox', count(*) FROM outbox
UNION ALL SELECT 'sites', count(*) FROM sites
UNION ALL SELECT 'repo_requests', count(*) FROM repo_requests;"
```

Pass criteria:

- All six tables resolve. A missing table means a partial dump.
- `sites` equals the H2 number, or is lower by the sites registered since the dump ran. A higher count is impossible and is a finding.
- `deploys` is at or below the H2 number, for the same reason.
- The restore log holds zero `^ERROR:` lines.

Tear the scratch pod down with §E.

### H6 — Record the result

Replace the status line at the top of this section:

```
**Status: PASSED. Run on: <YYYY-MM-DD>.** Artefact `artemis-<ts>.sql.gz`. sites=<n> against live <n>. deploys=<n> against live <n>. ERROR lines: 0.
```

A drill with no recorded date has not been run. Do not write the line before the run.

## Related

- [`02-deploy-artemis-service.md`](02-deploy-artemis-service.md) — artemis deploy + staged durable-exec bootstrap + RELEASE-CUT CHECKLIST
- [`03-artemis-postdeploy-check.md`](03-artemis-postdeploy-check.md) §Durable-exec substrate check — post-deploy substrate verification
- [`04-secrets-decrypt.md`](04-secrets-decrypt.md) — sops envelope usage (the overlay is YAML, not dotenv)
- [`06-windmill-pg-backup.md`](archive/2026-07-07/06-windmill-pg-backup.md) — the windmill precedent this backup mirrors (schedule, sentinel, rclone pattern)
- ADR-019 §Stateful-pillar backup pattern — RPO/RTO floor + four-tier backup ladder
- ADR-020 (durable-execution model) — bundled-PG M1 vs CNPG-sweep GA trajectory
- `~/DEV/fCC/artemis/docs/design/0001-durable-execution-model.md` §3 — data ownership + stateful-pillar trajectory
- Chart: `k3s/gxy-management/apps/artemis/charts/artemis/templates/backup-cronjob.yaml` — the artefact producer
