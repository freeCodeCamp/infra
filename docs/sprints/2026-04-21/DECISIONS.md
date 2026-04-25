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

| D   | Status                               | Summary                                                                                                                                                                                         |
| --- | ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D5  | superseded by D35                    | Preview DNS scheme original                                                                                                                                                                     |
| D22 | resolved                             | OAuth org-gate canonical for native-OAuth tools; CF Access dropped globally                                                                                                                     |
| D29 | superseded by D36                    | Origin IP enforcement original                                                                                                                                                                  |
| D32 | resolved                             | `caddy.fs.r2` + `r2_alias` modules canonical for serve plane                                                                                                                                    |
| D33 | **amended ×2 2026-04-25**            | CF R2 admin cred → `infra-secrets/windmill/.env.enc` (was `platform/`, then `global/`). Vars: `CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID`. Bearer-only, S3 admin keys dropped. NOT direnv-loaded. |
| D34 | **superseded by D40 2026-04-25**     | Original per-site sops path                                                                                                                                                                     |
| D35 | accepted 2026-04-22                  | Preview DNS = `<site>.preview.freecode.camp` dot-scheme                                                                                                                                         |
| D36 | accepted 2026-04-22                  | DO Cloud Firewall only; no CF-IP allow-list                                                                                                                                                     |
| D37 | accepted 2026-04-22                  | Two-zone staff-site DNS pattern (prod + preview siblings)                                                                                                                                       |
| D38 | accepted 2026-04-22                  | Rollback SLO ≤ 2 min                                                                                                                                                                            |
| D39 | accepted 2026-04-22                  | 7d hard retention; alias prefix-pin                                                                                                                                                             |
| D40 | accepted 2026-04-25 (supersedes D34) | Per-site R2 secrets persist **only** in Woodpecker repo-scoped secrets. No `constellations/` dir, no `.sops.yaml` rule. Recovery = re-mint via CF API. Offline backup → TODO-park.              |

## Amendments log (this doc)

- **2026-04-22** — Q1–Q8 accepted; tasks #28–#35 closed.
- **2026-04-25** — D33 amended (`platform/` → `global/` → `windmill/.env.enc`).
  Cause: structure deep-audit caught direnv leak risk on `global/.env.enc`.
- **2026-04-25** — D40 supersedes D34. Per-site secrets stay in Woodpecker.

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
