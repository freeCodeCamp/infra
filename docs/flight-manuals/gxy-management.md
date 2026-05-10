# Flight Manual — gxy-management

Control-plane galaxy. Today: Windmill (live), artemis (live, deploy
proxy), Valkey (registry KV substrate). ArgoCD + Zot + Atlantis are
**parked** — chart on disk, deploy frozen pending ADR-005 reactivation
trigger.

| Field             | Value                                                           |
| ----------------- | --------------------------------------------------------------- |
| Role              | Control plane (Windmill + artemis + Valkey)                     |
| Provider          | DigitalOcean FRA1                                               |
| Pod CIDR          | `10.1.0.0/16`                                                   |
| Service CIDR      | `10.11.0.0/16`                                                  |
| Cilium cluster ID | `1`                                                             |
| TLS posture       | Mixed: `freecodecamp.net` Full Strict; `freecode.camp` Flexible |
| Last rehearsed    | 2026-05-10 (post universe-master-audit)                         |

> **Read first:** [`UNIVERSE.md`](UNIVERSE.md) §0 prereqs, §1 DNS, §2
> secrets, §3 shared infra. Not repeated here.
>
> **Working-directory rule (HARD):** `cd k3s/gxy-management/` before any
> cluster-touching recipe. Each section repeats the `cd`.
>
> **Idempotency:** every state-changing step has a "skip-if-already-done"
> guard. Re-run any section in isolation and the second run is a no-op.

This chapter feeds the cassiopeia GA design at
[`../architecture/rfc-gxy-cassiopeia-ga.md`](../architecture/rfc-gxy-cassiopeia-ga.md)
(Valkey substrate, artemis registry decouple). The cassiopeia chapter
links here for the deploy-side bring-up.

## §A — k3s bootstrap

### A.1 Pre-flight (cassiopeia + management-specific files)

`infra-secrets/k3s/gxy-management/`:

- `windmill.values.yaml.enc` — sops overlay for windmill chart
- `windmill-backup.secrets.env.enc` — DO Spaces creds for daily pg_dump
- `artemis.values.yaml.enc` — sops overlay for artemis chart (R2 admin
  creds, GH OAuth client id, JWT signing key)
- `valkey.values.yaml.enc` — sops overlay for valkey chart (AUTH password)

`infra-secrets/global/tls/freecodecamp-net.{crt,key}.enc` — CF Origin
wildcard for the `freecodecamp.net` zone (windmill / future argocd /
future zot reuse).

```bash
cd ~/DEV/fCC/infra
just secret-verify-all
```

### A.2 DigitalOcean infrastructure (one-time, ClickOps)

3× `s-8vcpu-16gb-amd` in FRA1, named `gxy-vm-management-k3s-{1,2,3}`,
tag `gxy-management-k3s`, image Ubuntu 24.04, VPC `universe-vpc-fra1`,
cloud-init `cloud-init/basic.yml`. Cloud Firewall: create
`gxy-fw-fra1` (or attach tag if it already exists). VPC rules
(source `10.110.0.0/20`): `2379-2380, 4240, 4244, 5001, 6443, 8472,
10250`. Public rules: `22/TCP, 80/TCP, 443/TCP`.

Idempotency:

```bash
test "$(doctl compute droplet list --tag-name gxy-management-k3s --format ID --no-header | wc -l)" -eq 3 \
  && echo "✓ 3 management droplets present" \
  || echo "↻ provision via DO dashboard"
```

DO Spaces bucket `net-freecodecamp-universe-backups` in FRA1
(per `UNIVERSE.md §3`). Single bucket, prefix-scoped per use
(`etcd/<galaxy>/`, `windmill/<galaxy>/`).

### A.3 Tailscale + cluster bootstrap

```bash
cd ~/DEV/fCC/infra
just play tailscale--0-install gxy_management_k3s
just play tailscale--1b-up-with-ssh gxy_management_k3s

cd k3s/gxy-management
just play k3s--bootstrap gxy_management_k3s
```

`k3s--bootstrap` runs validate → prerequisites → k3s deploy → Cilium →
verify + kubeconfig. Idempotent.

### A.4 Verify

```bash
cd ~/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get nodes -o wide
# All 3 Ready, InternalIP = VPC IPs (10.110.0.x)

kubectl top nodes
# All 3 reporting CPU/memory (metrics-server working)

kubectl get pods -n kube-system
# All Running, no CrashLoopBackOff

kubectl exec -n kube-system $(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}') -- cilium-health status
# 3/3 reachable, all endpoints 1/1
```

## §B — Windmill

### B.1 Helm install

```bash
cd ~/DEV/fCC/infra

# Skip if release already healthy.
helm get values -n windmill windmill >/dev/null 2>&1 \
  && echo "✓ windmill release present" \
  || just helm-upgrade gxy-management windmill

just deploy gxy-management windmill
```

`just deploy` decrypts the sops overlay + applies kustomize manifests
(Gateway, HTTPRoute, TLS secret) on top of the helm release.

### B.2 Verify

```bash
cd ~/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get pods -n windmill
# 6 pods Running (app, 2× workers-default, workers-native, extra, postgresql)

kubectl get gateway -n windmill
# windmill-gateway   Programmed=True

kubectl get httproute -n windmill
# windmill-route, http-redirect

kubectl get svc -n kube-system traefik
# EXTERNAL-IP shows all 3 node VPC IPs
```

### B.3 Restore Windmill state (REBUILD ONLY)

Skip on fresh install. Only applies when this chapter is replayed to
rebuild an existing cluster — the bundled PostgreSQL comes up empty
after B.1, so the pre-teardown `pg_dumpall` must be loaded before end
users hit the UI.

For a rebuild, do this BEFORE §D DNS cutover.

#### B.3.1 Preconditions

- Pre-teardown pg_dump exists at
  `k3s/gxy-management/.backups/windmill-<ts>.sql.gz` (run
  `just windmill-backup gxy-management` before teardown)
  OR S3 copy at
  `s3://net-freecodecamp-universe-backups/windmill/gxy-management/windmill-<ts>.sql.gz`.
- `windmill-postgresql-0` pod Running (B.2 green).

#### B.3.2 Quiesce Windmill app + worker pods

The bundled PostgreSQL refuses `DROP DATABASE windmill` while app
holds connections (~35 sessions per deploy). Scale Windmill
deployments to zero first; leave the StatefulSet up.

```bash
cd ~/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Record current replica counts for restore after (chart 4.x → 1/1/2/1).
kubectl get deploy -n windmill -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.spec.replicas}{"\n"}{end}'

kubectl scale deploy -n windmill \
  windmill-app windmill-extra windmill-workers-default windmill-workers-native \
  --replicas=0

# Wait until only windmill-postgresql-0 is Running.
kubectl get pods -n windmill -w
```

#### B.3.3 Restore

```bash
DUMP=k3s/gxy-management/.backups/windmill-<ts>.sql.gz   # adjust timestamp
PG_POD=$(kubectl get pod -n windmill -l app=windmill-postgresql-demo-app -o jsonpath='{.items[0].metadata.name}')

kubectl cp "$DUMP" "windmill/${PG_POD}:/tmp/"

# Kill stragglers + drop the fresh-install DB so the dump's CREATE lands cleanly.
kubectl exec -n windmill "${PG_POD}" -- psql -U postgres -c "
  SELECT pg_terminate_backend(pid) FROM pg_stat_activity
  WHERE datname='windmill' AND pid <> pg_backend_pid();"
kubectl exec -n windmill "${PG_POD}" -- psql -U postgres -c "DROP DATABASE IF EXISTS windmill;"

kubectl exec -n windmill "${PG_POD}" -- bash -c \
  "gunzip -c /tmp/$(basename $DUMP) | psql -U postgres"
```

Expected noise: `NOTICE` / `ERROR: role "postgres" already exists` and
similar — harmless (`pg_dumpall --clean --if-exists` emits idempotent
DROP statements that race with the bootstrapped `postgres` super-role).
Constraint violations on `INSERT` are real errors.

#### B.3.4 Scale back + verify

```bash
# Restore original replica counts (chart 4.x defaults).
kubectl scale deploy -n windmill windmill-app --replicas=1
kubectl scale deploy -n windmill windmill-extra --replicas=1
kubectl scale deploy -n windmill windmill-workers-default --replicas=2
kubectl scale deploy -n windmill windmill-workers-native --replicas=1

kubectl rollout status deploy -n windmill windmill-app --timeout=5m
kubectl rollout status deploy -n windmill windmill-workers-default --timeout=5m

# Row counts
kubectl exec -n windmill "${PG_POD}" -- psql -U postgres -d windmill -c "
  SELECT
    (SELECT count(*) FROM script) AS scripts,
    (SELECT count(*) FROM flow) AS flows,
    (SELECT count(*) FROM app) AS apps,
    (SELECT count(*) FROM resource) AS resources,
    (SELECT count(*) FROM usr) AS users,
    (SELECT count(*) FROM schedule) AS schedules
  ;"

# wmill CLI sync check (from ~/DEV/fCC-U/windmill)
cd ~/DEV/fCC-U/windmill
wmill sync pull --workspace platform --yes
# Expect: zero deletions, zero new additions.
```

### B.4 CNPG migration (parked)

The bundled PostgreSQL is single-instance, no replication, no WAL
archiving. CNPG migration (P0-05 in prior audit) is parked behind the
gxy-backoffice provisioning trigger. Tracked in `TODO-park §"CNPG
migration for Windmill"`.

## §C — Valkey (registry KV substrate)

Per [RFC §B](../architecture/rfc-gxy-cassiopeia-ga.md#section-b-static-apps-registry-kv-substrate-matrix-and-decision-s1):
single-instance Valkey in its own namespace, AOF on PVC, ClusterIP
locked to artemis pods via NetworkPolicy. Cross-namespace DNS:
`valkey.valkey.svc.cluster.local:6379`.

> **Bring-up gate:** §C runs **before** §D — artemis depends on
> Valkey reachable + populated when `REGISTRY_BACKEND=valkey` is
> set on the artemis chart.

### C.1 Mint the sops envelope (once per cluster lifetime)

Skip if `$SECRETS_DIR/k3s/gxy-management/valkey.values.yaml.enc`
already exists. Re-mint only if rotating the password (which forces
a Valkey pod restart — see C.5 rotation runbook).

```bash
# 1. Generate AUTH password (64 hex chars).
openssl rand -hex 32 > /tmp/valkey-pass.txt

# 2. Build the plaintext envelope from the chart-shipped template.
cp ~/DEV/fCC/infra/k3s/gxy-management/apps/valkey/secrets/valkey.values.yaml.enc.template \
   /tmp/valkey-mint.yaml

# 3. Substitute the password into the template (in-place).
PASS=$(cat /tmp/valkey-pass.txt)
sed -i.bak "s|REPLACE_WITH_64_HEX_CHARS_FROM_OPENSSL_RAND_HEX_32|$PASS|" \
  /tmp/valkey-mint.yaml
rm /tmp/valkey-mint.yaml.bak

# 4. Encrypt to the infra-secrets target path.
sops --input-type yaml --output-type yaml --encrypt /tmp/valkey-mint.yaml \
  > "$SECRETS_DIR/k3s/gxy-management/valkey.values.yaml.enc"

# 5. Wipe the plaintext tempfiles.
shred -u /tmp/valkey-mint.yaml /tmp/valkey-pass.txt

# 6. Commit + push the .enc in infra-secrets.
cd "$SECRETS_DIR"
git add k3s/gxy-management/valkey.values.yaml.enc
git commit -m "feat(gxy-management): valkey overlay"
# (push is operator-owned per covenant)
```

### C.2 Helm install

```bash
cd ~/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# skip-if-already-deployed guard
helm -n valkey list -q | grep -q '^valkey$' \
  && echo "✓ valkey release present" \
  || just deploy gxy-management valkey
```

The `just deploy` recipe auto-decrypts the sops envelope at
`$SECRETS_DIR/k3s/gxy-management/valkey.values.yaml.enc` (with the
required `--input-type yaml --output-type yaml` flags — see
`docs/runbooks/04-secrets-decrypt.md`) into a per-invocation
tempfile and appends `--values $TMP` to the helm chain. The
decrypted file lives only inside the recipe's shell scope and is
unlinked on shell exit (trap).

### C.3 Verify

```bash
cd ~/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl -n valkey get pods,svc,pvc
# valkey-0 Running (StatefulSet); svc valkey ClusterIP + valkey-headless;
# data-valkey-0 PVC bound to local-path-pv-...

# Auth + ping (sops bare invocations on `.enc` route to JSON parser
# and fail with `invalid character '#'` — both type flags required
# on every read verb. See feedback memory + 04-secrets-decrypt.md.)
PASS=$(sops --input-type yaml --output-type yaml --decrypt \
  "$SECRETS_DIR/k3s/gxy-management/valkey.values.yaml.enc" \
  | yq '.secretEnv.VALKEY_PASSWORD')
kubectl -n valkey exec sts/valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning PING
unset PASS
# → PONG

# Persistence config (anonymized password — kubectl exec env var
# is the cleanest path; see C.4 / import-sites.sh)
kubectl -n valkey exec sts/valkey -- sh -c \
  'valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning CONFIG GET appendonly'
# → 1) "appendonly"  2) "yes"
```

### C.4 Sites import (one-shot, cutover step)

Pre-populates Valkey with the 11-site canonical registry derived
from R2 (`rclone ls r2-gxy:universe-static-apps-01 | rg production`).
Run **before** the artemis cutover in §D so the moment artemis flips
to `REGISTRY_BACKEND=valkey` no `*.freecode.camp` request 404s.

Skip if `SMEMBERS sites:all` already returns 11 entries.

```bash
cd ~/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# 1. Dry-run prints the HSET / SADD / PUBLISH commands, no writes.
apps/valkey/scripts/import-sites.sh --dry-run

# 2. Apply against the live pod. Idempotent — re-run is safe (HSET
#    overwrites with identical fields; SADD is set-typed).
apps/valkey/scripts/import-sites.sh

# 3. Verify
kubectl -n valkey exec sts/valkey -- sh -c \
  'valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning SMEMBERS sites:all' \
  | sort
# → 11 slugs, alphabetized
```

### C.5 Backups (deferred — post-GA)

Nightly RDB → R2 mirror is **not** part of the v0.1 chart. Tracked as
post-GA scope in the cassiopeia GA RFC. Until then, Valkey AOF on the
local-path PVC is the sole durability layer; an unscheduled node loss
on the gxy-management node forfeits up to 1s of writes (`appendfsync
everysec`). Acceptable for the 11-site / write-bursty-by-staff
workload; revisit if write rate grows.

### C.6 Cutover smoke gate G13 — 2026-05-11

Closes the cassiopeia registry cutover phase (P7) plus G12 idempotency
rehearsal. Run by mrugesh from a laptop hitting
`https://uploads.freecode.camp` after Phase 5 deploy of artemis chart
0.2.0 / image `sha256:f61f2b…`. Both rounds produced identical output
(modulo per-call `created_at` / `updated_at` timestamps stamped by
artemis at write time).

Pre-state — `/api/sites` returns the 11 canonical slugs:

```console
$ curl -sS -H "Authorization: Bearer $(gh auth token)" \
    https://uploads.freecode.camp/api/sites | jq 'length'
11
```

Round 1 — `universe sites` write path against staff-authz endpoints:

```console
$ universe sites ls    (universe-cli v0.5.0 / built locally)
│  SLUG                   TEAMS  CREATED BY  CREATED AT
│  checkers               staff  mrugesh     2026-05-10T00:00:00Z
│  cognitive-biases       staff  mrugesh     2026-05-10T00:00:00Z
│  five-dice              staff  mrugesh     2026-05-10T00:00:00Z
│  gomoku                 staff  mrugesh     2026-05-10T00:00:00Z
│  hello-universe         staff  mrugesh     2026-05-10T00:00:00Z
│  newton-laws-of-motion  staff  mrugesh     2026-05-10T00:00:00Z
│  number-tiles           staff  mrugesh     2026-05-10T00:00:00Z
│  projectile-motion      staff  mrugesh     2026-05-10T00:00:00Z
│  reversi                staff  mrugesh     2026-05-10T00:00:00Z
│  share-python           staff  mrugesh     2026-05-10T00:00:00Z
│  test                   staff  mrugesh     2026-05-10T00:00:00Z

$ universe sites register smoke-test  →  201, teams=[staff], created_by=raisedadead
$ universe sites ls | rg smoke-test    →  present
$ universe sites update smoke-test --team=staff,news-editors  →  200
$ curl … /api/sites | jq '.[] | select(.slug=="smoke-test")'
  →  teams=["staff","news-editors"], updated_at > created_at
$ universe sites rm smoke-test         →  204 (R2 bytes preserved per cron)
$ universe sites ls | rg smoke-test || echo absent ✓
absent ✓
```

Round 2 — same cycle, different per-call timestamps:

```console
$ universe sites register smoke-test
◆  Registered smoke-test
│    Slug:        smoke-test
│    Teams:       staff
│    Created by:  raisedadead
│    Created at:  2026-05-10T19:10:39.588586015Z

$ universe sites update smoke-test --team=staff
◆  Updated smoke-test
│    Slug:        smoke-test
│    Teams:       staff
│    Updated at:  2026-05-10T19:10:40.67148201Z      ← +1.1s, server-stamped

$ universe sites rm smoke-test
◆  Deleted smoke-test
│    Note: R2 deploy bytes are NOT removed; they age out via the
│          post-GA cleanup cron.

$ universe sites ls --json | jq '.count, ([.sites[].slug] | any(. == "smoke-test"))'
11
false
```

Identical output between rounds (modulo timestamps) → V3 idempotency
holds end-to-end. G13 closed; G12 closed in same evidence trail.

Side-finding (now closed): the artemis CiliumNetworkPolicy initially
omitted in-cluster DNS L7 patterns. Cilium DNS proxy filtered the
`valkey.valkey.svc.cluster.local` query, returning a malformed
response that Go's resolver surfaced as `server misbehaving`. The new
artemis pod CrashLoopBackOff'd on startup; old pods kept serving
(RollingUpdate). Resolved by adding `matchName:
valkey.valkey.svc.cluster.local` plus `matchPattern:
*.*.svc.cluster.local` to the L7 rules (`*` doesn't cross dots in
Cilium pattern semantics). Two follow-up commits during cutover:
`fix(artemis): allow cluster.local DNS in CNP` (insufficient — single-
label wildcard) and `fix(artemis): CNP DNS pattern crosses dots`
(closed it).

The trap had bitten before — woodpecker forge list on gxy-launchbase
on 2026-04-07 with the same `server misbehaving` shape on a
cross-namespace Postgres lookup. That history was captured in the
archived field-notes (`Universe/spike/field-notes/archive/2026-05-10/infra.md`)
but never promoted to canonical guidance, so the artemis chart
re-discovered it from scratch. Promoted now to
[`docs/infra-guides/cilium-cnp.md`](../infra-guides/cilium-cnp.md) —
read before adding any cross-namespace egress to a CNP'd pillar.

## §D — Artemis (deploy proxy)

Public surface `https://uploads.freecode.camp` (NOT
`*.freecodecamp.net` — Universe domain, Flexible SSL). Auth: GitHub
OAuth Bearer + deploy-session JWT. RUN-residency clean: image pulls
from `ghcr.io/freecodecamp/artemis` direct; never via the zot mirror
co-located on this galaxy (chicken-egg on cluster wipe).

### D.1 Preconditions (one-time per cluster)

| #   | What                                                                           | Where                                                           |
| --- | ------------------------------------------------------------------------------ | --------------------------------------------------------------- |
| 1   | DNS A record `uploads.freecode.camp` → 3 node public IPs                       | CF dashboard                                                    |
| 2   | CF zone `freecode.camp` SSL = `Flexible`                                       | CF dashboard                                                    |
| 3   | GitHub OAuth App `Universe CLI` (Device Flow ✅)                               | freeCodeCamp org settings                                       |
| 4   | Sealed dotenv `infra-secrets/management/artemis.env.enc`                       | `sops encrypt --input-type dotenv --output-type dotenv`         |
| 5   | Sealed YAML overlay `infra-secrets/k3s/gxy-management/artemis.values.yaml.enc` | `docs/runbooks/02-deploy-artemis-service.md` §5                 |
| 6   | Valkey running (§C.2 green)                                                    | this chapter §C                                                 |
| 7   | First GHCR image build for artemis                                             | `gh workflow run ci.yml --repo freeCodeCamp/artemis --ref main` |

### D.2 Deploy

```bash
cd ~/DEV/fCC/infra

helm get values -n artemis artemis >/dev/null 2>&1 \
  && echo "✓ artemis release present" \
  || true

just deploy gxy-management artemis
```

The recipe layers chart values → production overlay → sops sealed
overlay; in the post-RFC chart the `--set-file
sites=$ARTEMIS_REPO/config/sites.yaml` from the legacy bring-up is
**dropped**. Sites map lives in Valkey (§C). The chart sets:

- `VALKEY_ADDR=valkey.artemis.svc.cluster.local:6379`
- `VALKEY_PASSWORD` from sops overlay
- `REGISTRY_BACKEND=valkey` (default once migration step 5 from RFC §B
  Migration shape lands in artemis repo)

Backward-compat one-release window: artemis can read either Valkey
(`REGISTRY_BACKEND=valkey`) or the helm-embedded ConfigMap
(`REGISTRY_BACKEND=sites_yaml`). Operators flip the env after the §C.3
import succeeds.

### D.3 Verify

```bash
cd ~/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl -n artemis get pods,svc,gateway,httproute
# 3 pods Running, gateway Programmed, httproute attached

curl -fsS https://uploads.freecode.camp/healthz
# → {"ok":true}
```

### D.4 Smoke

```bash
cd ~/DEV/fCC/infra
just artemis-postdeploy-check
just phase5-smoke
```

E2E flow: init → upload → finalize (preview) → preview curl →
promote → prod curl. Marker-content match on both surfaces. Trap
rolls back to the prior production deploy on exit (success OR
failure). Exit 0 = green.

### D.5 Cluster-wipe rebuild rehearsal (operational invariant)

When rehearsing a galaxy rebuild from scratch, **run with zot
unreachable**. Artemis must come up green from a cold cluster with
zero zot dependency in the image-pull path. If artemis fails to pull
its image without zot, RUN-residency is broken — fix the chart before
claiming the rebuild green.

## §E — Parked apps (DO NOT DEPLOY)

ArgoCD, Zot, Atlantis chart artifacts live on disk in
`k3s/gxy-management/apps/{argocd,zot}/` (Atlantis is not yet on disk).
**Do not run** `just helm-upgrade gxy-management {argocd,zot}` — it
will succeed and create cluster state that contradicts the parked
status in ADR-005.

| App      | Status                                    | Reactivation gate                                                                   |
| -------- | ----------------------------------------- | ----------------------------------------------------------------------------------- |
| ArgoCD   | parked per ADR-005 amend 2026-05-04       | Multi-galaxy GitOps need (likely gxy-backoffice provisioning)                       |
| Zot      | parked per ADR-005 amend 2026-05-04       | First containerized constellation on gxy-triangulum + RUN-residency design re-check |
| Atlantis | parked per spike-plan §"What NEVER moves" | OpenTofu modules exist (ADR-002 amend follow-up)                                    |

If a future operator forgets and deploys one anyway:

```bash
# Roll back:
helm uninstall -n argocd argocd      # or zot
kubectl delete namespace argocd      # or zot
# Restore parked state.
```

## §F — DNS + access

### F.1 Get node public IPs

```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="ExternalIP")].address}{"\n"}{end}'

# If no ExternalIP populated, fall back to:
doctl compute droplet list --tag-name gxy-management-k3s --format Name,PublicIPv4
```

### F.2 Cloudflare DNS records

| Hostname                    | Record      | Proxy | SSL         | Notes                                                              |
| --------------------------- | ----------- | ----- | ----------- | ------------------------------------------------------------------ |
| `windmill.freecodecamp.net` | A × 3 nodes | ON    | Full Strict | Origin cert from `infra-secrets/global/tls/freecodecamp-net.*.enc` |
| `uploads.freecode.camp`     | A × 3 nodes | ON    | Flexible    | No origin cert — CF→origin HTTP                                    |
| `argocd.freecodecamp.net`   | (parked)    | —     | —           | Phantom DNS deletion queued — do not recreate                      |
| `zot.freecodecamp.net`      | (parked)    | —     | —           | Same                                                               |

### F.3 Auth gates

- **Windmill** — native auth (no CF Access). D22 OAuth-org-gate canonical (sprint 2026-04-21 amendment).
- **artemis** — programmatic API; auth is GH Bearer + JWT (no CF Access — that would block CLI clients).

### F.4 Smoke

```bash
curl -sI https://windmill.freecodecamp.net
# 200

curl -fsS https://uploads.freecode.camp/healthz
# {"ok":true}
```

## §G — Backups

| Data              | Method                                             | Schedule                    | Storage                                                           | Restore time         |
| ----------------- | -------------------------------------------------- | --------------------------- | ----------------------------------------------------------------- | -------------------- |
| etcd              | k3s built-in S3 snapshots                          | Every 6h, 20 retained       | `s3://net-freecodecamp-universe-backups/etcd/gxy-management/`     | Minutes (k3s native) |
| Windmill PG       | CronJob `pg_dumpall` → S3                          | Daily 02:00 UTC, 7 retained | `s3://net-freecodecamp-universe-backups/windmill/gxy-management/` | Minutes (pg_restore) |
| Valkey (registry) | **Deferred — post-GA** (see §C.5)                  | not yet running             | future: `r2://universe-static-apps-01/_meta/registry/<date>.rdb`  | post-GA scope        |
| ArgoCD            | not backed up — state in git                       | n/a                         | n/a                                                               | re-deploy from git   |
| Zot (parked)      | not backed up                                      | n/a                         | DO Spaces (when reactivated)                                      | n/a                  |
| Helm releases     | not backed up — chart values are source of truth   | n/a                         | infra repo                                                        | `just helm-upgrade`  |
| Secrets           | not backed up — `infra-secrets` repo IS the backup | n/a                         | infra-secrets repo                                                | `just deploy`        |

### G.1 Ad-hoc Windmill backup (before maintenance)

```bash
cd ~/DEV/fCC/infra
just windmill-backup gxy-management
```

Saves to `k3s/gxy-management/.backups/`. Run before any helm-upgrade,
teardown, or PG change.

### G.2 Restore Windmill PG

See B.3 above.

### G.3 Restore Valkey from R2 RDB mirror — DEFERRED (post-GA)

> The R2 mirror CronJob is not yet running (see §C.5). Until it
> ships, the only recovery path on Valkey data loss is the AOF on
> the local-path PVC. Worst case (PVC loss + no nightly mirror):
> rerun `apps/valkey/scripts/import-sites.sh` to re-seed the 11-site
> registry, then accept that any sites registered after the seed
> import are lost and must be re-`universe sites register`'d by
> staff.
>
> When G.3 reactivates, the recipe will read from
> `r2://universe-static-apps-01/_meta/registry/<date>.rdb`, copy
> into the Valkey pod under `-n valkey`, and decrypt the password
> from `secretEnv.VALKEY_PASSWORD` in the sops envelope (NOT
> `auth.password` — schema in C.1).

### G.4 Restore etcd from S3

```bash
# List available snapshots:
k3s etcd-snapshot list --s3 \
  --s3-bucket net-freecodecamp-universe-backups \
  --s3-folder etcd/gxy-management \
  --s3-endpoint fra1.digitaloceanspaces.com \
  --s3-region fra1

# Restore (run on the --cluster-init node only):
k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=s3://net-freecodecamp-universe-backups/etcd/gxy-management/SNAPSHOT_NAME
```

Then rejoin the other nodes. See
<https://docs.k3s.io/datastore/backup-restore>.

## §H — Windmill IaC (CLI sync, separate repo)

Windmill CE has no Git Sync. Scripts/flows/apps managed via `wmill`
CLI in dedicated repo `~/DEV/fCC-U/windmill`. Critical warnings:

- **NEVER `wmill sync push` from the wrong directory.** "No wmill.yaml
  found" = wrong dir; without config, push sees empty local state and
  deletes everything remote.
- **ALWAYS decrypt resources before push, re-encrypt after.** Pushing
  encrypted ciphertext stores `ENC[AES256_GCM,...]` as literal values.
- **ALWAYS use `--dry-run` first.** Verify changes show `+`/`~`, not
  unexpected `-`.

```bash
cd ~/DEV/fCC-U/windmill

# Push local → remote
sops -d -i f/integration/apollo-11_github_app.resource.yaml
wmill sync push --dry-run                           # verify creates/updates
wmill sync push --yes
sops -e -i f/integration/apollo-11_github_app.resource.yaml

# Pull remote → local
wmill sync pull
sops -e -i f/integration/apollo-11_github_app.resource.yaml

# Regenerate metadata after code changes
wmill generate-metadata
```

Branch strategy: `main` config only; `gxy-management` carries scripts/flows/apps for the gxy-management workspace.

## §I — Smoke (post-bring-up)

Hits the cassiopeia ↔ management seam end-to-end:

```bash
cd ~/DEV/fCC/infra

# Cassiopeia caddy reachable; assumes gxy-cassiopeia chapter green.
curl -fsSI https://test.freecode.camp/ | head -5

# artemis healthy + sites enumeration.
just artemis-postdeploy-check

# Static apps deploy E2E (deploys to test, curls cassiopeia, rolls back).
just phase5-smoke
```

Acceptance gates (this chapter contributes G5/G6/G9/G10/G11 from
RFC §E):

- **G5** Valkey running with persistence + AUTH (§C.2).
- **G6** artemis with `REGISTRY_BACKEND=valkey`, no `--set-file` (§D.2).
- **G9** Registry survives `kubectl rollout restart deploy/artemis` —
  pod restarts; sites enum unchanged.
- **G10** Registry survives `kubectl delete pod -l app=valkey` — PVC
  reattach + AOF replay; sites enum unchanged.
- **G11** Nightly RDB lands in R2 (§C.4 manual trigger validates).

## §J — Teardown

Destructive. Run an ad-hoc Windmill backup (G.1) and a Valkey
manual-trigger RDB upload (§C.4) before teardown.

### Cluster only (preserves VMs)

```bash
cd ~/DEV/fCC/infra
just play k3s--teardown gxy_management_k3s
```

### Full teardown (VMs too)

```bash
cd ~/DEV/fCC/infra
just play k3s--teardown gxy_management_k3s
doctl compute droplet delete \
  gxy-vm-management-k3s-1 gxy-vm-management-k3s-2 gxy-vm-management-k3s-3 \
  --force
```

VPC, firewall, DO Spaces, R2 buckets persist (shared infra — see
`UNIVERSE.md §3`).
