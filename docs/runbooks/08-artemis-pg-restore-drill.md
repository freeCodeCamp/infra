# Artemis — Postgres backup restore drill

**Type:** Operator. Disaster-recovery rehearsal (read-mostly; writes only to a throwaway scratch pod). **Cluster:** `gxy-management`. Namespace: `artemis`. **Spec:** chart at `k3s/gxy-management/apps/artemis/`. Stateful floor: ADR-019 §Stateful-pillar backup pattern + ADR-020 (durable-execution model).

The artemis durable-exec substrate is a single-node bundled Postgres StatefulSet (`artemis-postgresql`) shared by two tenants — the `artemis` database (deploy/GC bookkeeping) and the `hatchet` database (engine state). Its availability floor is **not replication** — it is the nightly logical backup to R2 plus this rehearsed restore (chart `values.yaml` `postgres:` block; ADR-020 §3). This runbook restores the newest R2 dump into a throwaway scratch Postgres, sanity-checks row counts, and records the RPO/RTO the artefact actually delivers.

It is a **drill**: nothing here touches the live `artemis-postgresql` StatefulSet or the live databases. The scratch pod is a standalone `postgres:16-alpine` with no tenant labels, so neither the live PG nor the postgres NetworkPolicy is involved. A real production restore (overwrite the live instance) is a separate, destructive procedure — out of scope here; this drill is the confidence check that such a restore would succeed.

`08.A` confirms a backup exists; `08.B` pulls + integrity-checks the artefact; `08.C` restores into a scratch PG; `08.D` is the row-count sanity gate; `08.E` tears the scratch pod down; `08.F` is the RPO/RTO statement.

## Prerequisites

| Requirement                                   | Verify                                                                  |
| --------------------------------------------- | ----------------------------------------------------------------------- |
| infra repo checkout                           | `ls $HOME/DEV/fCC/infra/justfile`                                       |
| infra-secrets at canonical relative path      | `ls ../infra-secrets/k3s/gxy-management/artemis.values.yaml.enc`        |
| Org age key present                           | see `04-secrets-decrypt.md` §Preconditions                              |
| `rclone`, `sops`, `kubectl`, `gunzip` on PATH | `rclone version && sops --version`                                      |
| Durable-exec profile live                     | `kubectl -n artemis get sts artemis-postgresql` returns the StatefulSet |
| Nightly backup CronJob present                | `kubectl -n artemis get cronjob artemis-backup`                         |

The backup artefacts live under the R2 prefix `artemis/gxy-management/` in bucket `universe-static-apps-01`, named `artemis-<YYYYMMDD-HHMMSS>.sql.gz`. These literals come straight from the chart's `backup-cronjob.yaml` (`R2_PREFIX="artemis/${GALAXY}"`, `FILENAME="artemis-${TIMESTAMP}.sql.gz"`) and `backup.galaxy: gxy-management` / `env.R2_BUCKET` in the values files. The R2 credentials are the same admin keys artemis uses — sealed in the YAML overlay under `secretEnv.R2_*` (NOT a separate backup envelope; the CronJob reuses `artemis-env-secret`).

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

Decrypt the R2 admin keys from the YAML overlay (the overlay is YAML, not dotenv — see `04-secrets-decrypt.md` §2) and wire them into rclone's `RCLONE_CONFIG_R2_*` env pattern (no on-disk `rclone.conf`; `RCLONE_CONFIG=/dev/null`):

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
```

`pg_dumpall` replays into a fresh cluster; expect a clean run. `ON_ERROR_STOP=0` tolerates the leading `DROP`/`REVOKE` lines that `--clean` emits against objects a fresh scratch cluster does not yet have (those are expected, harmless errors on a clean target).

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

The serve plane (Caddy + R2) is unaffected by a PG outage — only new deploys + retention GC pause (ADR-016 consequence; ADR-020 §3 "HA scope = artemis only"). The ADR-019 GA target of RPO \<= 5 min (WAL-continuous) and RTO \<= 30-60 min lands at the platform CNPG sweep, which folds artemis-PG into the operator-managed T1+T2 ladder — that is OUT OF SCOPE for the M1 bundled profile this drill covers (ADR-020 §3 D1; chart `values.yaml` `postgres:` PG-HA posture note).

Rehearse this drill before declaring artemis-PG GA, and after any change to the backup CronJob, the `postgres-rclone` image, or the bundled PG version.

## Related

- [`02-deploy-artemis-service.md`](02-deploy-artemis-service.md) — artemis deploy + staged durable-exec bootstrap + RELEASE-CUT CHECKLIST
- [`03-artemis-postdeploy-check.md`](03-artemis-postdeploy-check.md) §Durable-exec substrate check — post-deploy substrate verification
- [`04-secrets-decrypt.md`](04-secrets-decrypt.md) — sops envelope usage (the overlay is YAML, not dotenv)
- [`06-windmill-pg-backup.md`](06-windmill-pg-backup.md) — the windmill precedent this backup mirrors (schedule, sentinel, rclone pattern)
- ADR-019 §Stateful-pillar backup pattern — RPO/RTO floor + four-tier backup ladder
- ADR-020 (durable-execution model) — bundled-PG M1 vs CNPG-sweep GA trajectory
- `~/DEV/fCC/artemis/docs/design/0001-durable-execution-model.md` §3 — data ownership + stateful-pillar trajectory
- Chart: `k3s/gxy-management/apps/artemis/charts/artemis/templates/backup-cronjob.yaml` — the artefact producer
