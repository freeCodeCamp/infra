# RFC — gxy-cassiopeia GA Hardening

**Status:** Proposed (universe-master-audit, 2026-05-10) · Owner: infra
**Anchors:** ADR-007 (DX), ADR-009 (networking), ADR-010 (secrets), ADR-011 (security), ADR-016 (deploy proxy)
**Supersedes:** archived `rfc-gxy-cassiopeia.md` (2026-04-30), archived `task-gxy-cassiopeia.md` (2026-04-30); also retires the still-in-tree `rfc-gxy-cassiopeia-caddyfile-poc.md` (POC, surfaced for retirement 2026-04-30).

## Context

gxy-cassiopeia is the static-apps galaxy. caddy-s3 fronts R2 at
`*.freecode.camp`. The deploy plane is artemis on gxy-management
(`uploads.freecode.camp`). The caddy + R2 read-side is already live and
SHA-pinned (see probes 02, 04). The deploy-side is live but the
**static-apps registry** (which maps `<site-slug>` → authorized GH
teams) is encoded as `artemis/config/sites.yaml` and embedded into the
Helm chart at deploy-time via `--set-file` — this couples every
staff-onboarding round-trip to operator + PR + helm. Cassiopeia
cannot reach GA without breaking that coupling.

This RFC is the GA hardening pass. Sections A-D enumerate the work;
sections E-F define the gates and the few open questions that need
operator input before the cassiopeia chapter of the master flight-manual
is authored.

## What's in / out

| In scope (this RFC)                                                      | Out of scope (parked)                                                                       |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| caddy-s3 + R2 read-plane reconciliation against ADR-007/009/016          | gxy-backoffice / gxy-triangulum / Hetzner pivot (parked)                                    |
| Static-apps registry decouple from operator (the C3 main blocker)        | ArgoCD-driven sync of artemis + valkey manifests (gates on ADR-005 reactivation)            |
| Artemis service trim post-registry-decouple                              | cosign + Kyverno + Grype/Trivy supply-chain pipeline reactivation (Woodpecker retired)      |
| Ingress + DNS + cert posture for `*.freecode.camp` (Cloudflare Flexible) | Origin allow-list automation (`gxy-static-k7d.14`, parked)                                  |
| Acceptance gates + smoke for cassiopeia GA                               | R2 lifecycle GC / cleanup-cron for orphan deploy bytes (parked, deferred to post-GA sprint) |
| Operator-runnable flight-manual chapter (T4 deliverable, separate file)  | universe-cli `static deploy` UX changes (out of repo)                                       |

## Proposed end state (one picture)

```
                staff laptop                                                operator
                    │                                                            │
                    │ universe site register <slug> --teams=staff                │
                    │ universe static deploy <slug>                              │
                    ▼                                                            ▼
        ┌─────────────────────────────────────────────────┐         ┌─────────────────────┐
        │  artemis  (gxy-management/uploads.freecode.camp)│         │  one-time bootstrap │
        │  ┌───────────────────────────────────────────┐  │         │  just helm-upgrade  │
        │  │  POST /api/site/register                  │  │         │   gxy-management    │
        │  │  POST /api/deploy/{init|upload|finalize}  │  │         │   artemis           │
        │  │  POST /api/site/<site>/promote            │  │         │  (no --set-file)    │
        │  │  POST /api/site/<site>/rollback           │  │         └─────────────────────┘
        │  └───┬───────────────────────────────────────┘  │
        │      │  authn: GH OAuth Bearer  authz: GH team   │
        │      │     membership probe (cached 5m)          │
        │      ▼                                            │
        │  ┌─────────────────────────────────┐  resp/3 +   │
        │  │  registry-store (kv, primary)   │◀ pub-sub ───┤
        │  │  Valkey 1× alongside artemis    │             │
        │  │  in gxy-management.artemis ns   │             │
        │  │  AOF + RDB on PVC               │             │
        │  └────────────┬────────────────────┘             │
        │               │  artemis nightly RDB dump        │
        │               ▼                                  │
        │  ┌─────────────────────────────────┐             │
        │  │  registry-mirror (kv, DR-only)  │             │
        │  │  R2: universe-static-apps-01/   │             │
        │  │  _meta/registry/<date>.rdb      │             │
        │  └─────────────────────────────────┘             │
        └────────────────┬────────────────────────────────┘
                         │ S3 admin token (sole writer)
                         ▼
                  R2: universe-static-apps-01
                  └── <site>/{deploys,preview,production}
                         ▲
                         │ R2 read-only token (sole reader)
                         │
        ┌──────────────────────────────────┐
        │  caddy-s3  (gxy-cassiopeia)       │
        │  HTTPRoute *.freecode.camp        │
        │  in-tree caddy.fs.r2 alias module │
        └──────────────────────────────────┘
                         ▲
                  Cloudflare (Flexible SSL)
                         ▲
                       public
```

## Section A — caddy-s3 + R2 read plane (S2)

State today (probe 02):

- `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/` — Helm chart with Gateway API
  HTTPRoute + Gateway + Deployment + ConfigMap + Secret + NetworkPolicy.
- Chart `values.yaml` defaults SHA-pinned to `dev`; production overlay at
  `values.production.yaml` pins `sha-712c6e3@sha256:e024…`.
- R2 bucket `universe-static-apps-01`, prefix-scoped per site.
- Caddy reads `<site>.freecode.camp/<env>` aliases via in-tree `caddy.fs.r2`
  module (D32 absorbed `sagikazarmark/caddy-fs-s3` after upstream stalled).
- TLS posture: CF Flexible SSL (CF-edge HTTPS, origin HTTP). No origin
  cert at the k8s layer for this zone.

Gaps to close at GA:

| Gap                                                                    | Action                                                                                                                                                                                                         |
| ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ADR-016 alias-key format echoes hard-coded across chart + caddy module | Document the contract in flight-manual §B; add chart values comment cross-linking artemis chart `ALIAS_*_KEY_FORMAT`.                                                                                          |
| R2 read-only token rotation cadence                                    | Already runbooked at `docs/runbooks/05-r2-keys-rotation.md`. Ensure flight-manual links it from §B post-deploy.                                                                                                |
| caddy chart sidecar `rclone-sync`                                      | Existing manual line 99 mentions sidecar in pod (`2/2`). With D32 in-tree module the sidecar may be redundant — verify in T4 by reading `templates/deployment.yaml`; if sidecar is gone, drop the verify line. |
| 503 fallback to previous deploy                                        | Already runbookable (`universe static promote --to <id>`). Encode in flight-manual §E smoke + "503 troubleshooting".                                                                                           |

No chart edits are mandated by this RFC — the chart is GA-shaped today.
The cassiopeia chapter encodes the operator-runnable verifier.

## Section B — Static-apps registry: KV substrate matrix and decision (S1)

The operator-coupling problem (C3) is the biggest blocker. This
section lays out candidates, re-scores them with **vendor-neutrality
weighted heavier** (per the standing platform tenet), and records
the user-confirmed decision: **Valkey single-instance alongside
artemis on gxy-management** (2026-05-10).

A first-pass recommendation defaulted to `ConfigMap` on a "minimal
diff" axis. User pushback corrected the priority order: vendor-neutral
substrate first, "+1 small pillar" acceptable when the substrate is
the right shape for the job. Decision rationale + dismissed
alternatives recorded below for future readers.

### Requirements

R1. **Operator-free site registration** — a staff member (or
universe-cli on their behalf) registers a new site without operator
PR + helm + local checkout. Steady-state path: API call → registry
mutation → live within <60s.

R2. **Authz preserved** — every register/deploy still authenticates
via GH Bearer + authorizes via GH team membership (per ADR-016). The
registry is the **source of truth** for `<site> → [team-slugs]`.

R3. **Hot-reload in artemis** — the running artemis pod picks up
registry mutations without an operator-driven helm-upgrade.

R4. **DR posture** — registry survives a cluster wipe. Restoration
should not require operator-manual data entry.

R5. **Vendor-neutral within practical limits** — Cloudflare (R2,
edge, DNS) is already foundational and outside this audit's
substitution scope; new vendor lock-ins are weighed against
self-hosted alternatives. Self-hosted preferred when the
implementation cost is comparable.

R6. **Sized for ~100 sites near-term, 10K long-term** — the registry
is platform-team-curated; explosive growth not expected, but the
substrate must not cap out at chart-values size.

### Candidate matrix (re-scored 2026-05-10)

Vendor-neutrality weighted heavier than initial pass; "+1 small pillar"
no longer auto-disqualifies a candidate.

| Candidate                                 | License            | Vendor-neutral | Op-free path?                        | Hot-reload (artemis)    | Multi-writer safe (3 replicas)    | DR posture                          | New deps                                     | Verdict                                |
| ----------------------------------------- | ------------------ | -------------- | ------------------------------------ | ----------------------- | --------------------------------- | ----------------------------------- | -------------------------------------------- | -------------------------------------- |
| **A. Valkey 1× alongside artemis**        | BSD-3 (LF fork)    | ✅             | Yes — API → `HSET` + `PUBLISH`       | pub-sub (instant)       | ✅ (single Valkey serializes)     | AOF + RDB + nightly RDB → R2 mirror | 1 small pillar (~50 MiB, 1 PVC, 1 Service)   | **Selected (2026-05-10)**              |
| B. In-cluster ConfigMap (artemis-managed) | (k8s native)       | partial (k8s)  | Yes — artemis SA patches own CM      | fsnotify (~1 s)         | partial (no CAS; last-write-wins) | etcd snapshots + nightly R2 mirror  | None                                         | Fallback if "no new pillars"           |
| C. Postgres single 1× on gxy-management   | PostgreSQL         | ✅             | Yes — artemis writes SQL             | LISTEN/NOTIFY (instant) | ✅                                | PITR (S3 WAL archive)               | 1 medium pillar (~150 MiB, 1 PVC, 1 Service) | Future-proof; oversized for ~100 sites |
| D. SQLite + Litestream (embedded)         | PD + Apache 2.0    | ✅             | Yes — artemis writes file            | local file (instant)    | ❌ (single-writer; arch shift)    | Litestream → S3 continuous          | Embedded; artemis becomes stateful           | Architecturally invasive               |
| E. NATS JetStream KV                      | Apache 2.0         | ✅             | Yes — artemis writes via NATS client | watch (instant)         | ✅                                | NATS file stream                    | 1 small-medium pillar; less familiar         | Viable; less ecosystem fit             |
| F. R2 JSON object                         | (CF, already used) | ❌ (CF lock)   | Yes — artemis writes R2 JSON         | polling (~30 s)         | partial (ETag CAS works)          | R2 versioning + multi-region        | None                                         | Rejected — control-plane CF lock       |
| G. Cloudflare Workers KV                  | (CF lock)          | ❌             | Yes — artemis writes via CF API      | eventual (~60 s)        | partial                           | CF edge replicas                    | New CF KV namespace + token                  | Rejected — vendor lock                 |
| H. Windmill resource                      | (self-hosted)      | partial        | Yes — Apollo flow writes resource    | polling                 | ✅                                | Windmill PG (CNPG path owed)        | Couples artemis read-path to Windmill        | Rejected — read-path coupling          |
| I. Postgres on CNPG (gxy-launchbase)      | PostgreSQL         | ✅             | Yes — artemis writes SQL             | LISTEN/NOTIFY           | ✅                                | CNPG PITR (already speced)          | Cross-galaxy network coupling                | Rejected — cross-galaxy hop            |
| J. etcd direct                            | Apache 2.0         | ✅             | No (anti-pattern to share k3s etcd)  | n/a                     | n/a                               | etcd snapshots                      | None (but anti-pattern)                      | Rejected                               |

### Decision: **A. Valkey single-instance alongside artemis** (locked 2026-05-10)

Rationale:

1. **Vendor-neutral.** Valkey is the BSD-3 LF-stewarded fork of Redis
   (post-Redis-Inc.-relicensing 2024). Portable to any k8s, VM, or
   bare-metal substrate. No CF lock for control-plane state, no
   "k8s-resource-as-database" hack.
2. **Right tool for the shape.** Native KV: `HSET`/`HGETALL` for
   per-site rows, `SADD` for the all-sites set, `WATCH`/`MULTI` for
   compare-and-set, `PUBLISH` for hot-reload notification, `EXPIRE`
   for ephemeral cache rows (e.g. GH membership cache pulled out of
   in-process memory once we want cross-pod cache coherence).
3. **Multi-writer safe.** All 3 artemis replicas write through one
   Valkey — Valkey serializes commands. ConfigMap has no
   compare-and-set; concurrent writes race.
4. **Operator-free steady state.** Bootstrap = `just deploy gxy-management valkey`
   followed by `just deploy gxy-management artemis` once. Steady
   state: staff (or universe-cli on staff's behalf) calls `POST
/api/site/register` against artemis; artemis writes Valkey;
   `PUBLISH registry.changed <site>` fans the invalidation. No
   operator, no PR, no helm-upgrade.
5. **Right-sized footprint.** Single pod (~50 MiB RAM idle), single
   PVC (~1 GiB sufficient for ~10K sites of the schema below), one
   Service `valkey.artemis.svc.cluster.local:6379`. NetworkPolicy
   allows only `app=artemis` pods to connect.
6. **DR posture.** AOF (appendfsync everysec) + RDB snapshot every 6
   h on PVC. Nightly RDB dump → `r2://universe-static-apps-01/_meta/registry/<date>.rdb`.
   On a cluster wipe: reattach PVC if it survived (`pv` reclaim
   policy `Retain`); otherwise restore latest RDB from R2 via
   `valkey-cli --rdb` on a fresh pod, then bring artemis back.
7. **HA bolt-on.** Async replica or Sentinel is a chart-flag away
   when scale demands. Don't pay the cost now — single-instance is
   sufficient for ~100 → ~10K sites with the read pattern below.

Why not B (ConfigMap):

- ConfigMap has no compare-and-set; multi-replica artemis writes
  race. Last-write-wins under concurrent registrations.
- Built for static config, not mutable runtime state. fsnotify
  reload has a known race (file-renamed-into-place vs partial mount
  refresh) and 1 MiB cap eventually bites.
- Recorded as fallback if "no new pillars" hardens into a constraint.

Why not F (R2 JSON), G (CF KV), H (Windmill), I (CNPG cross-galaxy),
J (etcd direct): vendor lock or cross-coupling — see matrix verdict
column.

### Deployment shape

New helm release `valkey` in namespace `artemis` on `gxy-management`:

```
k3s/gxy-management/apps/valkey/
├── charts/valkey/                            # local copy of the upstream chart
│   ├── Chart.yaml
│   ├── values.yaml                           # dev defaults
│   └── templates/                             # Service, StatefulSet, PVC, NetworkPolicy
└── values.production.yaml                    # SHA pin, persistence, NetworkPolicy
```

Production overlay highlights (non-secret; `auth` password lives in sops):

```yaml
architecture: standalone
auth:
  enabled: true
  # password populated from infra-secrets/k3s/gxy-management/valkey.values.yaml.enc
persistence:
  enabled: true
  size: 1Gi
  storageClass: local-path # k3s default
appendonly: yes
appendfsync: everysec
save: "3600 1 300 100" # RDB snapshot triggers
networkPolicy:
  enabled: true
  ingressNSPodLabels:
    app: artemis # only artemis pods may reach 6379
resources:
  requests: { cpu: 50m, memory: 64Mi }
  limits: { cpu: 500m, memory: 256Mi }
```

Image: track `valkey/valkey:<minor>` (e.g. `8.0`) tag-and-digest
pinned per ADR-011. SHA pin lands in `values.production.yaml` next to
the existing artemis pattern.

Backup: a CronJob (`apps/valkey/manifests/base/rdb-backup.yaml`) runs
daily 03:00 UTC, execs `valkey-cli BGSAVE` + uploads
`/data/dump.rdb` → R2. R2 lifecycle: 30-day retention. Same R2 admin
token already used by artemis (no new credential).

### Migration shape (no operator marathon)

| Step                                                                                                                           | Who                             | Effect                                                                     |
| ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------- | -------------------------------------------------------------------------- |
| 1. Mint `infra-secrets/k3s/gxy-management/valkey.values.yaml.enc` with `auth.password`.                                        | operator                        | one-time secret seed                                                       |
| 2. `cd k3s/gxy-management && just deploy valkey`                                                                               | operator                        | helm install valkey + manifests; PVC bound; pod Ready                      |
| 3. Bump artemis image to a build that supports `REGISTRY_BACKEND=valkey` (defaults: `REGISTRY_BACKEND=sites_yaml`).            | follow-up sprint (artemis repo) | artemis with both backends compiled in                                     |
| 4. Run one-shot `just artemis-registry-import sites.yaml` (in-cluster Job): reads `/etc/artemis/sites.yaml`, writes to Valkey. | operator                        | content migrated; `HLEN sites` matches source                              |
| 5. `just helm-upgrade gxy-management artemis --set env.REGISTRY_BACKEND=valkey` (no `--set-file`).                             | operator                        | artemis switches read path to Valkey; ConfigMap mount retained as fallback |
| 6. After 24h soak: drop `--set-file` from chart values + remove `SITES_YAML_PATH` env + retire `sites.yaml` from artemis repo. | follow-up sprint (artemis repo) | artemis chart no longer references the file                                |

Step 3 (and the tail of step 6) are **artemis-side code work** —
follow-up sprint scope, not this audit. The flight-manual chapter
encodes the **end state** (steps 4-5 only as the operator path);
steps 1-2 belong in the cassiopeia or management chapter as one-time
bootstrap.

### Schema (Valkey)

Per-site row as a hash; index set for enumeration:

```
HSET site:<slug>  teams      <json-array>
                  created_at <iso-8601>
                  updated_at <iso-8601>
                  created_by <gh-login>

SADD sites:all   <slug>
```

Read path:

```
HGETALL site:<slug>           # → teams + metadata for authz
SMEMBERS sites:all            # → enumerate (admin / list endpoint)
```

Write path (atomic via MULTI/EXEC):

```
MULTI
HSET site:<slug>  teams ...  created_at ...  ...
SADD sites:all   <slug>
PUBLISH registry.changed <slug>
EXEC
```

Hot-reload: artemis subscribes to `registry.changed`; on event,
invalidates the in-process site cache row. New reads pull from
Valkey on cache miss. Pub-sub is fire-and-forget — artemis also
caches with a short TTL fallback (e.g. 60 s) so a missed message
self-heals.

JSON over YAML for the `teams` field (encoder symmetry with API
responses).

### CLI surface (universe-cli, ADR-007 reuse)

| Command                                         | Authz                       | Effect                                                                                              |
| ----------------------------------------------- | --------------------------- | --------------------------------------------------------------------------------------------------- |
| `universe site register <slug> --teams=t1[,t2]` | caller in `staff` team      | `POST /api/site/register`; artemis runs the MULTI/EXEC + PUBLISH                                    |
| `universe site list`                            | any GH user                 | `GET /api/sites` (read-only; reads `SMEMBERS sites:all` then `HGETALL` each)                        |
| `universe site update-teams <slug> --teams=…`   | caller in `staff` team      | `PATCH /api/site/{slug}`; `HSET teams …` + `PUBLISH registry.changed`                               |
| `universe site delete <slug>`                   | caller in `staff` + confirm | `DELETE /api/site/{slug}`; `DEL site:<slug>` + `SREM sites:all <slug>` + `PUBLISH registry.changed` |

The `static deploy / promote / rollback` path is unchanged from
ADR-016 except authz now consults Valkey instead of the
helm-embedded ConfigMap.

## Section C — Artemis service trim (S2)

Once the registry leaves `--set-file`, the chart simplifies:

| Concern                              | Before                                                 | After                                                                                                     |
| ------------------------------------ | ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| `--set-file sites=...`               | required at every helm-upgrade                         | **dropped**                                                                                               |
| Operator local artemis checkout      | required                                               | **not required**; checkout is a developer convenience only                                                |
| `sites: ""` chart values placeholder | string injection point                                 | **removed**                                                                                               |
| sites.yaml ConfigMap mount           | `/etc/artemis/sites.yaml` from helm-rendered ConfigMap | **removed** (one-release backward-compat mount window if needed for migration step 5)                     |
| `SITES_YAML_PATH` env                | mount path                                             | **removed** (replaced by Valkey conn)                                                                     |
| `VALKEY_ADDR` env                    | n/a                                                    | **added**: `valkey.artemis.svc.cluster.local:6379` (chart default)                                        |
| `VALKEY_PASSWORD` (secret env)       | n/a                                                    | **added** from sops overlay `infra-secrets/k3s/gxy-management/artemis.values.yaml.enc`                    |
| `REGISTRY_BACKEND` env               | n/a                                                    | **added**: `valkey` (default once migration step 5 lands; `sites_yaml` for the one-release backward path) |
| Artemis SA                           | none beyond default                                    | unchanged — Valkey is reached via TCP+AUTH, not k8s API; no RBAC growth                                   |
| NetworkPolicy                        | artemis ingress allow CF→Traefik                       | **add egress** allow to `valkey.artemis.svc:6379`; valkey chart owns the matching ingress rule            |

Other artemis hardening items (post-registry):

- **Schema slim** — ADR-016 hints at moving from per-site nested
  team-list to flat allowlist + env `AUTHORIZED_TEAMS`. The KV
  decision in §B keeps the per-site nested form for now (more flexible);
  flat-allowlist parked.
- **`POST /api/site/register` rate limit** — reuse the per-source-IP
  Traefik middleware already on the chart. No new infra.
- **Audit log** — emit structured log line per registry mutation
  (request user, action, target site). Already have stdout logs going
  through Vector → ClickHouse pattern (when o11y reactivates per
  ADR-015); for now, kubectl logs is fine.

## Section D — Ingress + DNS + cert (S1)

Cassiopeia serves `*.freecode.camp` from R2 via caddy-s3. The user's
locked scope item is "wildcard `*.freecode.camp` cert + DNS path
formalized".

### TLS posture per zone (anchors for §1 of UNIVERSE.md)

| Zone               | Mode        | Origin cert                       | Used by                                                                        |
| ------------------ | ----------- | --------------------------------- | ------------------------------------------------------------------------------ |
| `freecode.camp`    | Flexible    | none (CF-edge HTTPS, origin HTTP) | caddy on cassiopeia · artemis on management                                    |
| `freecodecamp.net` | Full Strict | `*.freecodecamp.net` wildcard     | windmill / argocd / zot (when reactivated) on management; future galaxy planes |

The zones intentionally use different posture: `freecode.camp` is
public static-app surface (high cardinality, wildcard origin cert
infeasible across many subdomains, edge HTTPS sufficient);
`freecodecamp.net` is internal-tools surface (small fixed set, origin
cert worth carrying).

### DNS surface for `*.freecode.camp`

Two flavors:

1. **`<site>.freecode.camp`** (production). Wildcard A record to all
   3 cassiopeia node public IPs, CF orange cloud ON. Per-site DNS
   addition is **NOT** required — wildcard catches everything.
2. **`<site>--preview.freecode.camp`** (preview). Same wildcard
   covers — the `--preview` is part of the `<sitePrefix>` from
   caddy's perspective. ADR-009 already specifies double-dash to
   avoid wildcard-cert scope creep.

Per `gxy-cassiopeia.md` Phase 23 today: 3 A records per production
domain, proxy ON, SSL Flexible. No per-site DNS edit required after
wildcard is in place.

### Cert manager / DNS-01 issuer

Not deployed in tree (per probe 02). Decision today: **don't deploy**.

- The `freecode.camp` zone is Flexible SSL. CF-edge cert covers public traffic.
- Origin is HTTP — no origin cert required.
- A DNS-01 issuer would add complexity for the `freecodecamp.net`
  zone (wildcard origin cert) but that's an existing operator-rotated
  cert in `infra-secrets/global/tls/freecodecamp-net.{crt,key}.enc`
  — also no automation needed.

cert-manager / DNS-01 is **deferred** behind a future "we have many
zones with origin certs" trigger. Recorded in TODO-park.

### Origin allow-list (gxy-static-k7d.14, parked)

Today: DO Cloud Firewall accepts 80/443 from 0.0.0.0/0. Only CF WAF
gates origin hits. The "only allow CF edge IPs" cron + manifest is
parked. Document the gap in flight-manual §D and link to TODO-park.
Not GA-blocking — origin reveals galaxy IPs but everything serves
through CF.

## Section E — Acceptance gates + smoke

Cassiopeia GA = all of the following pass on a fresh
back-to-back idempotent rerun of the cassiopeia flight-manual chapter:

| Gate | Description                                                                                        | Command anchor                                                                                                                                        |
| ---- | -------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| G1   | k3s + Cilium green                                                                                 | `kubectl get nodes -o wide` + `cilium-health status`                                                                                                  |
| G2   | caddy-s3 chart deployed and pods 3/3 Running with Gateway Programmed                               | `kubectl get pods,gateway,httproute -n caddy`                                                                                                         |
| G3   | R2 bucket reachable from caddy with read-only key                                                  | `just r2-bucket-verify universe-static-apps-01`                                                                                                       |
| G4   | DNS resolves `*.freecode.camp` to 3 cassiopeia node IPs                                            | `dig +short test.freecode.camp` matches `doctl droplet list` output                                                                                   |
| G5   | Valkey running in artemis ns with persistence + AUTH                                               | `kubectl -n artemis get pods,svc,pvc -l app=valkey`; `valkey-cli AUTH … && valkey-cli PING` returns `PONG`                                            |
| G6   | artemis on gxy-management with `REGISTRY_BACKEND=valkey` (no `--set-file`)                         | `helm get values -n artemis artemis` shows no `sites:` key; `kubectl -n artemis exec deploy/artemis -- env \| grep REGISTRY_BACKEND` reports `valkey` |
| G7   | `universe site register test --teams=staff` succeeds without operator action                       | CLI exits 0; `GET /api/sites` includes `test`; `valkey-cli SMEMBERS sites:all` includes `test`                                                        |
| G8   | E2E deploy → preview → promote → production through artemis                                        | `just phase5-smoke` (existing artemis post-deploy smoke harness)                                                                                      |
| G9   | Registry survives `kubectl rollout restart deployment -n artemis artemis`                          | `GET /api/sites` returns same set; Valkey pod untouched (different release/sts)                                                                       |
| G10  | Registry survives Valkey pod restart (PVC reattach)                                                | `kubectl -n artemis delete pod -l app=valkey`; new pod replays AOF; `GET /api/sites` matches                                                          |
| G11  | Nightly RDB backup lands in R2                                                                     | `aws s3 ls s3://universe-static-apps-01/_meta/registry/ --endpoint=$R2` shows `<date>.rdb`                                                            |
| G12  | Idempotency — operator runs the cassiopeia chapter top-to-bottom **twice** with no divergent state | flight-manual §E reruns clean                                                                                                                         |

G12 is the single most-important gate for the user's stated
constraint ("I will run every step of it to check if the manual is
idempotent"). Every section in the cassiopeia chapter must include a
"skip-if-already-done" guard (e.g. `helm get -n caddy caddy >/dev/null
2>&1 || just helm-upgrade gxy-cassiopeia caddy`).

## Section F — Open questions for user

Narrow set; only the items that block flight-manual authoring.

| #   | Question                                                                                                           | Status (2026-05-10)                                                                          |
| --- | ------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| F1  | KV substrate                                                                                                       | **Locked: Valkey single-instance alongside artemis** (user pick, vendor-neutrality weighted) |
| F2  | Helm release name + ns                                                                                             | Default: `valkey` release in `artemis` ns. Override-able if you prefer `static-apps-valkey`. |
| F3  | `POST /api/site/register` authz                                                                                    | Default: env-configurable `REGISTRY_AUTHZ_TEAM`, default value `staff`.                      |
| F4  | RDB-to-R2 mirror cadence                                                                                           | Default: nightly 03:00 UTC. Bump to 6 h to align with etcd snapshot if you want symmetry.    |
| F5  | Schema in Valkey                                                                                                   | Default: hash-per-site + `sites:all` index set; `teams` field is JSON-encoded array.         |
| F6  | When does the cassiopeia chapter rehearse against a **live cluster** (vs `--dry-run` only)? Operator-driven (you). | Document both paths; operator chooses.                                                       |

## Acceptance: when does this RFC close?

Closes when:

1. The cassiopeia flight-manual chapter (T4) lands and rehearses
   green twice on the operator's box (G12).
2. The valkey helm release lands at
   `k3s/gxy-management/apps/valkey/` with persistence + AUTH +
   NetworkPolicy.
3. The artemis chart drops `--set-file sites=...` and adds
   `VALKEY_ADDR` / `VALKEY_PASSWORD` / `REGISTRY_BACKEND=valkey`
   plumbing. Follow-up sprint deliverable in the artemis repo.
4. The artemis service ships `POST /api/site/register` and the
   Valkey-backed registry read path. Follow-up sprint deliverable.

Items 3 and 4 are **planning** scope of this RFC; the **work** is a
post-audit sprint. Item 2 (valkey chart bring-up) is in the operator
path of the cassiopeia / management flight-manual chapter. The
cassiopeia chapter encodes the END-STATE operator path — it links to
this RFC for the design and the open-Qs status table.

## Out of scope (deferred to post-GA, recorded so they don't surprise)

- Origin allow-list automation (CF edge IPs only on DO firewall)
- R2 lifecycle GC for orphan deploy bytes
- ArgoCD-driven sync of valkey + artemis manifests (post-D005 reactivation; today driven by `just deploy`)
- Supply-chain pipeline reactivation (cosign + Grype/Trivy + Syft)
- cert-manager / DNS-01 issuer
- gxy-cassiopeia Hetzner pivot (post-M5)
- Cilium Gateway eval for cassiopeia (Traefik gatewayClassName stays
  primary)

## Cites

- Probes: `.scratchpad/dossier/probes/{02-cassiopeia,03-artemis-sites,04-management-apps}.md`.
- ADR drift report: `docs/architecture/adr-drift-2026-05-10.md`.
- ADR-007, ADR-009, ADR-010, ADR-011, ADR-016 (Universe/decisions/).
- Existing flight-manual: `docs/flight-manuals/gxy-cassiopeia.md` Phase 19-24.
