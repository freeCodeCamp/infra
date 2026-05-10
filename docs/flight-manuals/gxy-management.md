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
single-instance Valkey alongside artemis. AOF + RDB on PVC. Nightly
RDB → R2.

### C.1 Helm install

```bash
cd ~/DEV/fCC/infra

helm get values -n artemis valkey >/dev/null 2>&1 \
  && echo "✓ valkey release present" \
  || just helm-upgrade gxy-management valkey

just deploy gxy-management valkey
```

The valkey chart lives at `k3s/gxy-management/apps/valkey/charts/valkey/`.
Production overlay at `apps/valkey/values.production.yaml` pins the
image SHA + sets persistence + NetworkPolicy. AUTH password from sops
overlay `infra-secrets/k3s/gxy-management/valkey.values.yaml.enc`.

> **Bring-up gate:** §C runs **before** §D — artemis depends on
> valkey reachable on `valkey.artemis.svc.cluster.local:6379`.

### C.2 Verify

```bash
cd ~/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl -n artemis get pods,svc,pvc -l app=valkey
# valkey-0 Running (StatefulSet); svc valkey ClusterIP; PVC bound

# Auth + ping
PASS=$(sops decrypt --extract '["auth"]["password"]' \
  ../../infra-secrets/k3s/gxy-management/valkey.values.yaml.enc)
kubectl -n artemis exec sts/valkey -- valkey-cli -a "$PASS" PING
# → PONG

# Persistence config
kubectl -n artemis exec sts/valkey -- valkey-cli -a "$PASS" CONFIG GET appendonly
# → 1) "appendonly"  2) "yes"
```

### C.3 Sites import (one-shot, migration step from `sites.yaml`)

Skip if `SMEMBERS sites:all` is already non-empty.

```bash
cd ~/DEV/fCC/infra
just artemis-registry-import       # one-shot Job: reads sites.yaml from artemis chart values, writes Valkey
```

(`just artemis-registry-import` is a follow-up sprint deliverable in
the artemis repo — encode here as the operator anchor; recipe exits 0
when valkey hash count matches `sites.yaml` entry count.)

### C.4 Nightly RDB → R2 mirror

The valkey chart ships a CronJob (`apps/valkey/manifests/base/rdb-backup.yaml`)
that runs daily 03:00 UTC, execs `valkey-cli BGSAVE`, uploads
`/data/dump.rdb` → `r2://universe-static-apps-01/_meta/registry/<date>.rdb`.
30-day R2 lifecycle.

```bash
kubectl -n artemis get cronjob valkey-rdb-backup
# valkey-rdb-backup   0 3 * * *   ...

# Manual trigger to validate the path before waiting overnight:
kubectl -n artemis create job valkey-rdb-test-$(date +%s) --from=cronjob/valkey-rdb-backup
```

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

| Data              | Method                                             | Schedule                             | Storage                                                           | Restore time                         |
| ----------------- | -------------------------------------------------- | ------------------------------------ | ----------------------------------------------------------------- | ------------------------------------ |
| etcd              | k3s built-in S3 snapshots                          | Every 6h, 20 retained                | `s3://net-freecodecamp-universe-backups/etcd/gxy-management/`     | Minutes (k3s native)                 |
| Windmill PG       | CronJob `pg_dumpall` → S3                          | Daily 02:00 UTC, 7 retained          | `s3://net-freecodecamp-universe-backups/windmill/gxy-management/` | Minutes (pg_restore)                 |
| Valkey (registry) | CronJob `valkey-cli BGSAVE` → R2                   | Daily 03:00 UTC, 30-day R2 lifecycle | `r2://universe-static-apps-01/_meta/registry/<date>.rdb`          | Minutes (valkey-cli `--rdb` restore) |
| ArgoCD            | not backed up — state in git                       | n/a                                  | n/a                                                               | re-deploy from git                   |
| Zot (parked)      | not backed up                                      | n/a                                  | DO Spaces (when reactivated)                                      | n/a                                  |
| Helm releases     | not backed up — chart values are source of truth   | n/a                                  | infra repo                                                        | `just helm-upgrade`                  |
| Secrets           | not backed up — `infra-secrets` repo IS the backup | n/a                                  | infra-secrets repo                                                | `just deploy`                        |

### G.1 Ad-hoc Windmill backup (before maintenance)

```bash
cd ~/DEV/fCC/infra
just windmill-backup gxy-management
```

Saves to `k3s/gxy-management/.backups/`. Run before any helm-upgrade,
teardown, or PG change.

### G.2 Restore Windmill PG

See B.3 above.

### G.3 Restore Valkey from R2 RDB mirror

```bash
cd ~/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Get latest mirror.
DATE=$(aws --endpoint-url "$R2_ENDPOINT" s3 ls s3://universe-static-apps-01/_meta/registry/ \
  | awk '{print $4}' | sort -r | head -1)

aws --endpoint-url "$R2_ENDPOINT" s3 cp \
  "s3://universe-static-apps-01/_meta/registry/$DATE" /tmp/dump.rdb

# Quiesce artemis (optional; or accept brief 5xxs while valkey is restoring).
kubectl scale deploy -n artemis artemis --replicas=0

# Restore: copy file into the valkey pod and trigger a FLUSHALL+restore.
PASS=$(sops decrypt --extract '["auth"]["password"]' \
  ../../infra-secrets/k3s/gxy-management/valkey.values.yaml.enc)

kubectl cp /tmp/dump.rdb artemis/valkey-0:/data/dump.rdb
kubectl -n artemis exec sts/valkey -- valkey-cli -a "$PASS" SHUTDOWN NOSAVE
# k8s restarts the pod; on boot Valkey loads dump.rdb.
kubectl wait --for=condition=Ready pod/valkey-0 -n artemis --timeout=2m

# Bring artemis back.
kubectl scale deploy -n artemis artemis --replicas=3
```

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
