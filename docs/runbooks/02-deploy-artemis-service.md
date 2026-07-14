# Deploy artemis service (Universe deploy proxy)

End-to-end operator runbook for the artemis svc on `gxy-management`. Public surface: `https://uploads.freecode.camp`. Spec: ADR-016.

Architecture: see `k3s/gxy-management/apps/artemis/README.md`. No Tailscale, no Caddy/cassiopeia hop, no CF Access (programmatic API behind GitHub OAuth Bearer + Traefik rate-limit + CF WAF).

## Preconditions (one-time, ClickOps + secret mint)

### 1. CF DNS A record

| Field | Value                               |
| ----- | ----------------------------------- |
| Zone  | `freecode.camp`                     |
| Name  | `uploads`                           |
| Type  | A                                   |
| Value | gxy-management public IP (any node) |
| Proxy | proxied (orange cloud)              |
| TTL   | auto                                |

Verify: `dig +short uploads.freecode.camp` returns CF anycast IPs.

### 2. CF zone SSL mode (no origin cert at k8s layer)

`freecode.camp` zone is on **Flexible SSL** — CF Edge terminates HTTPS using Universal SSL; CF→origin is plain HTTP. Matches the cassiopeia caddy precedent on the same zone. Verify via CF dashboard → SSL/TLS → Overview — mode = `Flexible`.

No origin cert mint required at the k8s layer; chart Gateway listener is HTTP :80 only. To flip the zone to Full Strict later, cassiopeia caddy + artemis charts both need TLS terminator listeners + sealed origin certs; file as a separate dispatch (`T-strict-tls`) — out of T34 scope.

### 3. GitHub OAuth App — `Universe CLI`

freeCodeCamp org → Settings → Developer settings → OAuth Apps → New:

- Name: `Universe CLI`
- Homepage URL: `https://uploads.freecode.camp`
- Authorization callback URL: `https://uploads.freecode.camp/oauth/callback` (unused for device flow but field is required)
- **Enable Device Flow** ✅
- Capture `client_id`.

### 4. Mint sops dotenv (SOT) — `infra-secrets/management/artemis.env.enc`

```bash
cp infra-secrets/management/artemis.env.sample \
   infra-secrets/management/artemis.env

# Fill 5 REQUIRED secret values:
#   R2_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY,
#   GH_CLIENT_ID, JWT_SIGNING_KEY (`openssl rand -hex 32`)
# Defaults (R2_BUCKET, GH_ORG, etc.) already set.

sops encrypt --in-place infra-secrets/management/artemis.env
mv infra-secrets/management/artemis.env \
   infra-secrets/management/artemis.env.enc

git -C infra-secrets add management/artemis.env.enc
git -C infra-secrets commit -m "feat(management): seal artemis env"
```

Decrypt incantation (canonical):

```bash
sops decrypt --input-type dotenv --output-type dotenv \
  infra-secrets/management/artemis.env.enc
```

Both flags required — sops auto-detect from `.enc` extension falls back to JSON parser; dotenv envelopes silently fail without explicit type flags. See `infra/CLAUDE.md` §Secrets.

### 5. Mint sops YAML overlay (helm input) — `infra-secrets/k3s/gxy-management/artemis.values.yaml.enc`

The dotenv envelope is the source of truth. The YAML overlay is the helm input mirror — same secret values in YAML form. One-time mint (also re-run on env-var rotation, ≤1×/quarter typical). Paste this block from the infra repo root:

```bash
SOT="../infra-secrets/management/artemis.env.enc"
TGT="../infra-secrets/k3s/gxy-management/artemis.values.yaml.enc"
TMP_DOT=$(mktemp); TMP_YAML=$(mktemp); TMP_ENC=$(mktemp)
trap "rm -f $TMP_DOT $TMP_YAML $TMP_ENC" EXIT
sops -d --input-type dotenv --output-type dotenv "$SOT" > "$TMP_DOT"
{
  echo "# Auto-generated mirror from $SOT. Do NOT hand-edit."
  echo
  echo "secretEnv:"
  while IFS='=' read -r KEY VAL; do
    case "$KEY" in
      R2_ENDPOINT|R2_ACCESS_KEY_ID|R2_SECRET_ACCESS_KEY|GH_CLIENT_ID|JWT_SIGNING_KEY|VALKEY_PASSWORD|SENTRY_DSN|POSTGRES_PASSWORD|ARTEMIS_DB_PASSWORD|HATCHET_DB_PASSWORD)
        ESC=$(printf '%s' "$VAL" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
        printf '  %s: "%s"\n' "$KEY" "$ESC"
        ;;
    esac
  done < "$TMP_DOT"
} > "$TMP_YAML"
python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$TMP_YAML"
sops --config ../infra-secrets/.sops.yaml \
  --encrypt --input-type yaml --output-type yaml "$TMP_YAML" > "$TMP_ENC"
mv "$TMP_ENC" "$TGT"
echo "Sealed $TGT"
```

No TLS material — CF Flexible SSL on `freecode.camp` (see §2).

The glob seals ten keys. The first six (`R2_*`, `GH_CLIENT_ID`, `JWT_SIGNING_KEY`, `VALKEY_PASSWORD`) are the always-required deploy-proxy secrets. `SENTRY_DSN` is optional — supply it (recommended in production) to enable external Sentry; if omitted, artemis runs with Sentry disabled (empty DSN = SDK off, per `internal/config` in the artemis repo). The chart never fails on a missing DSN; instead `NOTES.txt` prints a warning on `helm upgrade` when `env.ENVIRONMENT` is non-development. The last three (`POSTGRES_PASSWORD`, `ARTEMIS_DB_PASSWORD`, `HATCHET_DB_PASSWORD`) are durable-execution secrets the chart hard-requires once `postgres.enabled` is true — the `secret-env.yaml` template wraps them in `{{- if .Values.postgres.enabled }}` `required` guards, so a missing key fails the helm upgrade with `.Values.secretEnv.<KEY> is required when postgres.enabled`. Add all three to the dotenv SOT (`management/artemis.env.enc`) before sealing if you are deploying the durable-exec profile (production overlay flips `postgres.enabled: true`). `HATCHET_CLIENT_TOKEN` is NOT sealed here at mint time — it is minted from the live Hatchet engine in stage-2 (see §Staged durable-exec bootstrap).

After it succeeds, commit the new `.enc` from infra-secrets:

```bash
git -C ../infra-secrets add k3s/gxy-management/artemis.values.yaml.enc
git -C ../infra-secrets commit -m "feat(gxy-management): seal artemis values overlay"
git -C ../infra-secrets push
```

The dotenv stays the SOT — never hand-edit the YAML overlay.

### 6. Bootstrap the sites registry

Source of truth is Valkey, not a file. On a fresh cluster the registry starts empty; seed it with the `test` slug (smoke-target reserved for the post-deploy E2E suite) plus any production slugs:

```bash
universe sites register test --team staff
# Production slugs once you're past preconditions:
# universe sites register hello-universe --team bots,staff
# universe sites register <slug> --team <team>[,<team>...]
```

The CLI POSTs `/api/site/register` against artemis; staff-team membership gates writes (`REGISTRY_AUTHZ_TEAM` chart env, default `staff`). Cold-start reference: `freeCodeCamp/artemis` `config/sites.yaml` is a **dormant seed** of the historical map — not consumed at runtime; only useful when replaying entries after a full Valkey wipe.

### 7. artemis CI — first GHCR image

```bash
gh workflow run ci.yml --repo freeCodeCamp/artemis --ref main
```

Pin tag + digest in `infra/k3s/gxy-management/apps/artemis/values.production.yaml`:

```bash
docker buildx imagetools inspect ghcr.io/freecodecamp/artemis:<tag>
# copy the sha256:<digest> line
```

Update `image.tag` to `sha-<full-sha>@sha256:<digest>` and commit.

## Deploy

Once all preconditions land:

```bash
cd ~/DEV/fCC/infra
just release gxy-management artemis
```

The generic `deploy` recipe smart-dispatches on `apps/<app>/`:

1. Loads chart defaults (`charts/artemis/values.yaml`).
1. Loads production overlay (`apps/artemis/values.production.yaml`).
1. Decrypts + loads sops sealed overlay (`infra-secrets/k3s/gxy-management/artemis.values.yaml.enc`).
1. Runs `helm upgrade --install` into the `artemis` namespace.

Optional: `kubectl -n artemis rollout status deploy/artemis --timeout=120s`.

## Staged durable-exec bootstrap

The durable-execution substrate (bundled Postgres + Hatchet engine, ADR-020) comes up in two stages so the migration runner and the GC worker are never racing an un-deployed engine. The chart gates each stage on a single value:

| Stage | `postgres.enabled` | `env.HATCHET_ADDR` | `secretEnv.HATCHET_CLIENT_TOKEN` | What runs                                                                                     |
| ----- | ------------------ | ------------------ | -------------------------------- | --------------------------------------------------------------------------------------------- |
| 1     | `true`             | unset (`""`)       | unset                            | PG StatefulSet up, artemis migrations applied, GC **wired but dormant** — no worker, no relay |
| 2     | `true`             | engine gRPC addr   | sealed engine token              | worker + outbox relay live; retention GC executes                                             |

**Current production state (gxy-management):** stage 2, fully live, since the 2026-06-06 cutover. The production overlay (`apps/artemis/values.production.yaml`) is pinned `v1.2.2` with `postgres.enabled: true`, `env.HATCHET_ADDR: "hatchet-engine.artemis.svc.cluster.local:7077"`, and the sealed `HATCHET_CLIENT_TOKEN` — worker + outbox relay run, retention GC executes for real (`CLEANUP_DRY_RUN: "false"`, `CLEANUP_BLAST_CAP: "10"`), across `replicaCount: 3`. Stage 1 is a transient checkpoint gxy-management has already passed through — the two subsections below document the gate for a fresh galaxy bootstrap or a full DR rebuild, not gxy-management's day-2 posture.

### Stage 1 — Postgres up, migrations applied, worker dormant

Preconditions: the three durable-exec passwords sealed in the overlay (§5 glob), and the production overlay image pinned to a durable-exec-capable artemis build (>= `v1.0.0`; gxy-management's pre-cutover baseline was `0.8.0` — see the historical RELEASE-CUT CHECKLIST below).

```bash
cd ~/DEV/fCC/infra
just release gxy-management artemis
kubectl -n artemis rollout status statefulset/artemis-postgresql --timeout=120s
kubectl -n artemis rollout status deploy/artemis --timeout=120s
```

Confirm PG is up and the two tenant databases + roles were bootstrapped by the init ConfigMap (`postgres-init-configmap.yaml`):

```bash
kubectl -n artemis exec statefulset/artemis-postgresql -- \
  psql -U postgres -c '\l' | grep -E 'artemis|hatchet'
```

Expect both `artemis` and `hatchet` databases owned by their like-named roles.

Confirm migrations applied and the worker stayed dormant via the artemis pod logs:

```bash
kubectl -n artemis logs -l app.kubernetes.io/name=artemis --since=15m \
  | grep -E 'postgres: connected, migrations applied|gc: wired|worker: starting|outbox relay: started'
```

Stage-1 expectation: `postgres: connected, migrations applied` and `gc: wired` appear; `worker: starting` and `outbox relay: started` do **NOT** (they are gated on a non-empty `HATCHET_ADDR`, `cmd/artemis/main.go`).

`/readyz` semantics in stage 1: the readiness probe checks Valkey + R2 + Postgres. With PG up it returns `200 {"ready":true}`. If PG is unreachable while Valkey + R2 are fine, `/readyz` returns `200 {"ready":true,"degraded":true}` — the pod stays in the Service endpoints (deploy/serve still work; only GC is impaired). A `503` from `/readyz` means Valkey or R2 is down, not Postgres (`internal/handler/readyz.go`).

### Stage 2 — deploy the Hatchet engine, wire the worker

Once the Hatchet engine is deployed into the `artemis` namespace (operator step, sharing the bundled PG `hatchet` tenant — out of this chart's scope) and a client token has been minted from it:

1. Add the minted `HATCHET_CLIENT_TOKEN` to the dotenv SOT and re-seal the overlay (re-run §5 — the token rides in `secretEnv.HATCHET_CLIENT_TOKEN`, rendered by `secret-env.yaml` only when present).

1. Set `env.HATCHET_ADDR` in `values.production.yaml` to the engine Service's gRPC address. The port MUST match `hatchet.grpcPort` in the chart (default `7077`) and the deployed engine Service — verify against the deployed chart (hatchet-stack has shipped both `:7070` and `:7077`):

   ```yaml
   env:
     HATCHET_ADDR: "hatchet-engine.artemis.svc.cluster.local:7077"
   ```

1. Re-release and confirm the worker + relay came up:

   ```bash
   just release gxy-management artemis
   kubectl -n artemis rollout status deploy/artemis --timeout=120s
   kubectl -n artemis logs -l app.kubernetes.io/name=artemis --since=15m \
     | grep -E 'worker: starting|outbox relay: started'
   ```

Stage-2 expectation: both `worker: starting addr=<HATCHET_ADDR>` and `outbox relay: started` now appear.

## RELEASE-CUT CHECKLIST (durable-exec cutover — historical / DR-rebuild reference)

gxy-management already cut over (stage 1 on 2026-06-05, stage 2 on 2026-06-06; current pin `v1.2.2`). This checklist is kept for standing up a fresh galaxy or a full DR rebuild from a stateless (deploy-only) baseline — not needed for day-2 ops on gxy-management. Both items are hard gates — skipping either fails the helm upgrade or boots a worker against the wrong image.

1. **Seal the durable-exec passwords in the overlay.** Add `POSTGRES_PASSWORD`, `ARTEMIS_DB_PASSWORD`, and `HATCHET_DB_PASSWORD` to the dotenv SOT (`infra-secrets/management/artemis.env.enc`), then re-run the §5 mint block (its case-glob now seals all three). The chart hard-requires them when `postgres.enabled` — `secret-env.yaml` fails the upgrade with `.Values.secretEnv.HATCHET_DB_PASSWORD is required when postgres.enabled` if the overlay is missing the key. `DATABASE_URL` is auto-constructed from `ARTEMIS_DB_PASSWORD` unless set explicitly; `HATCHET_CLIENT_TOKEN` is sealed later in stage 2, not now.

1. **Bump the image pin off the pre-durable-exec baseline.** A pre-durable-exec image (gxy-management's baseline was `0.8.0`) does not contain the migration runner, GC wiring, or the Hatchet worker — a `postgres.enabled` release on it brings up PG but the pod never runs migrations or wires GC. Bump `image.tag` (and the `# release:` comment) to a durable-exec-capable release (>= `v1.0.0`) per the [§Image update](#image-update-deploy-new-artemis-release) procedure — resolve the digest, pin `X.Y.Z@sha256:<digest>`, commit.

After both land, run the staged bootstrap above (stage 1, then stage 2).

## Verify

```bash
kubectl -n artemis get pods,svc,gateway,httproute
curl -fsS https://uploads.freecode.camp/healthz
# expect: {"ok":true}
```

Confirm the running version + commit via the startup banner:

```bash
kubectl -n artemis logs -l app.kubernetes.io/name=artemis --since=15m \
  | grep "starting version"
```

Expected: `artemis: starting version=<semver-or-sha-or-branch> commit=<full-sha>` one line per replica. `VERSION` reflects the tag that triggered the build (semver on tag push, `sha-<sha>` on `workflow_dispatch`, branch name on branch push); `COMMIT` is the full sha. Both embedded via `-ldflags -X main.version=… -X main.commit=…` at build time.

E2E proxy smoke:

```bash
just verify-artemis
```

Recipe wraps `make integration` against the deployed artemis (see `docs/runbooks/03-artemis-postdeploy-check.md` for the full suite shape): init→upload→finalize→preview→promote→prod against the `test` site, marker-content match on both surfaces, rollback on exit. Exit 0 on green.

## Rotate

| What rotates                         | Recipe                                                                                                                         |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| GH_CLIENT_ID, R2 keys, JWT key       | edit dotenv → `sops -e --in-place`; re-run §5 mint block; `just release gxy-management artemis`                                |
| CF zone SSL flip (Flexible → Strict) | out of artemis scope — needs zone-wide change covering cassiopeia caddy too; file as `T-strict-tls` dispatch                   |
| sites registry entries               | `universe sites register/update/rm <slug> …` (staff-gated; live in seconds via `registry.changed` pub-sub, ≤60 s TTL fallback) |
| Image tag                            | see [§Image update](#image-update-deploy-new-artemis-release) — full procedure                                                 |

## Image update (deploy new artemis release)

Use when a new artemis release lands and must roll into gxy-management. Releases are tag-triggered: an operator with push rights to `freeCodeCamp/artemis` cuts a `vX.Y.Z` annotated tag per artemis `RELEASING.md`; `.github/workflows/docker-ghcr.yml` fires automatically on the tag push, builds the image, publishes to GHCR with tags `X.Y.Z` (bare semver, no `v`-prefix — docker/metadata-action strips it; OCI convention is bare semver), `X.Y`, and `sha-<full-sha>`, and auto-publishes a GitHub Release.

The image pin lives at `k3s/gxy-management/apps/artemis/values.production.yaml` under `image.tag` (format: `X.Y.Z@sha256:<digest>`). Bootstrap-only path (no semver tag exists yet) uses `sha-<full-sha>@sha256:<digest>` via the `workflow_dispatch` route — see §7.

### 1. Confirm drift

```bash
kubectl -n artemis get deploy artemis \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
git -C ~/DEV/fCC/artemis fetch --tags origin
git -C ~/DEV/fCC/artemis describe --tags --abbrev=0 origin/main
```

If the deployed semver lags the most-recent tag on artemis `origin/main`, drift is real — proceed.

### 2. Cut + push the artemis tag

The artemis-side flow (audit unreleased commits, pick the bump, annotated tag, regen CHANGELOG, push) is documented in `~/DEV/fCC/artemis/RELEASING.md`. Operator runs that flow; the tag push fires the GHCR workflow + the GH Release auto-publish step.

Watch the build:

```bash
gh run watch --repo freeCodeCamp/artemis --exit-status
```

### 3. Resolve digest

```bash
VERSION=X.Y.Z
docker buildx imagetools inspect "ghcr.io/freecodecamp/artemis:${VERSION}" \
  --format '{{.Manifest.Digest}}'
```

Output is the `sha256:<64-hex>` digest that becomes the load-bearing pin.

### 4. Bump pin

Edit `k3s/gxy-management/apps/artemis/values.production.yaml`:

```yaml
image:
  repository: ghcr.io/freecodecamp/artemis
  # release: X.Y.Z
  tag: "X.Y.Z@sha256:<digest>"
  pullPolicy: IfNotPresent
```

Both the `# release:` comment and the `tag:` value carry the bare semver (no `v`-prefix). The `@sha256:<digest>` suffix is the immutable anchor — kubelet pulls by digest when both are present. Never ship `tag: X.Y.Z` without the digest, and never ship `tag: latest` in production values.

Then bump the chart `appVersion` to the same bare semver in the **same commit**, so `helm list` reflects what is actually running (they drift otherwise). Edit `k3s/gxy-management/apps/artemis/charts/artemis/Chart.yaml` → set `appVersion: "X.Y.Z"` to match the `tag:` above. Leave the chart `version:` (chart-shape cadence) untouched unless the chart templates changed.

### 5. Commit

```bash
cd ~/DEV/fCC/infra
git add k3s/gxy-management/apps/artemis/values.production.yaml
git commit -m "chore(artemis): pin vX.Y.Z"
```

Operator pushes per infra-repo conventions (small-fix-direct vs PR-with-review threshold; see `PR_WORKFLOW.md`).

### 6. Deploy + watch rollout

```bash
just release gxy-management artemis
kubectl -n artemis rollout status deploy/artemis --timeout=180s
```

### 7. Verify

```bash
just verify-app gxy-management artemis
curl -fsS https://uploads.freecode.camp/healthz   # {"ok":true}
just verify-artemis
```

Confirm the running version banner picks up the new release:

```bash
kubectl -n artemis logs -l app.kubernetes.io/name=artemis --since=15m \
  | grep "starting version"
```

Expected: `artemis: starting version=X.Y.Z commit=<full-sha>` one line per replica.

`verify-artemis` is the authoritative E2E check — green = the new image serves init/upload/finalize/promote correctly against R2 + GH OAuth.

### Rollback

Revert the `values.production.yaml` commit and re-run `just release gxy-management artemis`. Image is digest-pinned so rollback is deterministic. No DB / state migration on artemis (stateless svc over R2).

Faster path when the regression is acute: `helm -n artemis history artemis` + `helm -n artemis rollback artemis <revision>` — re-pin the file afterward so the next `just release` does not undo the rollback.

## Failure modes

| Symptom                                                                                  | Likely cause                                   | Action                                                                                                     |
| ---------------------------------------------------------------------------------------- | ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `Error unmarshalling input json: invalid character '#'` from sops                        | dotenv decrypted without explicit type flags   | use the canonical incantation in §4                                                                        |
| Helm fail with `.Values.secretEnv.X is required`                                         | sops overlay missing key                       | re-run §5 mint block (paste-once)                                                                          |
| Helm fail with `.Values.secretEnv.HATCHET_DB_PASSWORD is required when postgres.enabled` | durable-exec password not sealed               | RELEASE-CUT CHECKLIST item 1 — seal the three PG passwords, re-run §5                                      |
| PG StatefulSet up but no migrations + GC never wired                                     | image pinned to pre-durable-exec `0.8.0`       | RELEASE-CUT CHECKLIST item 2 — bump image off `0.8.0`                                                      |
| Worker stays dormant after stage 2 (no `worker: starting` log)                           | `env.HATCHET_ADDR` empty or engine unreachable | set `HATCHET_ADDR` in `values.production.yaml`; verify engine Service gRPC port matches `hatchet.grpcPort` |
| `whoami` lists no sites on a freshly bootstrapped cluster                                | Valkey registry not yet seeded                 | `universe sites register <slug> --team <team>` per §6 bootstrap                                            |
| 503 on `uploads.freecode.camp/healthz`                                                   | Gateway not bound; HTTPRoute not picked up     | `kubectl -n artemis describe gateway,httproute` — check Traefik logs                                       |
| 502 / "no available server" via CF                                                       | CF zone SSL = Strict + origin no cert          | flip CF zone SSL to Flexible (zone-wide; matches cassiopeia caddy)                                         |
| ERR_SSL_PROTOCOL_ERROR in browser                                                        | CF zone SSL = Off                              | set CF zone SSL to Flexible                                                                                |
| 429 on bulk upload                                                                       | rate-limit middleware tripped                  | tune `rateLimit.average` / `.burst` in `values.production.yaml`                                            |

## Cross-references

- ADR-016 — Universe deploy proxy
- ADR-020 — durable-execution model (Hatchet engine, retention GC substrate)
- ADR-019 §Stateful-pillar backup pattern — RPO/RTO floor for the bundled PG
- `~/DEV/fCC/artemis/docs/design/0001-durable-execution-model.md` — staged bootstrap rationale (M1 bundled PG)
- `~/DEV/fCC/artemis/RELEASING.md` — artemis-side release flow (cut, tag, CHANGELOG, push)
- `~/DEV/fCC-U/Architecture/spike/field-notes/infra.md` §2026-04-26 build-residency, §2026-04-27 RUN-residency clause
- `~/DEV/fCC-U/Architecture/decisions/009-...` — Tailscale Operator rejected
- [`01-deploy-new-constellation-site.md`](01-deploy-new-constellation-site.md) — staff-side deploy flow against this service
- [`03-artemis-postdeploy-check.md`](03-artemis-postdeploy-check.md) — E2E post-deploy gate
- [`04-secrets-decrypt.md`](04-secrets-decrypt.md) — canonical sops dotenv decrypt
- [`05-r2-keys-rotation.md`](05-r2-keys-rotation.md) — R2 admin key rotation
- [`08-artemis-pg-restore-drill.md`](08-artemis-pg-restore-drill.md) — PG backup restore drill (RPO/RTO floor)
- `infra/CLAUDE.md` §Secrets
- `infra/k3s/gxy-management/apps/artemis/README.md`
- `infra/scripts/phase5-proxy-smoke.sh`
