# Artemis — registry restore after Valkey wipe

**Type:** Operator. Disaster recovery. **Cluster:** `gxy-management`. Namespace: `artemis`. **Spec:** chart at `k3s/gxy-management/apps/artemis/`. Registry KV substrate at `k3s/gxy-management/apps/valkey/`.

The artemis registry is the source of truth for per-site team authorization, stored in Valkey as `site:<slug>` hashes. When that KV is lost (AOF + RDB corruption, accidental `FLUSHDB`, volume loss before the nightly snapshot completes), every `universe static deploy` short-circuits at the `whoami → authorizedSites` preflight: `site_unauthorized` for every slug. Production alias pointers in R2 keep serving — `*.freecode.camp` reads route through cassiopeia caddy, not through artemis — but the entire deploy / promote / rollback path is offline until the registry is rebuilt.

This runbook covers two recovery paths in order of preference:

| Path            | Source of truth                                               | Use when                                                                  |
| --------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------- |
| RDB restore     | `infra-secrets/k3s/gxy-management/valkey/dump.rdb`            | Valkey RDB snapshot is present and uncorrupted; fastest path (5–10 min).  |
| Register replay | universe-cli `sites register` against the canonical site list | RDB is also lost; rebuild from R2 prefix scan + operator-maintained list. |

`07.A` is the probe; `07.B`/`07.C` are the RDB path; `07.D`/`07.E`/`07.F` are the replay path; `07.G` is the post-restore verify gate.

## A — Confirm the registry is gone

```sh
kubectl -n artemis exec deploy/artemis -- \
  curl -fsS http://valkey.valkey.svc.cluster.local:6379/ \
  | head -1 || true

# Direct shell — count `site:*` keys.
kubectl -n valkey exec deploy/valkey -- valkey-cli --scan --pattern 'site:*' | wc -l
```

Expected on a healthy registry: at least one entry per registered Universe site.

Expected on a wiped registry: `0`.

Cross-check via universe-cli (uses the public artemis API; doesn't need cluster access):

```sh
universe sites ls --json | jq '.count'
```

If both probes return `0`, proceed.

## B — Restore from RDB snapshot (preferred path)

Valkey's daily snapshot lives in the sops-vaulted operator bundle. Path varies by galaxy; for `gxy-management`:

```sh
sops -d --input-type binary --output-type binary \
  ../infra-secrets/k3s/gxy-management/valkey/dump.rdb.enc \
  > /tmp/valkey-dump.rdb
```

Stop Valkey, swap the dump, start it back:

```sh
kubectl -n valkey scale deploy/valkey --replicas=0
kubectl -n valkey cp /tmp/valkey-dump.rdb \
  $(kubectl -n valkey get pod -l app=valkey -o name | head -1):/data/dump.rdb
kubectl -n valkey scale deploy/valkey --replicas=1
```

Re-run the probe from `07.A`. If count matches the pre-incident registry size, jump to `07.G`. If the RDB itself is missing or fails to load, fall through to `07.D`.

## C — RDB snapshot freshness check

`dump.rdb` is captured by the operator-run RDB sync, not by an in-cluster CronJob. The freshness gate is:

```sh
sops -d --input-type binary --output-type binary \
  ../infra-secrets/k3s/gxy-management/valkey/dump.rdb.enc \
  | wc -c
```

Compare against the live `dbsize` recorded the last time the dump was captured. A non-zero size with a `dbsize` close to the live count is the green-light to use it; otherwise treat the RDB as suspect and fall through to register replay.

## D — Rebuild the canonical site list

When the RDB path is closed, rebuild the registry by replaying `universe sites register` against every slug. The site list comes from two complementary sources:

1. **R2 prefix scan** (machine-derivable). Every registered site has an R2 prefix at `<slug>.freecode.camp/`. Listing first-level prefixes is exhaustive for the live set.

   ```sh
   export AWS_ACCESS_KEY_ID="$(sops -d --extract '["R2_ADMIN_ACCESS_KEY_ID"]' \
     ../infra-secrets/k3s/gxy-management/artemis/secrets.env.enc)"
   export AWS_SECRET_ACCESS_KEY="$(sops -d --extract '["R2_ADMIN_SECRET_ACCESS_KEY"]' \
     ../infra-secrets/k3s/gxy-management/artemis/secrets.env.enc)"
   export AWS_ENDPOINT_URL="https://<account-id>.r2.cloudflarestorage.com"

   aws s3api list-objects-v2 \
     --bucket universe-static-apps-01 \
     --delimiter / \
     --query 'CommonPrefixes[].Prefix' \
     --output text \
     | tr '\t' '\n' \
     | sed -E 's|\.freecode\.camp/$||' \
     > /tmp/sites-from-r2.txt
   ```

1. **Operator-maintained mirror** (authoritative for `teams` membership). The R2 scan recovers slugs but NOT the `teams` list per slug — that's pure Valkey state with no other on-disk source. Maintain a one-time-keyed mirror in `infra-secrets/k3s/gxy-management/artemis/site-registry.csv.enc` (schema: `slug,teams_comma_separated`). When this runbook gets used, `sops -d` it into `/tmp/site-registry.csv` and use as the replay input.

   If the mirror doesn't exist yet (first-run; this is the seed step), reconstruct `teams` from operator memory — Universe is small enough today that every site has at most one team (`staff` by default).

Merge into a single replay file:

```sh
# Default `teams=staff` for any slug missing from the mirror.
awk -F, 'NR==FNR{m[$1]=$2; next} {print $1","(m[$1]?m[$1]:"staff")}' \
  /tmp/site-registry.csv /tmp/sites-from-r2.txt \
  > /tmp/replay.csv
```

## E — Register replay

Drive the replay through `universe sites register` so every write goes through the artemis API gate (validates auth + persists to Valkey identically to a first-time registration):

```sh
export GITHUB_TOKEN="$(op item get 'fCC GH staff PAT' --fields token)"

while IFS=, read -r slug teams; do
  [[ -z "${slug}" ]] && continue
  echo ">>> register ${slug} (teams=${teams})"
  universe sites register "${slug}" --team "${teams}" --json \
    | jq '{slug, success: (.error // empty | not), error: .error.code}'
done < /tmp/replay.csv
```

`universe sites register` is idempotent against the artemis 409 path: if a slug already exists (e.g., restart of the loop after a partial replay), the CLI surfaces `EXIT_CONFLICT` and the next iteration continues. Capture the JSON envelopes if you want a hard audit trail.

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

# Random sample (5 slugs).
universe sites ls --json | jq -r '.sites[].slug' | shuf | head -5 \
  | xargs -I{} sh -c 'universe sites ls --mine --json | jq --arg s {} ".sites[] | select(.slug==\$s)"'

# Per-site deploy listing still works.
universe static ls --site <slug> --json | jq '.deploys | length'
```

Expected:

- Registry count matches the R2 prefix scan ± any deferred adds/removes.
- Sampled slugs round-trip through `sites ls --mine`.
- `static ls` returns the same deploy list as before the incident (R2 wasn't touched).

If any of the three fails, re-run `07.E` for the affected slugs and re-check.

## Related

- `02-deploy-artemis-service.md` — fresh-install of the artemis chart.
- `04-secrets-decrypt.md` — sops envelope usage primer.
- `k3s/gxy-management/apps/valkey/scripts/import-sites.sh` — bulk-loader script (matches the Valkey key schema this runbook restores).
