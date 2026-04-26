# Sprint 2026-04-21 — DECISIONS

Locked operator decisions. **Read-only after acceptance.** Amendments
appended in-place via dated blocks; never rewrite original rows.

Source-of-truth split:

- **Q1–Q8** locked here. Brainstorm rationale archived below.
- **D33–D40** are RFC-authoritative — `docs/architecture/rfc-gxy-cassiopeia.md`
  Amendments section. Rows below are summary cross-refs only.

## Summary table — Q1–Q8 ACCEPTED 2026-04-22

| Q   | Topic                | Decision                                                                                |
| --- | -------------------- | --------------------------------------------------------------------------------------- |
| Q1  | Alias-write          | Woodpecker pipeline step (atomic last step)                                             |
| Q2  | CF R2 admin cred     | `infra-secrets/windmill/.env.enc` (D33 amended ×2 2026-04-25; Bearer + Account ID only) |
| Q3  | Per-site secrets     | Woodpecker repo-scoped secrets only — D40 supersedes D34 (no infra-secrets path)        |
| Q4  | Origin IP allow-list | DO Cloud Firewall only; no CF-IP allow-list; no per-galaxy split                        |
| Q5  | Staff-site DNS       | `<site>.freecode.camp` prod + `<site>.preview.freecode.camp` preview                    |
| Q6  | Rollback SLO         | ≤ 2 minutes (CF LRU 60s + 30s smoke poll × 2 green hits)                                |
| Q7  | Preview envs         | Both prod + preview in MVP (certs pre-issued via ACM → CF activated)                    |
| Q8  | Cleanup retention    | Hard 7d; both aliases pin their prefix                                                  |

## D-row cross-refs (RFC `rfc-gxy-cassiopeia.md` §Decisions / §Amendments)

| D   | Status                                                                              | Summary                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| --- | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D5  | superseded by D35                                                                   | Preview DNS scheme original                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| D22 | resolved                                                                            | OAuth org-gate canonical for native-OAuth tools; CF Access dropped globally                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| D29 | superseded by D36                                                                   | Origin IP enforcement original                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| D32 | resolved                                                                            | `caddy.fs.r2` + `r2_alias` modules canonical for serve plane                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| D33 | **amended ×2 2026-04-25**                                                           | CF R2 admin cred → `infra-secrets/windmill/.env.enc` (was `platform/`, then `global/`). Vars: `CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID`. Bearer-only, S3 admin keys dropped. NOT direnv-loaded.                                                                                                                                                                                                                                                                                                                                                                                           |
| D34 | **superseded by D40 2026-04-25**                                                    | Original per-site sops path                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| D35 | accepted 2026-04-22                                                                 | Preview DNS = `<site>.preview.freecode.camp` dot-scheme                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| D36 | accepted 2026-04-22                                                                 | DO Cloud Firewall only; no CF-IP allow-list                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| D37 | accepted 2026-04-22                                                                 | Two-zone staff-site DNS pattern (prod + preview siblings)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| D38 | accepted 2026-04-22                                                                 | Rollback SLO ≤ 2 min                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| D39 | accepted 2026-04-22                                                                 | 7d hard retention; alias prefix-pin                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| D40 | accepted 2026-04-25 (supersedes D34)                                                | Per-site R2 secrets persist **only** in Woodpecker repo-scoped secrets. No `constellations/` dir, no `.sops.yaml` rule. Recovery = re-mint via CF API. Offline backup → TODO-park.                                                                                                                                                                                                                                                                                                                                                                                                        |
| D41 | accepted 2026-04-26                                                                 | Smoke + cleanup ops use admin S3 keys + admin Bearer via on-demand sops decrypt of `windmill/.env.enc`. No per-cluster ops cred. No rclone. Vars: `CF_ACCOUNT_ID`, `R2_OPS_ACCESS_KEY_ID`, `R2_OPS_SECRET_ACCESS_KEY`.                                                                                                                                                                                                                                                                                                                                                                    |
| D42 | accepted 2026-04-26 (supersedes T12 ops-rw.env.enc)                                 | Per-cluster `infra-secrets/gxy-cassiopeia/ops-rw.env.enc` design dropped. Admin S3 keys live in `windmill/.env.enc` (D41).                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| D43 | accepted 2026-04-26 (supersedes T11 token-mint design; cross-ref Universe ADR D016) | Deploy-proxy plane. Standalone Go microservice at `uploads.freecode.camp` holds sole R2 admin credential. CLI authenticates via GitHub identity (env → GHA OIDC → Woodpecker OIDC → `gh auth token` → device flow). Server-side `sites.yaml` static team-slug map; per-request GH team membership probe with 5min cache. Streaming proxy (no presigned URLs). Server-side atomic alias write. New repo `freeCodeCamp/uploads`. universe-cli v0.4 fresh on `feat/proxy-pivot` off `main`. v0.3 stays current published. Per-site R2 token mint (D34/D40) DEAD — eliminated, not relocated. |

## Amendments log (this doc)

- **2026-04-22** — Q1–Q8 accepted; tasks #28–#35 closed.
- **2026-04-25** — D33 amended (`platform/` → `global/` → `windmill/.env.enc`).
  Cause: structure deep-audit caught direnv leak risk on `global/.env.enc`.
- **2026-04-25** — D40 supersedes D34. Per-site secrets stay in Woodpecker.
- **2026-04-26** — D41 added (smoke + cleanup ops surface) and D42
  added (T12 ops-rw cred superseded). Cause: T15 pre-flight + sprint
  state audit (`reports/sprint-state-audit-2026-04-25.md`) found 5
  unmet operator-env prereqs + 3 false-completion claims in G1.0.
  Recovery picked option 2 (admin Bearer + sops-on-demand for ops
  surface). See entries below.

### D41 — Smoke + cleanup ops surface (accepted 2026-04-26)

**Decision:** infra-side R2 ops (Phase 4 smoke + future cleanup cron)
consume admin S3 keys + admin Bearer **on demand from
`infra-secrets/windmill/.env.enc`**. No persistent per-cluster R2 ops
cred. No rclone surface.

**Vars added to `windmill/.env.enc` by G-dispatch G1.0a:**

- `CF_ACCOUNT_ID` — `ad45585c4383c97ec7023d61b8aef8c8` (live-verified)
- `R2_OPS_ACCESS_KEY_ID` — full-bucket-scope admin S3 key
- `R2_OPS_SECRET_ACCESS_KEY` — paired secret

**Consumers:**

- `scripts/phase4-test-site-smoke.sh` — sops-decrypts on each run,
  passes to `aws s3 ...` via env, never persists in operator shell.
- T22 cleanup cron (Windmill flow) — same pattern via Resource
  `u/admin/cf_r2_provisioner` + same `windmill/.env.enc` source.

**Why not per-cluster ops-rw:**

- One bucket → one ops key surface ≡ KISS.
- Admin token already lives at `windmill/.env.enc` (D33 ×2). Adding
  S3 ops keys to the same file consolidates rotation surface.
- Eliminates per-cluster `.env.enc` files (only `caddy.values.yaml.enc`
  belongs at `infra-secrets/k3s/<cluster>/`).
- Eliminates rclone-config-management (operator host state).

**Why not admin Bearer alone (CF REST API for objects):**

- CF REST API does not support arbitrary object PUT/GET/DELETE for
  R2 — that surface is S3-compatible only.
- `POST /accounts/{id}/r2/temp-access-credentials` requires
  `parentAccessKeyId` (an existing persistent S3 key), so Bearer-only
  bootstrap is impossible.

### D42 — T12 ops-rw.env.enc design superseded (accepted 2026-04-26)

**Decision:** Task 12 spec body lines L1842 + L1847 referencing
`infra-secrets/gxy-cassiopeia/caddy-r2.env.enc` and
`infra-secrets/gxy-cassiopeia/ops-rw.env.enc` are **superseded by D41**.
The single `windmill/.env.enc` source carries all admin R2 ops creds.
Per-cluster `.env.enc` files for R2 access are not created.

**Affected files (amendment block added in T12 spec body):**

- `docs/architecture/task-gxy-cassiopeia.md` Task 12 — amendment block
  appended pointing here.

**Recovery path on key compromise:** rotate via CF dashboard (revoke +
re-mint scoped to bucket), re-seed `windmill/.env.enc`, push Resource
update via `wmill resource push`. Same surface as admin Bearer rotation.

### D43 — Deploy-proxy plane (accepted 2026-04-26 evening)

**Cross-ref:** Universe ADR `~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md`
(written under broken-ownership session — see HANDOFF 2026-04-26 evening).

**Decision:** Deploy plane = standalone Go microservice at
`uploads.freecode.camp`. Service holds **sole** R2 admin credential.
Staff devs ship sites with **only `platform.yaml`** + GitHub identity.

**Why pivot from D40 (Woodpecker repo-scoped secrets):**

- D40 moved per-site R2 tokens from sops to Woodpecker secrets. That
  shifted blast radius from staff hands to CI hands but did not
  eliminate token sharing. Platform tenet violation persists.
- D016 removes per-site tokens entirely. Proxy is sole R2 writer.

**Q9–Q15 (locked single session, no team round-trip per broken-ownership):**

| Q   | Decision                                                                                                                                                                                                                    |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q9  | Standalone Go service, hostname `uploads.freecode.camp`. Caddy reverse-proxies to k3s service. Direct upload to existing `universe-static-apps-01/<site>/deploys/<ts>-<sha>/` — no staging bucket, no folder move.          |
| Q10 | CLI identity priority chain — `$GITHUB_TOKEN`/`$GH_TOKEN` env → GHA OIDC → Woodpecker OIDC → `gh auth token` → device-flow stored. Server validates via `GET /user`, caches login→user 5 min.                               |
| Q11 | Static `site → [team-slugs]` map server-side (`sites.yaml` hot-reload). GH team membership probe per request, cached 5 min. Apollo GH module reusable.                                                                      |
| Q12 | Streaming proxy. CLI multipart-uploads to proxy; proxy streams parts to R2. No presigned URLs.                                                                                                                              |
| Q13 | Server-side atomic alias write. Proxy is sole writer. Atomicity = single S3 PUT (R2 PutObject atomic per-key). After finalize, proxy verifies upload via ListObjectsV2, then PUT alias. Verify fail → 422; alias untouched. |
| Q14 | Yank universe-cli `feat/woodpecker-pivot` work. Fresh `feat/proxy-pivot` off `main`. v0.3 stays current published.                                                                                                          |
| Q15 | New repo `freeCodeCamp/uploads` at `~/DEV/fCC-U/uploads/`. Go module `github.com/freeCodeCamp/uploads`.                                                                                                                     |

**Survives unchanged:**

- Caddy `r2_alias` D35 dot-scheme on cassiopeia
- R2 bucket `universe-static-apps-01` + prefix-per-site layout
- Atomic alias-file write _semantics_ (proxy is the writer now)
- Admin token home in `windmill/.env.enc` (D33 ×2; proxy reads via Resource)
- T22 cleanup cron — upload-path agnostic
- D41 (smoke + cleanup ops surface) + D42 (T12 ops-rw superseded)

**Dies / pivots:**

- T11 (per-site token mint) — boneyarded with header in windmill source
- T16-T20 (universe-cli `feat/woodpecker-pivot`) — orphaned branch, never merged
- T21 (`.woodpecker/deploy.yaml` template) — demoted to optional reference example
- G1.0b (Woodpecker admin Resource) — retired; proxy doesn't push secrets to Woodpecker
- D40 — superseded by D43 in spirit (but D40 row stays for audit trail; D43 supersedes the underlying motivation)

**New dispatches filed (governing session 2026-04-26 evening):**

- T30 — D016 ADR draft (cross-repo Universe)
- T31 — uploads svc (Go, new repo)
- T32 — universe-cli v0.4 fresh branch
- T33 — `platform.yaml` v2 schema
- T34 — Caddy reverse proxy + DNS prep + smoke retarget

### Single-bucket invariant (reinforcement, not new)

`universe-static-apps-01` is the **only** R2 bucket for Universe static
apps. Per-site separation = prefix scoping (`<site>/...`), enforced by
Woodpecker per-site secret path-conditions (D40 / D22). Any future
dispatch / runbook / spec body must use bucket-prefix language, never
"per-site bucket".

## Brainstorm rationale (archived from QA-recommendations 2026-04-22)

### Q1 — Alias-write mechanism

**Decision: Woodpecker pipeline step.**

- Last step of canonical `.woodpecker/deploy.yaml` writes alias file to
  R2 after upload step succeeds.
- Atomic per deploy; no extra service hop; no Windmill dependency on
  staff push hot path. Matches ADR-007 "Windmill as glue, not hot path".
- Cost: staff repos need consistent last step. Solved by template (T21).
- Windmill wins for batch promote/rollback across multiple sites
  (Phase 2).

### Q2 — CF R2 admin cred path

**Decision: `infra-secrets/windmill/.env.enc` (D33 ×2 amended).**

- Originally proposed `infra-secrets/platform/cf-r2-provisioner.secrets.env.enc` (invented dir, rejected).
- First amendment moved to `global/.env.enc` (canonical CF token home per RFC).
- Second amendment moved to `windmill/.env.enc` because `global/.env.enc` is direnv-loaded into operator shell on every `cd infra/` — leaks admin token into every shell session.
- Final: `windmill/.env.enc` activates the previously-empty reserved Universe-platform-app namespace per `rfc-secrets-layout.md` D4. NOT direnv-loaded; consumed on-demand via `sops -d` or `wmill resource push`.
- Vars: `CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID` only. S3-style admin Access Key/Secret dropped (flow uses CF Bearer only).

### Q3 — Per-site secret path

**Decision: Woodpecker repo-scoped secrets only (D40 supersedes D34).**

- Original D34 proposed `infra-secrets/constellations/<site>.secrets.env.enc` for per-constellation portability.
- Amended 2026-04-25: per-site R2 secrets persist **only** in Woodpecker (D22 channel). No `constellations/` dir, no `.sops.yaml` rule.
- Recovery path: re-mint via CF API.
- Offline backup deferred to TODO-park.
- Names in Woodpecker: `r2_access_key_id` + `r2_secret_access_key`.

### Q4 — Origin IP allow-list

**Decision: DO Cloud Firewall only; no CF-IP allow-list.**

- `gxy-fw-fra1` keeps 80/443 open to `0.0.0.0/0`. Traffic gated behind CF proxy (SSL Full Strict); CF WAF + DDoS absorb abuse surface.
- No Windmill cron to diff CF IPs. No tag split per galaxy. KISS.
- Post-MVP triggers to reconsider: scraper-driven DO bandwidth spike, CF-bypass attack signature, compliance ask.
- T32 stamp-2 field note flagged Cilium CNP FQDN allow-lists as footgun under 1.19. Adding CF-IP rules trades footgun for weekly-cron dependency; protection not yet needed.

### Q5 — Staff-site DNS pattern

**Decision: platform-owned two-level pattern.**

- Prod: `<site>.freecode.camp` A → cassiopeia public IPs, CF proxied, SSL Full (Strict) via `*.freecode.camp` CF Origin cert (live).
- Preview: `<site>.preview.freecode.camp` A → same IPs, CF proxied, SSL Full (Strict) via `*.preview.freecode.camp` CF Origin cert (live).
- Onboarding flow accepts `<site>`, creates both A records, writes Caddy route/alias mapping.
- Phase 2: BYO domain via `universe` CLI per ADR-009 flat DNS model. Deferred until first staff asks.

### Q6 — Rollback SLO

**Decision: ≤ 2 minutes.**

- `r2_alias` caches alias file per-request with ~60s LRU TTL. Worst-case: live request resolves old alias for up to 60s after promote/rollback.
- Smoke harness polls 30s × 2 green.
- Sub-30s SLO would force CDN cache purge + shorter LRU TTL hurting steady-state cache hit rate.
- Phase 2: tiered SLO (sub-minute for prod-critical sites) when site demands it.

### Q7 — Preview environments in MVP

**Decision: prod + preview in MVP (flipped from default).**

- `*.preview.freecode.camp` CF Origin cert live alongside `*.freecode.camp`. No additional registrar/CF work.
- Each deploy writes two alias files: `<site>/production` + `<site>/preview`. `universe promote` repoints `<site>/production` to current preview prefix atomically.
- Cleanup cron treats both aliases as "in use" — same 7d retention.
- Why flipped: certs pre-issued, incremental cost collapses to R2 prefix bookkeeping. Preview path = staff safety net for prod cutover, load-bearing for content edit-and-ship loop.

### Q8 — Cleanup retention

**Decision: hard 7d per ADR-007 default; no override for MVP.**

- Windmill cron deletes deploys older than 7 days, except currently aliased (production + preview).
- KISS; no platform.yaml plumbing; 7d covers typical rollback window.
- Phase 2: per-site override via `platform.yaml` `static.retention: <N>d` when first ask lands.
