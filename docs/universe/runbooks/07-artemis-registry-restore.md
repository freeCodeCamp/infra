# Artemis — registry restore after Valkey wipe

**Type:** Operator. Disaster recovery. **Cluster:** `gxy-management`. Namespace: `artemis` (proxy) + `valkey` (KV substrate). **Spec:** chart at `k3s/gxy-management/apps/artemis/`. Registry KV substrate at `k3s/gxy-management/apps/valkey/`.

The artemis registry is the source of truth for per-site team authorization, stored in Valkey as `site:<slug>` hashes plus a `sites:all` set index. When that KV is lost (AOF + RDB corruption, accidental `FLUSHDB`, PVC loss), every `universe static deploy` short-circuits at the `whoami → authorizedSites` preflight: `site_unauthorized` for every slug. Production alias pointers in R2 keep serving — `*.freecode.camp` reads route through cassiopeia caddy, not through artemis — but the entire deploy / promote / rollback path is offline until the registry is rebuilt.

This runbook covers two recovery paths in order of preference:

| Path            | Source of truth                                                     | Use when                                                                                |
| --------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| RDB restore     | A local `.backups/valkey-<ts>.rdb` captured by `just backup-valkey` | A recent operator-captured snapshot exists and is uncorrupted; fastest path (5–10 min). |
| Register replay | universe-cli `sites register` against the canonical site list       | No usable RDB snapshot; rebuild from R2 prefix scan + operator-maintained slug list.    |

> **Backup-source reality (verified 2026-06-01).** There is **no** automated RDB→R2 mirror today and **no** sops-sealed `dump.rdb.enc` envelope in `infra-secrets`. The only RDB capture mechanism is the ad-hoc operator recipe `just backup-valkey gxy-management`, which runs `BGSAVE` in the pod and `kubectl cp`s `/data/dump.rdb` to `.backups/valkey-<timestamp>.rdb` on the operator host (justfile recipe `backup-valkey`, group `backup`). The nightly RDB→R2 mirror referenced in the chart comment (`backup-valkey` recipe header, "see the chart (T18)") is **ASPIRATIONAL / not-yet-implemented** — do not rely on it. Until T18 lands, the RDB restore path below is only available if an operator has previously run `just backup-valkey` and retained the artefact.

`07.A` is the probe; `07.B`/`07.C` are the RDB path; `07.D`/`07.E`/`07.F` are the replay path; `07.G` is the post-restore verify gate.

## A — Confirm the registry is gone

Valkey speaks RESP, not HTTP — probe it with `valkey-cli`, and probe artemis-side reachability through its HTTP API. The Valkey workload is a **StatefulSet** (`valkey-0`, single replica), not a Deployment; AUTH is required (`-a "$VALKEY_PASSWORD"`, injected into the pod env by the chart).

```sh
# In-cluster: count `site:*` keys directly (auth via in-pod $VALKEY_PASSWORD).
kubectl -n valkey exec valkey-0 -- \
  sh -c 'valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning --scan --pattern "site:*"' \
  | wc -l

# Registry index set cardinality (should equal the site count).
kubectl -n valkey exec valkey-0 -- \
  sh -c 'valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning SCARD sites:all'
```

Expected on a healthy registry: at least one `site:*` entry per registered Universe site, and `SCARD sites:all` matching.

Expected on a wiped registry: `0`.

Cross-check via the public artemis API (no cluster access needed; a `200` with an empty list confirms artemis is up but the registry is empty):

```sh
universe sites ls --json | jq '.count'
```

If both probes return `0`, proceed.

## B — Restore from a local RDB snapshot (preferred path)

This path applies **only if** an operator previously captured `.backups/valkey-<ts>.rdb` via `just backup-valkey gxy-management`. Pick the newest uncorrupted artefact:

```sh
ls -lt .backups/valkey-*.rdb | head
RDB=.backups/valkey-<ts>.rdb   # newest known-good
```

The Valkey StatefulSet runs with AOF enabled and a persistent `data` PVC (volumeClaimTemplate; **not** deleted on scale-down). Because AOF takes precedence over RDB on startup, a clean RDB restore requires removing the stale AOF so Valkey loads the dump:

```sh
# Scale the StatefulSet to 0 — the PVC survives.
kubectl -n valkey scale statefulset/valkey --replicas=0
kubectl -n valkey wait --for=delete pod/valkey-0 --timeout=120s

# Bring up a throwaway maintenance pod mounting the same PVC so we can
# swap the on-disk RDB and clear the AOF before valkey-0 starts.
kubectl -n valkey run valkey-maint --image=valkey/valkey:8.1.7-alpine \
  --restart=Never --overrides='
{
  "spec": {
    "containers": [{
      "name": "maint",
      "image": "valkey/valkey:8.1.7-alpine",
      "command": ["sleep","3600"],
      "volumeMounts": [{"name":"data","mountPath":"/data"}]
    }],
    "volumes": [{"name":"data","persistentVolumeClaim":{"claimName":"data-valkey-0"}}]
  }
}'
kubectl -n valkey wait --for=condition=Ready pod/valkey-maint --timeout=120s

# Replace the RDB and clear AOF so the next start loads the dump.
kubectl -n valkey cp "$RDB" valkey-maint:/data/dump.rdb
kubectl -n valkey exec valkey-maint -- sh -c 'rm -rf /data/appendonlydir /data/appendonly.aof* 2>/dev/null; true'

# Tear down the maintenance pod, restart valkey-0.
kubectl -n valkey delete pod valkey-maint --grace-period=0 --force
kubectl -n valkey scale statefulset/valkey --replicas=1
kubectl -n valkey wait --for=condition=Ready pod/valkey-0 --timeout=120s
```

Re-run the probe from `07.A`. If the `site:*` count matches the pre-incident registry size, jump to `07.G`. If the RDB is missing, stale, or fails to load, fall through to `07.D`.

> **AOF note.** Valkey rebuilds the AOF from the loaded RDB on first write after restart, so clearing it above is safe. If you skip the AOF removal, Valkey replays the stale AOF and your restored RDB is silently ignored.

## C — RDB snapshot freshness check

`.backups/valkey-<ts>.rdb` is captured only when an operator runs `just backup-valkey` — there is no in-cluster CronJob and no R2 mirror today (see backup-source reality note above). Before trusting a snapshot, check its size and timestamp against the live registry size you expect:

```sh
ls -l "$RDB"            # non-zero, plausible (>100 bytes; ~tens of KB for the live set)
date -r "$RDB"          # capture time — newer is better
```

A non-zero size with a capture time close to the incident is the green-light to use it; otherwise treat the RDB as suspect and fall through to register replay. To capture a fresh baseline snapshot for future incidents once the registry is healthy:

```sh
just backup-valkey gxy-management   # writes .backups/valkey-<ts>.rdb
```

## D — Rebuild the canonical site list

When the RDB path is closed, rebuild the registry by replaying `universe sites register` against every slug. The site list comes from two complementary sources:

1. **R2 prefix scan** (machine-derivable). Every registered site has an R2 prefix at `<slug>.freecode.camp/` in bucket `universe-static-apps-01`. Listing first-level prefixes is exhaustive for the live set. R2 admin credentials live in the **flat** sops envelope `artemis.values.yaml.enc` (a YAML helm overlay) under `secretEnv.R2_*` — decrypt with the YAML incantation (see `04-secrets-decrypt.md`), not as a dotenv:

   ```sh
   # Pull the three R2 keys out of the YAML overlay. Keys are
   # R2_ENDPOINT / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY (NOT R2_ADMIN_*).
   eval "$(sops decrypt --input-type yaml --output-type yaml \
     ../infra-secrets/k3s/gxy-management/artemis.values.yaml.enc \
     | yq -r '.secretEnv |
       "export AWS_ENDPOINT_URL=\(.R2_ENDPOINT)
        export AWS_ACCESS_KEY_ID=\(.R2_ACCESS_KEY_ID)
        export AWS_SECRET_ACCESS_KEY=\(.R2_SECRET_ACCESS_KEY)"')"

   aws s3api list-objects-v2 \
     --bucket universe-static-apps-01 \
     --delimiter / \
     --endpoint-url "$AWS_ENDPOINT_URL" \
     --query 'CommonPrefixes[].Prefix' \
     --output text \
     | tr '\t' '\n' \
     | sed -E 's|\.freecode\.camp/$||' \
     > /tmp/sites-from-r2.txt
   ```

1. **Operator-maintained teams mirror** (authoritative for `teams` membership). The R2 scan recovers slugs but NOT the `teams` list per slug — that is pure Valkey state with no other on-disk source. **There is no `teams` mirror envelope in `infra-secrets` today** — an encrypted CSV mirror is ASPIRATIONAL. Until one exists, reconstruct `teams` from operator memory: Universe is small enough that every site has at most one team (`staff` by default, matching `REGISTRY_AUTHZ_TEAM: "staff"` in `values.production.yaml`). The canonical seed list (11 sites as of 2026-05-10) lives in `k3s/gxy-management/apps/valkey/scripts/import-sites.sh`.

Build the replay file, defaulting every slug to `staff`:

```sh
awk '{print $1",staff"}' /tmp/sites-from-r2.txt > /tmp/replay.csv
```

If you maintain a richer slug→teams mapping out of band (e.g. a private note), merge it instead — the only requirement is a `slug,teams_comma_separated` CSV at `/tmp/replay.csv`.

## E — Register replay

Drive the replay through `universe sites register` so every write goes through the artemis API gate (validates auth + persists to Valkey identically to a first-time registration via the `HSET site:<slug>` + `SADD sites:all` + `PUBLISH registry.changed` path that `import-sites.sh` documents):

```sh
export GITHUB_TOKEN="$(op item get 'fCC GH staff PAT' --fields token)"

while IFS=, read -r slug teams; do
  [ -z "$slug" ] && continue
  echo ">>> register ${slug} (teams=${teams})"
  # --team accepts a comma-separated value or repeated flags; omit to
  # let the server default to `staff`.
  universe sites register "$slug" --team "$teams" --json \
    | jq '{slug, success, error: (.error.kind // null)}'
done < /tmp/replay.csv
```

`universe sites register` is safe to re-run after a partial replay: a slug that already exists comes back from artemis as a `409`-class error, which the CLI surfaces as a non-zero exit and an error envelope (`success: false`, `error.kind` = the artemis error code, e.g. `site_already_registered`). The loop continues to the next slug. There is no `EXIT_CONFLICT` constant — the CLI exit code is whatever the proxy error maps to (`src/lib/proxy-client.ts:wrapProxyError`). Capture the JSON envelopes if you want a hard audit trail.

## F — Restore alias pointers (only if RDB-less and R2-aliases also stale)

R2 holds the alias pointers (`<site>.freecode.camp/production` + `/preview`); they survive a Valkey wipe. **Do not touch them unless you confirmed they're stale.**

To re-pin from CLI:

```sh
# For each site whose alias is stale (operator decides):
universe static promote --from <deploy-id> --json | jq .
```

If alias pointers are lost too (R2 wipe alongside Valkey), every site's preview + production needs a fresh `universe static deploy --promote` — the registry rebuild alone won't bring sites back up.

## G — Verify

```sh
# Registry count.
universe sites ls --json | jq '.count'

# Random sample (5 slugs) round-trips through `sites ls --mine`.
universe sites ls --json | jq -r '.sites[].slug' | shuf | head -5 \
  | xargs -I{} sh -c 'universe sites ls --mine --json | jq --arg s {} ".sites[] | select(.slug==\$s)"'

# Per-site deploy listing still works.
universe static ls --site <slug> --json | jq '.deploys | length'
```

Expected:

- Registry count matches the R2 prefix scan ± any deferred adds/removes.
- Sampled slugs round-trip through `sites ls --mine`.
- `static ls` returns the same deploy list as before the incident (R2 wasn't touched).

If any of the three fails, re-run `07.E` for the affected slugs and re-check. Once green, capture a fresh baseline snapshot (`just backup-valkey gxy-management`) so the next incident has an RDB to restore from.

## Related

- `02-deploy-artemis-service.md` — fresh-install of the artemis chart.
- `04-secrets-decrypt.md` — sops envelope usage primer (note: `*.values.yaml.enc` are YAML, `*.env.enc` are dotenv — different `--input-type`).
- `k3s/gxy-management/apps/valkey/scripts/import-sites.sh` — bulk-loader script + canonical seed list (matches the Valkey key schema this runbook restores).
- `justfile` recipe `backup-valkey` (group `backup`) — the only RDB capture mechanism today; R2 mirror (chart T18) is aspirational.
