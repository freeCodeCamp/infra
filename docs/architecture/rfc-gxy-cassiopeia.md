# RFC: gxy-cassiopeia — Production-Grade Static-Site Galaxy

**Date:** 2026-04-16
**Status:** Draft
**Target Release:** 2026-06 (weeks of focused feature work)
**Author:** Infra team
**Related:** ADR-001 (topology), ADR-007 (developer experience / static stack), ADR-009 (networking & domains)

---

## Requirement Index

| ID  | Title                                           | Priority | Section                    |
| --- | ----------------------------------------------- | -------- | -------------------------- |
| R1  | Provision gxy-launchbase cluster                | P0       | §4.1 Cluster Provisioning  |
| R2  | Provision gxy-cassiopeia cluster                | P0       | §4.1 Cluster Provisioning  |
| R3  | Deploy Woodpecker CI on gxy-launchbase          | P0       | §4.2 Woodpecker CI         |
| R4  | Build custom Caddy `r2_alias` module            | P0       | §4.3 Caddy R2 Alias Module |
| R5  | Provision R2 bucket `universe-static-apps-01`   | P0       | §4.4 Storage Layout        |
| R6  | Deploy Caddy Helm chart on gxy-cassiopeia       | P0       | §4.5 Caddy Deployment      |
| R7  | Woodpecker pipeline template for static deploy  | P0       | §4.6 Pipeline Template     |
| R8  | DNS: `*.freecode.camp` → gxy-cassiopeia         | P0       | §4.7 DNS & TLS             |
| R9  | Preview routing `{site}--preview.freecode.camp` | P0       | §4.3 / §4.5 / §4.6         |
| R10 | Rewrite `universe deploy` (no R2 keys on dev)   | P0       | §4.8 universe-cli          |
| R11 | Rewrite `universe promote`                      | P0       | §4.8 universe-cli          |
| R12 | Rewrite `universe rollback`                     | P0       | §4.8 universe-cli          |
| R13 | Site name validation (`--` forbidden)           | P0       | §4.8 universe-cli          |
| R14 | Cloudflare cache purge on alias change          | P1       | §4.6 Pipeline Template     |
| R15 | Real-time log streaming in CLI                  | P1       | §4.8 universe-cli          |
| R16 | Old deploy cleanup cron (7-day retention)       | P1       | §4.9 Operational Flows     |
| R17 | Post-deploy smoke test                          | P1       | §4.6 Pipeline Template     |

## Decision Index

| ID  | Decision                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Rationale                                                                                                                                                                                                                                                                                                                                                                             | Alternatives §                          |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| D1  | Woodpecker CI is the sole deploy path (no direct R2 access from CLI)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Keeps R2 credentials off developer machines                                                                                                                                                                                                                                                                                                                                           | §5.1                                    |
| D2  | Build in CI, not on developer machine                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Matches Netlify/Vercel model; single source of truth                                                                                                                                                                                                                                                                                                                                  | §5.2                                    |
| D3  | R2-direct serving via custom Caddy module (no local disk, no rclone)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Simplest model; removes sync gap that plagued gxy-static                                                                                                                                                                                                                                                                                                                              | §5.3                                    |
| D4  | Custom Caddy Go module for alias resolution (~300 LOC)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | No existing plugin handles alias file → path rewrite                                                                                                                                                                                                                                                                                                                                  | §5.4                                    |
| D5  | Preview subdomain scheme: `{site}--preview.freecode.camp`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Stays under `*.freecode.camp` free wildcard SSL                                                                                                                                                                                                                                                                                                                                       | §5.5                                    |
| D6  | ArgoCD manages Caddy infrastructure only; exits per-deploy hot path                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Cleanly separates CD-of-platform from CD-of-sites                                                                                                                                                                                                                                                                                                                                     | §5.6                                    |
| D7  | Woodpecker on gxy-launchbase (not temporary on gxy-management)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Spike plan Phase 1 expectation; isolates CI from mgmt                                                                                                                                                                                                                                                                                                                                 | §5.7                                    |
| D8  | R2 bucket name: `universe-static-apps-01` (sequential suffix convention)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Matches gxy-static-1 naming; allows future buckets 2, 3…                                                                                                                                                                                                                                                                                                                              | §5.8                                    |
| D9  | Single Woodpecker pipeline with `OP` variable (deploy/promote/rollback)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Fewer pipeline files to maintain; same secrets/image cache                                                                                                                                                                                                                                                                                                                            | §5.9                                    |
| D10 | Alias files are plain text (single-line deploy ID, UTF-8, no trailing \n)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Matches current universe-cli convention; simplest to parse                                                                                                                                                                                                                                                                                                                            | §5.10                                   |
| D11 | Deploy ID format: `{YYYYMMDD-HHMMSS}-{git-sha7}`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Sortable, informative, collision-resistant                                                                                                                                                                                                                                                                                                                                            | §5.10                                   |
| D12 | gxy-cassiopeia: 3× s-4vcpu-8gb-amd DO FRA1 (same as gxy-static)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Proven size; Cloudflare fronts most traffic                                                                                                                                                                                                                                                                                                                                           | §5.11                                   |
| D13 | gxy-launchbase: 3× s-4vcpu-8gb-amd DO FRA1 initially; Hetzner migration post-M5                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Hetzner account not yet provisioned; DO unblocks Phase 1                                                                                                                                                                                                                                                                                                                              | §5.11                                   |
| D14 | Caddy cache TTL for alias file: 15s                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Balance between visibility latency and R2 request volume                                                                                                                                                                                                                                                                                                                              | §5.12                                   |
| D15 | Woodpecker namespace: `woodpecker`; Caddy namespace: `caddy`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Match existing convention (`argocd`, `windmill`, `zot`)                                                                                                                                                                                                                                                                                                                               | §5.13                                   |
| D16 | Cloudflare Flexible TLS (no origin cert changes)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Matches gxy-static; same DNS round-robin pattern                                                                                                                                                                                                                                                                                                                                      | §5.14                                   |
| D17 | Deploy events trigger on `push` to main + `manual` Woodpecker API                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Covers automatic and CLI-triggered deploys                                                                                                                                                                                                                                                                                                                                            | §5.15                                   |
| D18 | Custom module lives in `infra/docker/images/caddy-s3/modules/r2alias/`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Keep module + xcaddy build colocated; single repo ownership                                                                                                                                                                                                                                                                                                                           | §5.16                                   |
| D19 | Site name regex: `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$` (no `--`, no leading/trailing `-`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Matches RFC-1123 DNS label; prevents preview collision                                                                                                                                                                                                                                                                                                                                | §5.17                                   |
| D20 | No backward compatibility with gxy-static (user directive)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Reduces scope; gxy-static stays as sandbox for experiments                                                                                                                                                                                                                                                                                                                            | §5.18                                   |
| D21 | Woodpecker uses CloudNativePG (CNPG) at bootstrap, not SQLite                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Survives single-node PVC loss; no manual recovery procedure                                                                                                                                                                                                                                                                                                                           | §5.19                                   |
| D22 | R2 credentials are **repo-scoped**, not org-scoped                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Limits supply-chain blast radius of a compromised build dep                                                                                                                                                                                                                                                                                                                           | §5.20                                   |
| D23 | Caddy admin API binds to `127.0.0.1:2019` only                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Prevents in-cluster lateral movement via admin endpoint                                                                                                                                                                                                                                                                                                                               | §5.21                                   |
| D24 | Promote pipeline order: smoke-test the candidate deploy before writing the alias                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Failed verify never leaves a bad alias; no in-pipeline revert required                                                                                                                                                                                                                                                                                                                | §5.22                                   |
| D25 | DNS cutover preflight is a machine-checked list (`just cutover-preflight`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Removes ambiguity; prevents missed-site 404s after cutover                                                                                                                                                                                                                                                                                                                            | §5.23                                   |
| D26 | gxy-static stays live as rollback substrate for ≥ 30 days post-cutover; DNS-availability only, not content-parity (see §6.9.1)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Preserves Phase-6 rollback path until user decommissions; content-parity mitigation deferred (§5.24.1)                                                                                                                                                                                                                                                                                | §5.24, §6.9.1                           |
| D27 | Alias cache is bounded LRU (max 10k entries) with `singleflight` stampede control                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Bounds memory; prevents cache-fill attack and thundering herd                                                                                                                                                                                                                                                                                                                         | §5.25                                   |
| D28 | Cleanup cron uses an R2 lock object + 1-hour grace window                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Closes TOCTOU race between alias read and prefix delete                                                                                                                                                                                                                                                                                                                               | §5.26                                   |
| D29 | Origin access restricted to Cloudflare IP ranges (Cilium ingress allow-list)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Prevents bucket content enumeration via direct origin hit                                                                                                                                                                                                                                                                                                                             | §5.27                                   |
| D30 | Caddy pinned to `v2.11.2` (CVE-patched); 14-day CVE-bump SLA; no third-party Caddy plugins in the image                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Reproducible builds without shipping known-vulnerable Caddy; `caddy-fs-s3` removed per D32                                                                                                                                                                                                                                                                                            | §5.28                                   |
| D31 | Minimum viable observability at v1: CF uptime monitor + 5xx alert per site                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Detects next 404 storm before users do                                                                                                                                                                                                                                                                                                                                                | §5.29                                   |
| D32 | Merge S3 filesystem into `r2_alias` module as `caddy.fs.r2`; drop `sagikazarmark/caddy-fs-s3` dependency                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Upstream stale 14 months (last release Feb 1 2025) makes D30 SLA unenforceable; owning the FS layer preserves vendor-neutrality and removes single-vendor risk                                                                                                                                                                                                                        | §5.30                                   |
| D33 | R2 admin cred = **CF Account-owned API Token (Bearer)** with permission `Account → R2 Storage → Edit`, scoped to the freeCodeCamp Universe account. Lives in `infra-secrets/windmill/.env.enc` (sample-twin in `windmill/.env.sample`) — activates the reserved `windmill/` platform-wide app namespace per `rfc-secrets-layout.md` D4. Vars: `CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID`. **NO S3-style admin Access Key/Secret** — Windmill flow uses Bearer only against `api.cloudflare.com/client/v4/accounts/{id}/r2/buckets/{bucket}/credentials` to mint per-site keys. **AMENDED 2026-04-25 (twice)** — first move was `global/.env.enc`, corrected to `windmill/.env.enc` after structure audit confirmed `global/` is operator-direnv-loaded (would expose admin token in shell env on every `cd infra/`). | Cross-cluster Universe-platform Windmill app secret (consumer = Windmill flow `f/static/provision_site_r2_credentials` on gxy-management). Reserved `windmill/` namespace exists exactly for this — first activation proves the convention. NOT loaded into operator shell (no direnv coupling). Minimal blast radius (single Bearer, single perm). Sample-twin discipline preserved. | Q2 / 2026-04-22 · amended ×2 2026-04-25 |
| D34 | **SUPERSEDED 2026-04-25 by D40.** ~~Per-site data-plane secret path: `infra-secrets/constellations/<site>.secrets.env.enc` (flat, site-scoped; `.sops.yaml` `path_regex: ^constellations/.*\.secrets\.env\.enc$`)~~                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Original rationale (galaxy-stable path) overruled — Woodpecker repo-secret store IS source of truth per D22; offline backup deferred to TODO-park if/when audit need surfaces                                                                                                                                                                                                         | Q3 / 2026-04-22 · superseded 2026-04-25 |
| D35 | Preview host scheme changed: `{site}.preview.freecode.camp` (dot) via pre-issued `*.preview.freecode.camp` ACM/CF Origin cert — **SUPERSEDES D5** (`{site}--preview.freecode.camp` double-dash)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Wildcard cert already live on CF for `*.preview.freecode.camp`; cleaner DNS ergonomics; removes double-dash special case in D19 site-name regex                                                                                                                                                                                                                                       | Q5 + Q7 / 2026-04-22                    |
| D36 | Origin firewall posture: DO Cloud Firewall `gxy-fw-fra1` keeps 80/443 open to `0.0.0.0/0`; CF WAF + DDoS absorb abuse — **SUPERSEDES D29** (Cilium CF-IP allow-list + refresh cron)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | T14 2026-04-18 field note flagged Cilium 1.19 FQDN CNP as a footgun; weekly cron adds dependency for unneeded protection; MVP traffic already CF-fronted with Full Strict TLS                                                                                                                                                                                                         | Q4 / 2026-04-22                         |
| D37 | Rollback/promote SLO: ≤ 2 minutes (CF LRU 60s + 30s smoke poll × 2 consecutive green = 120s window)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | D14 alias LRU TTL of 15s tightened for launch bootstrap but baseline 60s LRU + 2× green assertions covers Phase 4 exit                                                                                                                                                                                                                                                                | Q6 / 2026-04-22                         |
| D38 | Preview is MVP-in: every deploy writes both `<site>/production` and `<site>/preview` alias files; `universe promote` atomically repoints `<site>/production` to the current preview prefix                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Certs already issued → incremental cost collapses to R2 prefix bookkeeping; preview becomes staff's prod-cutover safety net                                                                                                                                                                                                                                                           | Q7 / 2026-04-22                         |
| D39 | Deploy cleanup retention: hard 7d (no platform.yaml override for MVP); cron treats both `production` and `preview` aliases as "in use" (prefix-pin)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | KISS; per-site override deferred until first staff request                                                                                                                                                                                                                                                                                                                            | Q8 / 2026-04-22                         |
| D40 | Per-site R2 data-plane secrets persisted **ONLY** as Woodpecker repo-scoped secrets (D22 channel). T11 flow does NOT write to `infra-secrets`. No new sops scope, no `constellations/` dir. Offline backup deferred to TODO-park entry "Per-site R2 secret offline backup" with activation trigger = first audit demand                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Single source of truth = Woodpecker; eliminates dual-write drift; honors `rfc-secrets-layout.md` two-scope (no third scope invented); recoverable via re-mint from CF API if Woodpecker store lost                                                                                                                                                                                    | Supersedes D34 / 2026-04-25             |

### Amendments (2026-04-25)

Source: structure audit during sprint 2026-04-21 Wave A preflight
(see HANDOFF rolling log entry 2026-04-25). Mapped to D33 + D34 + D40.

- **AMENDED (1st pass):** D33 path moved `platform/cf-r2-provisioner.secrets.env.enc`
  → `global/.env.enc` to align with `rfc-secrets-layout.md` two-scope.
  Sample twin in `global/.env.sample` initially listed 4 vars
  (`CF_R2_ADMIN_API_TOKEN`, `CF_R2_ADMIN_ACCESS_KEY_ID`,
  `CF_R2_ADMIN_SECRET_ACCESS_KEY`, `CF_ACCOUNT_ID`).
- **AMENDED (2nd pass — same day):** D33 path corrected from
  `global/.env.enc` → **`windmill/.env.enc`** after structure audit
  noted that `global/.env.enc` is loaded into operator shell env via
  direnv on every `cd infra/`, leaking the admin token into every
  shell. Reserved Universe-platform `windmill/` namespace (per
  `rfc-secrets-layout.md` D4) is the canonical home for cross-cluster
  Windmill app secrets. Sample twin in `windmill/.env.sample`. Vars
  reduced to **2** (`CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID`) — flow
  uses CF Bearer only, S3 admin keys dropped (smaller blast radius).
- **SUPERSEDED:** D34 → D40. Per-site secrets stay in Woodpecker;
  no `constellations/` dir, no new sops creation_rule. T11 dispatch
  steps that wrote to infra-secrets are dropped.
- **TODO-park entry:** "Per-site R2 secret offline backup — activation
  trigger: first audit/recovery demand."
- **PROPAGATION:** sprint docs (`24-static-apps-k7d.md`, `MASTER.md`,
  `QA-recommendations.md`, `windmill-t11-dispatch.md`) carry corrected
  paths via T11 worker closure step (sprint-doc patch tagged onto T11).
  `infra-secrets/README.md` rewritten same day to document the
  decision tree + activate `windmill/` namespace + sample-twin
  discipline (2026-04-25 commit).
- **CORRECTED (bucket-name drift, evening):** All references to R2
  bucket `gxy-cassiopeia-1` → `universe-static-apps-01` (canonical
  per HANDOFF galaxy state + cluster-audit + sprint MASTER + Wave A
  operator confirmation). Affects R5 dispatch row, §4.4 Storage
  Layout, §4.6.3 path conditions, §6 cutover steps, §Task-11/22/25
  acceptance, §A.2 inventory snippets. Runbooks (`r2-bucket-provision.md`,
  `dns-cutover.md`) + flight-manual `gxy-cassiopeia.md` patched in
  same commit. Bucket-name "sequential suffix per D8" convention
  unchanged in spirit; the `-01` suffix matches D8 — naming scheme
  shifted from `gxy-<name>-N` to `universe-<purpose>-NN` mid-spike to
  decouple bucket lifetime from galaxy lifetime (R2 buckets persist
  across cassiopeia rebuilds).

### Amendments (2026-04-22)

Source: `docs/sprints/2026-04-21/QA-recommendations.md` (accepted
2026-04-22). Mapped to Decision Index rows D33–D39 above.

- **SUPERSEDED:** D5 → D35 (preview host scheme). Site-name regex (D19)
  unchanged; `--preview` suffix convention retired.
- **SUPERSEDED:** D29 → D36 (origin FW posture). T14 bead
  `gxy-static-k7d.15` closed with descope reason 2026-04-22.
- **REINFORCED:** D1 by Q1 → alias write is the canonical last step of
  `.woodpecker/deploy.yaml` (T21 pipeline template).
- **UNCHANGED:** D2, D3, D6–D28, D30–D32. No revisions required.

---

## 1. Summary

This RFC specifies **gxy-cassiopeia**, a production-grade static-site galaxy for Universe constellations. It replaces the sandbox `gxy-static` galaxy as the `*.freecode.camp` production target. It also scopes **gxy-launchbase**, the CI galaxy hosting Woodpecker, which is a prerequisite. The design is a "thin Netlify/Vercel": Woodpecker CI builds and uploads immutable deploys to R2; a custom Caddy Go module reads alias files from R2 to resolve which deploy each request should serve; Cloudflare CDN fronts the origin.

Two galaxies are provisioned. One CI pipeline is rewritten. One custom Caddy module (~300 LOC Go) is written, built into the existing xcaddy image, and deployed. Three CLI commands (`deploy`, `promote`, `rollback`) are rewritten to trigger Woodpecker via its REST API — developers never see R2 credentials.

## 2. Motivation

`gxy-static` (the current live static galaxy) drifted from ADR-007 in two ways documented in [field notes](../../../../fCC-U/Universe/spike/field-notes/infra.md) (2026-04-15):

1. **Polled 5-minute rclone sync.** Destructive — deleting bucket files propagates to pod local SSD on the next tick; no S3 fallback means the site returns 404 during the gap.
2. **Duplicated shell alias resolver** in init and sidecar containers, also polled every 5 minutes.

The observed failure mode: bucket edits briefly 404 the site, and browsers holding stale HTML referencing old asset hashes 404 on JS/CSS until they refresh. The infrastructure cannot be called production-grade while this is true.

Rather than patch `gxy-static` (which would require backward-compatibility surgery), the user has directed a fresh build that implements ADR-007 correctly end-to-end. The sandbox galaxy remains for experimentation and will be decommissioned by the user after cutover.

Universe's public-facing static sites — documentation, marketing, course landing pages, per-product constellations — need a serving path with these properties:

- **Deploys are immediate.** An alias update must be visible to new requests within 30 seconds, not 5 minutes.
- **Deploys are immutable.** Each deploy gets its own prefix; rollback is an alias repoint, not a rebuild.
- **No developer holds R2 credentials.** Security posture: blast radius of a leaked dev machine is bounded to their GitHub account and Woodpecker token, not the production bucket.
- **No backward compatibility burden.** Clean room.

## 3. Goals and Non-Goals

### 3.1 Goals

1. Provision gxy-launchbase (3 nodes, DO FRA1) and gxy-cassiopeia (3 nodes, DO FRA1) with the existing `play-k3s--bootstrap.yml` playbook, adding only new `group_vars` files. (Hetzner migration for gxy-launchbase is deferred to post-M5 once the account is provisioned.)
2. Deploy Woodpecker CI on gxy-launchbase with GitHub OAuth forge integration and org-scoped R2 secrets.
3. Deploy a new Caddy Helm chart release on gxy-cassiopeia using the custom `r2_alias` module — no rclone sidecars, no ConfigMap shell loops.
4. Rewrite `universe deploy|promote|rollback` to trigger Woodpecker pipelines via REST API with Bearer token auth and stream pipeline logs over SSE.
5. Move `*.freecode.camp` (+ apex + www) DNS from gxy-static to gxy-cassiopeia node IPs.
6. Deliver a reference pipeline template (`.woodpecker/deploy.yaml`) for static constellations that handles deploy, promote, and rollback operations via a single `OP` variable.
7. Preview URL convention `{site}--preview.freecode.camp` works with a valid Cloudflare free-tier wildcard certificate.
8. Ship with a cutover plan that leaves gxy-static untouched; users decommission it on their schedule after cutover confirms gxy-cassiopeia is stable.

### 3.2 Non-Goals

1. **Not migrating gxy-static.** The existing galaxy stays live as a sandbox until the user decommissions it. Cutover is DNS-level only.
2. **Not building container-app support.** gxy-cassiopeia serves static files. Dynamic app hosting is gxy-triangulum's role (deferred, separate spec).
3. **Not implementing gxy-backoffice observability stack.** Caddy access logs ship to stdout; ClickHouse pipeline (ADR-015) is deferred.
4. **Not implementing custom domains.** Constellations use `*.freecode.camp` only for v1. Custom domain mapping (`my-app.example.com` → constellation) is deferred.
5. **Not implementing branch/per-PR previews.** One `preview` alias per site. Per-branch previews are deferred.
6. **Not building a deploy dashboard UI.** CLI-only interface for v1.
7. **Not keeping local disk caching on Caddy.** R2-direct is v1. If origin latency becomes a problem, add a disk cache layer in a follow-up (two-way door decision).
8. **Not implementing Ceph RGW migration.** R2 stays as the S3 provider for both cloud and bare-metal phases until ADR-008 is revisited.

## 4. Detailed Design

### 4.1 Cluster Provisioning

Two new k3s clusters, same bootstrap path as `gxy-static` and `gxy-management`.

#### 4.1.1 gxy-launchbase

- **Provider:** DigitalOcean, Frankfurt (FRA1) — initial. Hetzner CX32 FSN1 migration is a post-M5 follow-up (D13).
- **Nodes:** 3× s-4vcpu-8gb-amd (4 vCPU / 8 GB RAM / 80 GB SSD)
- **k3s version:** `v1.34.5+k3s1` (matches current fleet)
- **Cilium cluster ID:** `3` (gxy-management=1, gxy-static=2, gxy-cassiopeia=4 — reserve 3 for launchbase)
- **Inventory group:** `gxy_launchbase_k3s`
- **DO tag:** `_gxy-launchbase-k3s` (dynamic inventory keys on this; hyphens become underscores in the Ansible group)
- **group_vars file:** `ansible/inventory/group_vars/gxy_launchbase_k3s.yml`

Config (new file to add):

```yaml
---
# gxy-launchbase galaxy configuration
# CI galaxy — Woodpecker server + agents for Universe constellations
# 3x s-4vcpu-8gb-amd in DO FRA1 (pre-Hetzner migration)

galaxy_name: gxy-launchbase
k3s_version: v1.34.5+k3s1
cilium_cluster_id: 3

server_config_yaml: |
  flannel-backend: "none"
  disable-network-policy: true
  disable-kube-proxy: true
  disable:
    - servicelb
  cluster-cidr: "10.6.0.0/16"
  service-cidr: "10.16.0.0/16"
  protect-kernel-defaults: true
  secrets-encryption: true
  kube-apiserver-arg:
    - "admission-control-config-file=/etc/rancher/k3s/pss-admission.yaml"
    - "audit-log-path=/var/log/k3s/audit.log"
    - "audit-policy-file=/etc/rancher/k3s/audit-policy.yaml"
    - "audit-log-maxage=30"
    - "audit-log-maxbackup=10"
    - "audit-log-maxsize=100"
  etcd-s3: true
  etcd-s3-endpoint: "fra1.digitaloceanspaces.com"
  etcd-s3-bucket: "net-freecodecamp-universe-backups"
  etcd-s3-folder: "etcd/gxy-launchbase"
  etcd-s3-region: "fra1"
  etcd-snapshot-schedule-cron: "0 */6 * * *"
  etcd-snapshot-retention: 20
```

CIDRs `10.6.0.0/16` (pod) and `10.16.0.0/16` (service) do not collide with gxy-management (`10.0.0.0/16`+`10.10.0.0/16`) or gxy-static (`10.5.0.0/16`+`10.15.0.0/16`).

#### 4.1.2 gxy-cassiopeia

- **Provider:** DigitalOcean, Frankfurt (FRA1)
- **Nodes:** 3× s-4vcpu-8gb-amd
- **k3s version:** `v1.34.5+k3s1`
- **Cilium cluster ID:** `4`
- **Inventory group:** `gxy_cassiopeia_k3s`
- **group_vars file:** `ansible/inventory/group_vars/gxy_cassiopeia_k3s.yml`

Config (new file to add):

```yaml
---
# gxy-cassiopeia galaxy configuration
# Production static constellation galaxy — Caddy + R2
# 3x s-4vcpu-8gb-amd in DO FRA1

galaxy_name: gxy-cassiopeia
k3s_version: v1.34.5+k3s1
cilium_cluster_id: 4

server_config_yaml: |
  flannel-backend: "none"
  disable-network-policy: true
  disable-kube-proxy: true
  disable:
    - servicelb
  cluster-cidr: "10.7.0.0/16"
  service-cidr: "10.17.0.0/16"
  protect-kernel-defaults: true
  secrets-encryption: true
  kube-apiserver-arg:
    - "admission-control-config-file=/etc/rancher/k3s/pss-admission.yaml"
    - "audit-log-path=/var/log/k3s/audit.log"
    - "audit-policy-file=/etc/rancher/k3s/audit-policy.yaml"
    - "audit-log-maxage=30"
    - "audit-log-maxbackup=10"
    - "audit-log-maxsize=100"
  etcd-s3: true
  etcd-s3-endpoint: "fra1.digitaloceanspaces.com"
  etcd-s3-bucket: "net-freecodecamp-universe-backups"
  etcd-s3-folder: "etcd/gxy-cassiopeia"
  etcd-s3-region: "fra1"
  etcd-snapshot-schedule-cron: "0 */6 * * *"
  etcd-snapshot-retention: 20
```

#### 4.1.3 Ansible Inventory

The existing `ansible/inventory/digitalocean.yml` dynamic inventory already covers gxy-launchbase when nodes are tagged correctly.

- **No new inventory file required.** DO tag `_gxy-launchbase-k3s` maps to Ansible group `gxy_launchbase_k3s` via the existing keyed_groups regex.
- **Tag convention:** All gxy-launchbase nodes carry DO tag `_gxy-launchbase-k3s` (leading underscore, hyphens preserved).
- **Existing `gxy_management_k3s` and `gxy_static_k3s`** groups in `digitalocean.yml` are unchanged.
- **Post-M5 Hetzner migration (deferred):** will introduce `ansible/inventory/hetzner.yml` using `hetzner.hcloud.hcloud` plugin and add the collection to `ansible/requirements.yml`. Not in scope for M0–M5.

#### 4.1.4 Bootstrap Procedure

Full bootstrap is identical to gxy-static (documented in `docs/flight-manuals/gxy-launchbase.md`):

1. ClickOps: provision 3× s-4vcpu-8gb-amd in DO FRA1 with the cloud-init config at `cloud-init/k3s-node.yaml` and tag `_gxy-launchbase-k3s`.
2. Direnv loads the cluster-specific DO token from `infra-secrets`.
3. `just play k3s--bootstrap` provisions k3s on all nodes in the target galaxy.
4. `just play k3s--cluster` applies Cilium and Traefik.

No playbook edits required — the playbook already reads `galaxy_name`, `cilium_cluster_id`, and `server_config_yaml` from group_vars. `cloud-init/k3s-node.yaml` was authored for DO FRA1 so no provider-parity dry-run is needed; the future Hetzner migration will add that gate when reintroduced.

### 4.2 Woodpecker CI (gxy-launchbase)

#### 4.2.1 Version and Chart

- **Woodpecker version:** v3.13.0 (released 2026-01-14, current stable at RFC date).
- **Helm chart:** `woodpeckerci/woodpecker` official chart, version pinned in the repo at `k3s/gxy-launchbase/apps/woodpecker/charts/woodpecker/repo`.
- **Namespace:** `woodpecker`
- **Release name:** `woodpecker`

#### 4.2.2 Topology

One server, three agents (one per node as a DaemonSet).

- **Server:** 2 replicas, 100 MB–500 MB RAM each. Backed by a **CloudNativePG** (CNPG) cluster in the same namespace (1 primary + 1 replica; `local-path` storage class in v1, Rook-Ceph when bare-metal lands per ADR-008). WAL archiving to DO Spaces (`net-freecodecamp-universe-backups/cnpg/gxy-launchbase/woodpecker`). **No SQLite.** See D21, §5.19.
- **Agents:** DaemonSet on all 3 nodes. `WOODPECKER_MAX_WORKFLOWS=2` per agent. Total capacity: 6 concurrent workflows.
- **Backend:** Kubernetes backend (`WOODPECKER_BACKEND=kubernetes`). Each workflow step runs as a Pod.

**CNPG topology details (D21):**

- Chart: `cloudnative-pg/cloudnative-pg` operator + `Cluster` CR. Operator installed cluster-wide in `cnpg-system`.
- Cluster spec: 2 instances (1 primary + 1 replica), PostgreSQL 16, `synchronous_commit = remote_write` with one synchronous standby.
- Backups: WAL archiving + 6-hourly base backups to DO Spaces. Retention 14 days. PITR window = 14 days.
- Secrets: database credentials injected into Woodpecker via `valueFrom.secretKeyRef` — sourced from the CNPG-generated `app` user secret.
- Restore drill: monthly scripted restore to a `woodpecker-restore-test` cluster, verifies backup chain integrity. Justfile recipe `just cnpg-restore-test gxy-launchbase woodpecker`.

#### 4.2.3 GitHub Integration

- **Forge:** GitHub OAuth app (`https://github.com/settings/developers` under `freeCodeCamp-Universe` org) for v1. See D28 / §5.26 for the GitHub App migration track.
- **OAuth callback:** `https://woodpecker.freecodecamp.net/authorize`
- **Webhook URL:** `https://woodpecker.freecodecamp.net/hook` (set automatically when Woodpecker activates a repo).
- **Required scopes:** `repo`, `read:org`, `user:email`.
- **Admin users:** Platform team GitHub usernames via `WOODPECKER_ADMIN`.

**Blast radius acknowledgment (CRITICAL).** The `repo` scope grants full read/write to every private repo the authorizing user can access across the `freeCodeCamp-Universe` org, not just constellation repos. A compromised Woodpecker server or admin OAuth token can exfiltrate or modify any private repo in the org. Compensating controls for v1:

1. Cloudflare Access on `woodpecker.freecodecamp.net` with email OTP restricted to the platform-team group (P1 security TODO §8.2 promoted to Phase 2 exit criterion).
2. Woodpecker server runs in a namespace with no other workloads; Cilium NetworkPolicy restricts egress (§8.2).
3. Admin OAuth sessions require 2FA at the GitHub org level (enforce via `freeCodeCamp-Universe` org settings; document in M1 exit checklist).
4. Audit log shipping: Woodpecker's audit log is mounted to a PVC and rotated; copy nightly to DO Spaces (Windmill cron in Phase 2 exit).
5. **Target end state:** migrate to a GitHub App with per-repo fine-grained permissions (`contents:read`, `metadata:read`, plus `checks:write` only on constellation repos). Tracked as Post-M5 work in §14 Q8.

#### 4.2.4 Secrets

**R2 write credentials are repo-scoped, not org-scoped** (D22, §5.20). Each registered constellation receives its own R2 access-key pair at registration time, minted with an IAM-equivalent policy (R2 Access Token with a [path condition](https://developers.cloudflare.com/r2/api/tokens/) limiting writes to `universe-static-apps-01/{site}/*`). This means a compromised build dependency in constellation A cannot overwrite constellation B's deploys.

| Scope        | Secret Name            | Value Source                                           | Used By                              |
| ------------ | ---------------------- | ------------------------------------------------------ | ------------------------------------ |
| **Repo**     | `r2_access_key_id`     | per-site, issued by onboarding flow, sops-encrypted    | Only that constellation's pipeline   |
| **Repo**     | `r2_secret_access_key` | per-site, issued by onboarding flow, sops-encrypted    | Only that constellation's pipeline   |
| Organization | `r2_endpoint`          | `https://<account>.r2.cloudflarestorage.com`           | All deploy pipelines (non-sensitive) |
| Organization | `r2_bucket`            | `universe-static-apps-01`                              | All deploy pipelines (non-sensitive) |
| Organization | `cf_api_token`         | CF Purge Cache API token, zone-scoped to freecode.camp | Cache purge step                     |
| Organization | `cf_zone_id`           | Cloudflare zone ID for `freecode.camp`                 | Cache purge step (non-sensitive)     |

R2 path conditions on the per-site token (documented at `https://developers.cloudflare.com/r2/api/tokens/#path-specific-access`):

```
allow PutObject, GetObject, DeleteObject on universe-static-apps-01/{site}/*
deny  PutObject, GetObject, DeleteObject on universe-static-apps-01/*
```

Caddy's read-only key is a separate org-scoped credential (not stored in Woodpecker; stored in Caddy's k8s Secret directly, sourced from infra-secrets, narrow to `GetObject` across the whole bucket).

Per-site secret bootstrap flow (justfile recipe `just constellation-register <site>`):

1. Mint R2 token via Cloudflare API with path condition above.
2. Store credentials sops-encrypted in `infra-secrets/cassiopeia/sites/<site>.secrets.env.enc`.
3. Push to Woodpecker as repo-scoped secrets via `woodpecker-cli repo secret add --repository=freeCodeCamp-Universe/<site>`.

Org-scope secrets are ONLY non-sensitive (`r2_endpoint`, `r2_bucket`, `cf_zone_id`) or scoped to a single tenant (`cf_api_token` is zone-limited to `freecode.camp`, so its blast radius is the same zone we already control).

Rotation:

- Per-site R2 keys: 90 days, rotated by a Windmill flow that mints a new token, updates sops file, calls `woodpecker-cli repo secret add`.
- `cf_api_token`: 90 days, same flow.
- `cf_zone_id`: never rotates (infrastructure identifier).

#### 4.2.5 Ingress

- **Domain:** `woodpecker.freecodecamp.net`
- **Routing:** Cloudflare → gxy-launchbase node public IPs → Traefik (hostNetwork) → Woodpecker service.
- **TLS:** Cloudflare Flexible (same pattern as other `.freecodecamp.net` services).
- **Cloudflare Access:** Platform team only, email OTP (deferred to P1 security TODO; open admin UI for now).

#### 4.2.6 API Authentication

Personal access tokens are created per user via the Woodpecker UI (`/user/token`). Tokens are used as `Authorization: Bearer <token>` in the universe-cli.

- **CLI token storage:** `WOODPECKER_TOKEN` environment variable, loaded by direnv from the developer's `~/.config/direnv/lib/universe.sh` or equivalent. Tokens are NOT stored in the repo.
- **Token scope:** Per user. No shared service tokens. Revocation is per-user in Woodpecker UI.

### 4.3 Caddy R2 Alias Module

#### 4.3.1 Module Identity

- **Go package path:** `github.com/freeCodeCamp-Universe/infra/docker/images/caddy-s3/modules/r2alias`
- **Package layout:** two Caddy modules register from this package — the middleware handler (alias resolver + path rewrite) and the filesystem (serves objects from R2). Shared S3 client, shared config fields, shared cache. Per D32 (§5.30), we own the FS layer instead of depending on `sagikazarmark/caddy-fs-s3`.
- **Caddy module IDs:**
  - `http.handlers.r2_alias` — middleware handler (T01–T03); Caddyfile directive `r2_alias`; ordered before `file_server`.
  - `caddy.fs.r2` — filesystem module (T01b); registered via Caddyfile `filesystem <name> r2 { ... }` under the global options block; consumed by `file_server { fs <name> }`.

#### 4.3.2 Responsibilities

1. Parse the `Host` header; split into `{site}` and `{alias_name}`.
   - If Host matches `<site>--preview.freecode.camp` → `site=<site>.freecode.camp`, `alias_name=preview`.
   - Otherwise → `site=<Host verbatim>`, `alias_name=production`.
2. Read alias file `{site}/{alias_name}` from the configured R2 bucket via AWS SDK v2 `s3.GetObject`.
3. Cache the alias file contents in a **bounded LRU TTL cache** (default 15s TTL, default 10,000 entries max) with `singleflight.Group` de-duplication so concurrent requests for the same missing key issue only one R2 GetObject (D27, §5.25). Cache key: `{bucket}/{site}/{alias_name}`. Library: `github.com/hashicorp/golang-lru/v2/expirable` for the LRU+TTL, `golang.org/x/sync/singleflight` for stampede protection.
4. If alias value exists and passes deploy-ID validation (regex `^[A-Za-z0-9._-]{1,64}$`, no `..`): rewrite the request URL path to `/{site}/deploys/{deploy-id}{original-path}` and pass to the next handler.
5. If alias file is missing (404) or invalid: respond `404 Not Found` with a configurable body (default: `Not Found`).
6. If R2 returns 5xx: respond `503 Service Unavailable` with a 30s `Retry-After` header; log error with fields `site`, `alias_name`, `upstream_status`.

#### 4.3.3 Caddyfile Directive

```caddy
{
  order r2_alias before file_server
}

:80 {
  r2_alias {
    bucket           {$R2_BUCKET}
    endpoint         {$R2_ENDPOINT}
    region           auto
    access_key_id    {$AWS_ACCESS_KEY_ID}
    secret_access_key {$AWS_SECRET_ACCESS_KEY}
    cache_ttl        15s
    cache_max_entries 10000
    preview_suffix   "--preview"
    root_domain      "freecode.camp"
    deploy_id_regex  "^[A-Za-z0-9._-]{1,64}$"
  }

  file_server {
    fs r2
  }
}
```

#### 4.3.4 Interface Contract (for implementers)

```go
package r2alias

import (
    "context"
    "net/http"
    "time"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/service/s3"
    "github.com/caddyserver/caddy/v2"
    "github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
    "github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
    "github.com/caddyserver/caddy/v2/modules/caddyhttp"
)

// R2Alias is a Caddy HTTP handler that resolves {site}/{alias_name} files in
// an S3-compatible bucket and rewrites the request path to the target deploy
// prefix. It is positioned before file_server so the rewritten path is served
// by the sibling caddy.fs.r2 filesystem module (same Go package, registered
// separately; see R2FS below).
type R2Alias struct {
    Bucket           string        `json:"bucket"`
    Endpoint         string        `json:"endpoint"`
    Region           string        `json:"region"`
    AccessKeyID      string        `json:"access_key_id,omitempty"`
    SecretAccessKey  string        `json:"secret_access_key,omitempty"`
    CacheTTL         time.Duration `json:"cache_ttl,omitempty"`
    CacheMaxEntries  int           `json:"cache_max_entries,omitempty"`   // default 10_000
    PreviewSuffix    string        `json:"preview_suffix,omitempty"`
    RootDomain       string        `json:"root_domain,omitempty"`
    DeployIDRegex    string        `json:"deploy_id_regex,omitempty"`

    client  *s3.Client
    cache   *expirable.LRU[string, aliasEntry]   // hashicorp/golang-lru/v2/expirable
    sfgroup singleflight.Group                    // golang.org/x/sync/singleflight
    logger  *zap.Logger
}

// aliasEntry is the cached resolution. Present=true means a valid deploy ID was
// resolved; Present=false is the "missing alias" sentinel used to absorb scan
// traffic against dead subdomains.
type aliasEntry struct {
    DeployID string
    Present  bool
}

// CaddyModule returns the Caddy module information.
func (R2Alias) CaddyModule() caddy.ModuleInfo {
    return caddy.ModuleInfo{
        ID:  "http.handlers.r2_alias",
        New: func() caddy.Module { return new(R2Alias) },
    }
}

// Provision sets up the S3 client and alias cache. Called once at startup.
func (r *R2Alias) Provision(ctx caddy.Context) error { /* ... */ }

// Validate enforces configuration invariants.
func (r *R2Alias) Validate() error { /* ... */ }

// UnmarshalCaddyfile parses Caddyfile tokens into struct fields.
func (r *R2Alias) UnmarshalCaddyfile(d *caddyfile.Dispenser) error { /* ... */ }

// ServeHTTP implements the handler. It resolves the alias, rewrites r.URL.Path,
// and calls next.ServeHTTP.
func (r R2Alias) ServeHTTP(w http.ResponseWriter, req *http.Request, next caddyhttp.Handler) error { /* ... */ }

// Interface guards
var (
    _ caddy.Provisioner           = (*R2Alias)(nil)
    _ caddy.Validator             = (*R2Alias)(nil)
    _ caddyfile.Unmarshaler       = (*R2Alias)(nil)
    _ caddyhttp.MiddlewareHandler = (*R2Alias)(nil)
)

// R2FS is a Caddy filesystem module (caddy.fs.r2) that serves objects from
// R2. It is consumed by file_server after r2_alias has rewritten the path.
// Registered in the same Go package as R2Alias — the two modules share config
// conventions but are instantiated independently so each Caddyfile can wire
// them with distinct credentials if desired.
type R2FS struct {
    Bucket          string `json:"bucket"`
    Endpoint        string `json:"endpoint"`
    Region          string `json:"region"`
    AccessKeyID     string `json:"access_key_id,omitempty"`
    SecretAccessKey string `json:"secret_access_key,omitempty"`
    UsePathStyle    bool   `json:"use_path_style,omitempty"` // default true for R2

    client *s3.Client
    logger *zap.Logger
}

// CaddyModule returns the filesystem module information.
func (R2FS) CaddyModule() caddy.ModuleInfo {
    return caddy.ModuleInfo{
        ID:  "caddy.fs.r2",
        New: func() caddy.Module { return new(R2FS) },
    }
}

// Provision sets up the S3 client. Called once at startup.
func (r *R2FS) Provision(ctx caddy.Context) error { /* ... */ }

// Open implements fs.FS — issues s3.GetObject and wraps the body in a
// seekable reader backed by an in-memory buffer (bounded by upstream
// Content-Length; files > R2FS.MaxFileSize return fs.ErrInvalid).
func (r *R2FS) Open(name string) (fs.File, error) { /* ... */ }

// Stat implements fs.StatFS — issues s3.HeadObject (lighter than GetObject).
func (r *R2FS) Stat(name string) (fs.FileInfo, error) { /* ... */ }

// Interface guards for R2FS
var (
    _ fs.StatFS             = (*R2FS)(nil)
    _ caddy.Provisioner     = (*R2FS)(nil)
    _ caddyfile.Unmarshaler = (*R2FS)(nil)
)
```

#### 4.3.5 Alias Cache

A **bounded LRU TTL cache** keyed by `bucket/site/alias_name` (D27, §5.25). Implementation:

- Library: `github.com/hashicorp/golang-lru/v2/expirable` — fixed capacity, TTL per entry, goroutine-safe.
- Default capacity: 10,000 entries (~1 MB worst-case with 100-byte entries). Configurable via `cache_max_entries`.
- Default TTL: 15s (both for present and missing entries). Configurable via `cache_ttl`.
- Values: `aliasEntry{DeployID string, Present bool}`. `Present=false` is the missing-alias sentinel.
- **Stampede control:** `singleflight.Group.Do(key, fetch)` wraps every cache miss. Concurrent requests for the same key de-dup to a single R2 GetObject; all waiters receive the same result.
- On S3 404: cache `{Present: false}` for full TTL. Prevents a subdomain-scan attack from inflating R2 request volume.
- On S3 5xx: do NOT cache; `singleflight` ensures only one in-flight retry per key; return 503 with `Retry-After: 30` to the caller.
- Memory bound: capacity × entry size. LRU eviction kicks in past capacity. At 10,000 entries this is a few MB in the worst case, well inside the 512 Mi Caddy pod limit.

#### 4.3.6 Path Rewrite

Original request: `GET /assets/main.js` with Host `hello-world.freecode.camp`.

After alias resolution (alias value `20260501-120000-a1b2c3d`):

- Rewritten path: `/hello-world.freecode.camp/deploys/20260501-120000-a1b2c3d/assets/main.js`
- `req.URL.Path` is mutated to the rewritten value.
- The next handler (`file_server { fs r2 }`) calls `Open()` on the S3 filesystem with the new path, which maps to the R2 key `hello-world.freecode.camp/deploys/20260501-120000-a1b2c3d/assets/main.js`.

For `GET /` (no explicit path), the standard `file_server` index resolution (`index.html`) applies after rewrite.

#### 4.3.7 Preview Routing

Host header `hello-world--preview.freecode.camp`:

- Strip suffix `--preview` from first label → `hello-world`
- Site key for alias lookup: `hello-world.freecode.camp`
- Alias name: `preview`
- Alias file path in R2: `hello-world.freecode.camp/preview`
- On resolution, rewritten path: `/hello-world.freecode.camp/deploys/{preview-id}/…`

Note the **R2 key prefix uses the production site name** (`hello-world.freecode.camp`), not the preview subdomain. This means preview and production deploys share the same `{site}/deploys/` tree; only the alias file differs. This is how Netlify/Vercel structure deploys.

#### 4.3.8 Build Integration

Extend `infra/docker/images/caddy-s3/Dockerfile`:

```dockerfile
# Pin both stages to an exact minor to avoid drift on rebuild (D30).
# Caddy v2.11.2 is the current stable patched against the Q1 2026 CVE wave
# (forward_auth identity injection + vars_regexp secret exposure + Feb 2026 batch
# of 6 CVEs in 2.11.1 covering host/path matching, TLS client auth, file matcher).
# Do NOT downgrade below 2.11.2.
FROM caddy:2.11-builder AS builder

ENV GOTOOLCHAIN=auto

COPY modules/r2alias /src/modules/r2alias

# Per D32 (§5.30): no third-party Caddy plugins. The r2alias Go package
# registers both http.handlers.r2_alias (alias resolver) and caddy.fs.r2
# (filesystem backend) from a single in-tree module.
RUN xcaddy build v2.11.2 \
    --with github.com/freeCodeCamp-Universe/infra/docker/images/caddy-s3/modules/r2alias=/src/modules/r2alias

FROM caddy:2.11-alpine

LABEL org.opencontainers.image.source=https://github.com/freeCodeCamp-Universe/infra
LABEL org.opencontainers.image.description="Caddy with in-tree r2alias module (alias resolver + R2 filesystem) for Universe static constellations"
LABEL org.opencontainers.image.licenses=Apache-2.0

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
```

Image tag convention: `ghcr.io/freecodecamp-universe/caddy-s3:{YYYYMMDD}-{git-sha7}`. Built and pushed by a Woodpecker pipeline in the infra repo on every change to `docker/images/caddy-s3/**`.

### 4.4 Storage Layout

#### 4.4.1 R2 Bucket

- **Name:** `universe-static-apps-01`
- **Account:** freeCodeCamp-Universe Cloudflare account
- **Provisioning:** ClickOps (Cloudflare UI) for v1; import to OpenTofu later (ADR-002).
- **Access keys:** Two keys — one for Woodpecker (read/write), one for Caddy (read-only). Both stored in `infra-secrets/gxy-cassiopeia/` as sops-encrypted files.
- **Public access:** Disabled. All access via S3 v4 signed requests.
- **Lifecycle rules:** None for v1. Cleanup is handled by the Windmill cron (§4.9).

#### 4.4.2 Key Layout

```
universe-static-apps-01/
├── {site}/
│   ├── deploys/
│   │   ├── {deploy-id}/
│   │   │   ├── index.html
│   │   │   ├── assets/…
│   │   │   └── _deploy-meta.json
│   │   └── …
│   ├── production                  # plain-text file: deploy-id
│   └── preview                     # plain-text file: deploy-id
```

Where `{site}` is the full subdomain (e.g. `hello-world.freecode.camp`) — not the bare constellation name. This matches the current universe-cli convention.

#### 4.4.3 Alias File Format

- Filename: `{site}/production` or `{site}/preview`
- Content: **single-line UTF-8 deploy ID, no trailing newline, no leading/trailing whitespace**.
- Content-Type: `text/plain`
- Cache-Control: `no-store` on PutObject (prevents any intermediary from caching the alias file itself).
- Example content: `20260501-120000-a1b2c3d`
- Writes MUST be atomic (S3 `PutObject` is atomic on R2; no partial reads).

**Audit metadata (SUGGESTION #27).** Every alias `PutObject` attaches S3 user-defined metadata so post-incident analysis can answer "who flipped this alias, from what pipeline":

| Metadata key             | Value                                      | Notes                                        |
| ------------------------ | ------------------------------------------ | -------------------------------------------- |
| `x-amz-meta-pipeline-id` | Woodpecker pipeline number                 | `${CI_PIPELINE_NUMBER}` in the pipeline      |
| `x-amz-meta-git-sha`     | full git commit SHA                        | `${CI_COMMIT_SHA}`                           |
| `x-amz-meta-op`          | `deploy`, `promote`, or `rollback`         | Lets audit distinguish first-deploy vs later |
| `x-amz-meta-actor`       | Woodpecker user who triggered the pipeline | `${CI_PIPELINE_AUTHOR}` or `system` on cron  |
| `x-amz-meta-timestamp`   | RFC3339 UTC                                | `date -u +%Y-%m-%dT%H:%M:%SZ` in step        |

Set via `rclone rcat --header-upload "x-amz-meta-pipeline-id: ..."` in the `write-alias` and `revert-alias` steps. Retrievable via `rclone lsjson` or S3 `HeadObject`. No additional storage cost — R2 supports up to 2KB of user metadata per object.

#### 4.4.4 Deploy ID Format

`{YYYYMMDD}-{HHMMSS}-{git-sha7}` where:

- `YYYYMMDD-HHMMSS` is UTC, deploy-creation time.
- `git-sha7` is the first 7 chars of the git commit SHA.
- If git is dirty or git info is unavailable, the suffix is `dirty-{randhex8}`.

Regex: `^\d{8}-\d{6}-([a-f0-9]{7}|dirty-[a-f0-9]{8})$`. The caddy module uses a looser regex (`^[A-Za-z0-9._-]{1,64}$`) to accept future formats without code changes; the CLI is the stricter producer.

#### 4.4.5 Deploy Metadata

`_deploy-meta.json` at the root of each deploy prefix:

```json
{
  "deployId": "20260501-120000-a1b2c3d",
  "timestamp": "2026-05-01T12:00:00Z",
  "gitHash": "a1b2c3d…",
  "gitBranch": "main",
  "gitDirty": false,
  "fileCount": 42,
  "totalSize": 123456,
  "buildEnv": {
    "nodeVersion": "22.12.0",
    "woodpeckerPipeline": 317
  }
}
```

Used by `universe status` (future) and `universe rollback` to list history.

### 4.5 Caddy Deployment (gxy-cassiopeia)

#### 4.5.1 Helm Chart Location

- Chart path: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/`
- This is a **new chart**, not a fork of the gxy-static chart. The old chart stays at `k3s/gxy-static/apps/caddy/` untouched.

#### 4.5.2 Chart Structure

```
k3s/gxy-cassiopeia/apps/caddy/
├── charts/
│   └── caddy/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── configmap.yaml
│           ├── secret.yaml
│           ├── service.yaml
│           ├── networkpolicy.yaml
│           └── httproute.yaml
└── values.production.yaml
```

#### 4.5.3 Deployment Template

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ .Chart.Name }}
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ .Chart.Name }}
        app.kubernetes.io/instance: {{ .Release.Name }}
      annotations:
        checksum/caddyfile: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                topologyKey: kubernetes.io/hostname
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/name: {{ .Chart.Name }}
                    app.kubernetes.io/instance: {{ .Release.Name }}
      containers:
        - name: caddy
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          # Admin API binds 127.0.0.1:2019 (D23) — not exposed as a container port.
          # Reachable only from `kubectl exec` into the pod for diagnostics.
          envFrom:
            - secretRef:
                name: {{ .Release.Name }}-r2-credentials
          volumeMounts:
            - name: caddyfile
              mountPath: /etc/caddy/Caddyfile
              subPath: Caddyfile
            - name: caddy-data
              mountPath: /data
            - name: caddy-config
              mountPath: /config
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 3
            periodSeconds: 5
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
      volumes:
        - name: caddyfile
          configMap:
            name: {{ .Release.Name }}-caddyfile
        - name: caddy-data
          emptyDir: {}
        - name: caddy-config
          emptyDir: {}
```

**Note:** No `initContainers`, no `rclone-sync` sidecar, no `site-data` volume. Caddy reads directly from R2.

#### 4.5.4 Caddyfile ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-caddyfile
data:
  Caddyfile: |
    {
      auto_https off
      # Admin API bound to loopback only (D23) — prevents in-cluster lateral movement.
      admin 127.0.0.1:2019

      order r2_alias before file_server

      # D32 (§5.30): filesystem backed by the in-tree caddy.fs.r2 module
      # (same Go package as http.handlers.r2_alias). No third-party plugins.
      filesystem r2 r2 {
        bucket           {$R2_BUCKET}
        region           auto
        endpoint         {$R2_ENDPOINT}
        access_key_id    {$AWS_ACCESS_KEY_ID}
        secret_access_key {$AWS_SECRET_ACCESS_KEY}
        use_path_style
      }
    }

    :80 {
      log {
        output stdout
        format json
      }

      # Apex and www redirect to freecodecamp.org (same as gxy-static)
      @apex host freecode.camp www.freecode.camp
      handle @apex {
        redir https://www.freecodecamp.org{uri} 302
      }

      # Health check (short-circuits alias resolution)
      handle /healthz {
        respond "ok" 200
      }

      # Resolve {site}/{alias} and rewrite path, then serve from R2
      r2_alias {
        bucket           {$R2_BUCKET}
        endpoint         {$R2_ENDPOINT}
        region           auto
        access_key_id    {$AWS_ACCESS_KEY_ID}
        secret_access_key {$AWS_SECRET_ACCESS_KEY}
        cache_ttl        15s
        preview_suffix   "--preview"
        root_domain      "freecode.camp"
      }

      file_server {
        fs r2
      }

      handle_errors {
        @404 expression {err.status_code} == 404
        respond @404 "Not Found" 404

        @503 expression {err.status_code} == 503
        respond @503 "Service Unavailable" 503

        respond "Server Error" 500
      }
    }
```

#### 4.5.5 Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Release.Name }}-r2-credentials
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID:     {{ .Values.r2.accessKeyId | quote }}
  AWS_SECRET_ACCESS_KEY: {{ .Values.r2.secretAccessKey | quote }}
  R2_ENDPOINT:           {{ .Values.r2.endpoint | quote }}
  R2_BUCKET:             {{ .Values.r2.bucket | quote }}
```

Populated from sops-encrypted overlay: `infra-secrets/gxy-cassiopeia/caddy.secrets.values.yaml`. The Caddy R2 key is **read-only** — it cannot write, which prevents module bugs from corrupting live data.

#### 4.5.6 Service and HTTPRoute

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: http
      name: http
  selector:
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}

# httproute.yaml (Traefik's Gateway API binding)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .Release.Name }}
spec:
  parentRefs:
    - name: traefik
      namespace: kube-system
  hostnames:
    - "*.freecode.camp"
  rules:
    - backendRefs:
        - name: {{ .Release.Name }}
          port: 80
```

#### 4.5.7 values.production.yaml

```yaml
replicaCount: 3

image:
  repository: ghcr.io/freecodecamp-universe/caddy-s3
  tag: "20260516-a1b2c3d" # pinned; updated by image-tag bump PR
  pullPolicy: IfNotPresent

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 1000m
    memory: 512Mi

r2:
  bucket: universe-static-apps-01
  endpoint: "https://<cf-account>.r2.cloudflarestorage.com"
  # accessKeyId and secretAccessKey injected from sops overlay
```

#### 4.5.8 NetworkPolicy

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: caddy-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: caddy
  egress:
    - toFQDNs:
        - matchPattern: "*.r2.cloudflarestorage.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
  # Ingress: only port 80 from cluster + world (via Traefik). Port 2019 is NOT
  # reachable — Caddy binds it to 127.0.0.1 (D23). NetworkPolicy MUST NOT allow
  # 2019 ingress; allowing it would re-introduce the lateral-movement risk.
  ingress:
    - fromEntities: [cluster, world]
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
```

**Origin access restriction (D29, §5.27).** gxy-cassiopeia node public IPs are discoverable via passive DNS history even with Cloudflare proxy enabled. To prevent bucket content enumeration via direct origin access, the cluster `HTTPRoute` (§4.5.6) pairs with a CiliumNetworkPolicy at the ingress-controller level that allow-lists Cloudflare's published IP ranges (`https://www.cloudflare.com/ips-v4/` and `-v6/`). A Windmill cron refreshes this list weekly. Requests from non-Cloudflare IPs get dropped at L3. Health-check exemption: gxy-cassiopeia nodes may probe each other's `:80/healthz` internally; enforced via separate allow rule for node-internal CIDR.

### 4.6 Pipeline Template

#### 4.6.1 Pipeline File

Each static constellation repo contains `.woodpecker/deploy.yaml`. The template is maintained in `~/DEV/fCC-U/Universe-templates/static-woodpecker/` (future repo) and copied in by `universe register`. For v1, constellations receive the template manually; templating automation is deferred.

#### 4.6.2 Pipeline Definition

```yaml
# .woodpecker/deploy.yaml
when:
  - event: push
    branch: main
  - event: manual

variables:
  - &rclone_image "rclone/rclone:1.70.0"
  - &node_image "node:22-alpine"
  - &alpine_image "alpine:3.20"
  - &curl_image "curlimages/curl:8.10.1"

steps:
  compute-deploy-id:
    image: *alpine_image
    commands:
      - |
        OP="${OP:-deploy}"
        TARGET="${DEPLOY_TARGET:-preview}"
        SITE="${CI_REPO_NAME}.freecode.camp"
        TS=$(date -u +%Y%m%d-%H%M%S)
        GIT_HASH=$(echo "${CI_COMMIT_SHA}" | cut -c1-7)
        DEPLOY_ID="${TS}-${GIT_HASH}"
        {
          echo "OP=${OP}"
          echo "TARGET=${TARGET}"
          echo "SITE=${SITE}"
          echo "DEPLOY_ID=${DEPLOY_ID}"
        } > .env
        cat .env

  build:
    image: *node_image
    commands:
      - npm ci
      - npm run build
      # dist/ is the expected output dir; constellations override with static.output_dir
    when:
      evaluate: 'env.OP == "deploy"'

  upload:
    image: *rclone_image
    environment:
      AWS_ACCESS_KEY_ID:
        from_secret: r2_access_key_id
      AWS_SECRET_ACCESS_KEY:
        from_secret: r2_secret_access_key
      R2_ENDPOINT:
        from_secret: r2_endpoint
      R2_BUCKET:
        from_secret: r2_bucket
    commands:
      - source .env
      - |
        rclone config create r2 s3 \
          provider=Cloudflare \
          endpoint="${R2_ENDPOINT}" \
          access_key_id="${AWS_ACCESS_KEY_ID}" \
          secret_access_key="${AWS_SECRET_ACCESS_KEY}"
      - |
        rclone copy dist/ "r2:${R2_BUCKET}/${SITE}/deploys/${DEPLOY_ID}/" \
          --checksum \
          --transfers=16 \
          --checkers=16
      - |
        cat > /tmp/meta.json <<EOF
        {
          "deployId": "${DEPLOY_ID}",
          "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
          "gitHash": "${CI_COMMIT_SHA}",
          "gitBranch": "${CI_COMMIT_BRANCH}",
          "fileCount": $(find dist -type f | wc -l),
          "totalSize": $(du -sb dist | cut -f1),
          "woodpeckerPipeline": ${CI_PIPELINE_NUMBER}
        }
        EOF
      - |
        rclone copyto /tmp/meta.json \
          "r2:${R2_BUCKET}/${SITE}/deploys/${DEPLOY_ID}/_deploy-meta.json"
    when:
      evaluate: 'env.OP == "deploy"'

  resolve-deploy-id:
    image: *rclone_image
    environment:
      AWS_ACCESS_KEY_ID:
        from_secret: r2_access_key_id
      AWS_SECRET_ACCESS_KEY:
        from_secret: r2_secret_access_key
      R2_ENDPOINT:
        from_secret: r2_endpoint
      R2_BUCKET:
        from_secret: r2_bucket
    commands:
      - source .env
      - |
        rclone config create r2 s3 \
          provider=Cloudflare \
          endpoint="${R2_ENDPOINT}" \
          access_key_id="${AWS_ACCESS_KEY_ID}" \
          secret_access_key="${AWS_SECRET_ACCESS_KEY}"
      - |
        # For promote: read preview alias, use that as the promote target
        if [ "${OP}" = "promote" ]; then
          DEPLOY_ID=$(rclone cat "r2:${R2_BUCKET}/${SITE}/preview")
          TARGET=production
          sed -i "s/^DEPLOY_ID=.*/DEPLOY_ID=${DEPLOY_ID}/" .env
          sed -i "s/^TARGET=.*/TARGET=${TARGET}/" .env
        fi
        # For rollback: ROLLBACK_TO must be passed as a variable from the CLI
        if [ "${OP}" = "rollback" ]; then
          if [ -z "${ROLLBACK_TO}" ]; then
            echo "ERROR: ROLLBACK_TO variable required for rollback operation" >&2
            exit 2
          fi
          sed -i "s/^DEPLOY_ID=.*/DEPLOY_ID=${ROLLBACK_TO}/" .env
          sed -i "s/^TARGET=.*/TARGET=production/" .env
        fi
        cat .env
    when:
      evaluate: 'env.OP == "promote" || env.OP == "rollback"'

  # Pre-flight: verify the candidate deploy prefix is complete BEFORE touching
  # any alias. Catches broken uploads without needing to flip aliases first.
  verify-deploy:
    image: *rclone_image
    environment:
      AWS_ACCESS_KEY_ID:
        from_secret: r2_access_key_id
      AWS_SECRET_ACCESS_KEY:
        from_secret: r2_secret_access_key
      R2_ENDPOINT:
        from_secret: r2_endpoint
      R2_BUCKET:
        from_secret: r2_bucket
    commands:
      - source .env
      - |
        rclone config create r2 s3 \
          provider=Cloudflare \
          endpoint="${R2_ENDPOINT}" \
          access_key_id="${AWS_ACCESS_KEY_ID}" \
          secret_access_key="${AWS_SECRET_ACCESS_KEY}"
      - |
        # Deploy prefix must exist and contain at least an index.html.
        if ! rclone lsf "r2:${R2_BUCKET}/${SITE}/deploys/${DEPLOY_ID}/" > /dev/null 2>&1; then
          echo "ERROR: deploy prefix does not exist: ${SITE}/deploys/${DEPLOY_ID}/" >&2
          exit 3
        fi
        if ! rclone lsf "r2:${R2_BUCKET}/${SITE}/deploys/${DEPLOY_ID}/index.html" > /dev/null 2>&1; then
          echo "ERROR: deploy prefix missing index.html: ${SITE}/deploys/${DEPLOY_ID}/" >&2
          exit 3
        fi
        echo "Candidate deploy verified: ${SITE}/deploys/${DEPLOY_ID}/"

  # Capture the previous alias value so we can revert on smoke-test failure
  # (D24). If no previous alias exists (first deploy), PREVIOUS_DEPLOY_ID is empty.
  snapshot-previous-alias:
    image: *rclone_image
    environment:
      AWS_ACCESS_KEY_ID:
        from_secret: r2_access_key_id
      AWS_SECRET_ACCESS_KEY:
        from_secret: r2_secret_access_key
      R2_ENDPOINT:
        from_secret: r2_endpoint
      R2_BUCKET:
        from_secret: r2_bucket
    commands:
      - source .env
      - |
        rclone config create r2 s3 \
          provider=Cloudflare \
          endpoint="${R2_ENDPOINT}" \
          access_key_id="${AWS_ACCESS_KEY_ID}" \
          secret_access_key="${AWS_SECRET_ACCESS_KEY}"
      - |
        PREV=$(rclone cat "r2:${R2_BUCKET}/${SITE}/${TARGET}" 2>/dev/null || echo "")
        echo "PREVIOUS_DEPLOY_ID=${PREV}" >> .env
        echo "Captured previous ${TARGET} alias: ${PREV:-<none>}"

  # Purge CDN BEFORE flipping the alias (WARNING #13). This invalidates the
  # edge cache so the next request after alias flip triggers a fresh origin
  # fetch — no mixed-state window where edge has old content but Caddy has new.
  purge-cache-pre:
    image: *curl_image
    environment:
      CF_API_TOKEN:
        from_secret: cf_api_token
      CF_ZONE_ID:
        from_secret: cf_zone_id
    commands:
      - source .env
      - |
        if [ "${TARGET}" = "preview" ]; then
          HOST="${SITE%%.*}--preview.freecode.camp"
        else
          HOST="${SITE}"
        fi
        curl -fsS -X POST \
          "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
          -H "Authorization: Bearer ${CF_API_TOKEN}" \
          -H "Content-Type: application/json" \
          --data "{\"hosts\":[\"${HOST}\"]}"

  write-alias:
    image: *rclone_image
    environment:
      AWS_ACCESS_KEY_ID:
        from_secret: r2_access_key_id
      AWS_SECRET_ACCESS_KEY:
        from_secret: r2_secret_access_key
      R2_ENDPOINT:
        from_secret: r2_endpoint
      R2_BUCKET:
        from_secret: r2_bucket
    commands:
      - source .env
      - |
        rclone config create r2 s3 \
          provider=Cloudflare \
          endpoint="${R2_ENDPOINT}" \
          access_key_id="${AWS_ACCESS_KEY_ID}" \
          secret_access_key="${AWS_SECRET_ACCESS_KEY}"
      - |
        echo -n "${DEPLOY_ID}" | rclone rcat \
          --header-upload "Cache-Control: no-store" \
          "r2:${R2_BUCKET}/${SITE}/${TARGET}"
        echo "Alias ${TARGET} → ${DEPLOY_ID}"

  smoke-test:
    image: *curl_image
    # failure: false keeps the pipeline running so the revert step can fire.
    failure: ignore
    commands:
      - source .env
      - |
        if [ "${TARGET}" = "preview" ]; then
          URL="https://${SITE%%.*}--preview.freecode.camp/"
        else
          URL="https://${SITE}/"
        fi
        # Wait up to 60s for alias cache + CDN fresh fetch to settle.
        for i in $(seq 1 12); do
          if curl -fsS --max-time 10 "${URL}" -o /tmp/smoke.html; then
            if grep -q "<html" /tmp/smoke.html; then
              echo "SMOKE_OK=1" >> .env
              exit 0
            fi
          fi
          sleep 5
        done
        echo "ERROR: smoke test failed after 60s: ${URL}" >&2
        echo "SMOKE_OK=0" >> .env
        exit 4

  # Revert alias on smoke-test failure (D24). Runs only when smoke-test set
  # SMOKE_OK=0 AND we have a previous alias to revert to.
  revert-alias:
    image: *rclone_image
    environment:
      AWS_ACCESS_KEY_ID:
        from_secret: r2_access_key_id
      AWS_SECRET_ACCESS_KEY:
        from_secret: r2_secret_access_key
      R2_ENDPOINT:
        from_secret: r2_endpoint
      R2_BUCKET:
        from_secret: r2_bucket
      CF_API_TOKEN:
        from_secret: cf_api_token
      CF_ZONE_ID:
        from_secret: cf_zone_id
    commands:
      - source .env
      - |
        rclone config create r2 s3 \
          provider=Cloudflare \
          endpoint="${R2_ENDPOINT}" \
          access_key_id="${AWS_ACCESS_KEY_ID}" \
          secret_access_key="${AWS_SECRET_ACCESS_KEY}"
      - |
        if [ "${SMOKE_OK}" != "0" ]; then
          echo "Smoke test passed; no revert needed."
          exit 0
        fi
        if [ -z "${PREVIOUS_DEPLOY_ID}" ]; then
          echo "ERROR: smoke failed and no previous alias exists — cannot revert."
          echo "Manual intervention required. Current ${TARGET} alias points at broken deploy ${DEPLOY_ID}."
          exit 5
        fi
        echo -n "${PREVIOUS_DEPLOY_ID}" | rclone rcat \
          --header-upload "Cache-Control: no-store" \
          "r2:${R2_BUCKET}/${SITE}/${TARGET}"
        echo "Reverted ${TARGET} alias: ${DEPLOY_ID} → ${PREVIOUS_DEPLOY_ID}"
        if [ "${TARGET}" = "preview" ]; then
          HOST="${SITE%%.*}--preview.freecode.camp"
        else
          HOST="${SITE}"
        fi
        curl -fsS -X POST \
          "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
          -H "Authorization: Bearer ${CF_API_TOKEN}" \
          -H "Content-Type: application/json" \
          --data "{\"hosts\":[\"${HOST}\"]}"
        # Exit non-zero so the pipeline is marked failed even though we reverted.
        exit 6
    when:
      evaluate: 'env.SMOKE_OK == "0"'
```

**Step order rationale (D24):**

1. `compute-deploy-id` — generates IDs, writes `.env`.
2. `build` / `upload` — only on `OP=deploy`. Candidate deploy lands at `{site}/deploys/{id}/`.
3. `resolve-deploy-id` — only on `OP=promote`/`rollback`. Resolves which existing deploy is the target.
4. `verify-deploy` — pre-flight: candidate prefix exists, has `index.html`. Cheap, fails fast.
5. `snapshot-previous-alias` — captures the current alias so revert is possible.
6. `purge-cache-pre` — purges CF edge **before** the alias flip (WARNING #13). No mixed-state window.
7. `write-alias` — atomic PutObject of the new alias with `Cache-Control: no-store` on the alias object itself.
8. `smoke-test` — hits the live URL. 60s budget (allows 15s Caddy cache + CF fresh-fetch). `failure: ignore` + `SMOKE_OK` env flag.
9. `revert-alias` — runs only when `SMOKE_OK=0`. Restores previous alias, purges CF again. Exits non-zero so the pipeline reports failure.

**No bad-alias window on smoke failure.** `snapshot-previous-alias` ensures we can always revert. First-deploy failures (no previous alias) exit with a clear error telling the operator to investigate manually — rare case, gets alerted (§10.3).

#### 4.6.3 Variables Reference

| Variable        | Source        | Values                          | Meaning                                        |
| --------------- | ------------- | ------------------------------- | ---------------------------------------------- |
| `OP`            | API / default | `deploy`, `promote`, `rollback` | Pipeline operation. Default `deploy` on push.  |
| `DEPLOY_TARGET` | API / default | `preview`, `production`         | Alias to write. Default `preview`.             |
| `ROLLBACK_TO`   | API           | deploy-id string                | Required when `OP=rollback`; target deploy ID. |

#### 4.6.4 Event Trigger Map

| Trigger                  | Resulting `OP` | Resulting `DEPLOY_TARGET` | Notes                           |
| ------------------------ | -------------- | ------------------------- | ------------------------------- |
| `git push` to `main`     | `deploy`       | `preview`                 | Automatic preview on every push |
| `universe deploy`        | `deploy`       | `preview`                 | Manual API trigger from CLI     |
| `universe promote`       | `promote`      | `production` (resolved)   | CLI passes OP=promote via API   |
| `universe rollback <id>` | `rollback`     | `production`              | CLI passes OP + ROLLBACK_TO     |

Deploying directly to `production` from a push is **intentionally not supported** for v1. Production requires an explicit `promote`.

### 4.7 DNS and TLS

#### 4.7.1 DNS Records

All records on the `freecode.camp` Cloudflare zone. Proxied (orange cloud) for CDN + TLS termination.

| Type | Name  | Value                    | TTL | Proxied | Purpose               |
| ---- | ----- | ------------------------ | --- | ------- | --------------------- |
| A    | `@`   | gxy-cassiopeia node 1 IP | 1m  | Yes     | Apex redirect (Caddy) |
| A    | `@`   | gxy-cassiopeia node 2 IP | 1m  | Yes     | Apex redirect (Caddy) |
| A    | `@`   | gxy-cassiopeia node 3 IP | 1m  | Yes     | Apex redirect (Caddy) |
| A    | `www` | gxy-cassiopeia node 1 IP | 1m  | Yes     | www redirect          |
| A    | `www` | gxy-cassiopeia node 2 IP | 1m  | Yes     | www redirect          |
| A    | `www` | gxy-cassiopeia node 3 IP | 1m  | Yes     | www redirect          |
| A    | `*`   | gxy-cassiopeia node 1 IP | 1m  | Yes     | Wildcard to Caddy     |
| A    | `*`   | gxy-cassiopeia node 2 IP | 1m  | Yes     | Wildcard to Caddy     |
| A    | `*`   | gxy-cassiopeia node 3 IP | 1m  | Yes     | Wildcard to Caddy     |

The existing gxy-static `A` records (same names, pointing at gxy-static node IPs) are **replaced** during cutover, not added to. See §6 Migration & Rollout Strategy.

#### 4.7.2 TLS

- **Edge:** Cloudflare Universal SSL, free tier, covers `*.freecode.camp` (single level of wildcard).
- **Cloudflare → Origin:** Flexible (HTTP between CF and node). Matches gxy-static. Future hardening to Full (Strict) with Cloudflare Origin CA certificates is a P1 security TODO.
- **No cert-manager, no Let's Encrypt, no Caddy auto HTTPS.** `auto_https off` is set explicitly.

#### 4.7.3 Preview Host Matching

`{site}--preview.freecode.camp` matches the single-level wildcard. No additional certificate or DNS record required per preview — the wildcard covers all.

### 4.8 universe-cli Changes

#### 4.8.1 Config Schema

`~/DEV/fCC-U/universe-cli/src/config/schema.ts` adds a `woodpecker` section:

```typescript
interface UniverseConfig {
  name: string;
  domain?: { production?: string; preview?: string };
  static: {
    output_dir: string;
    // rclone_remote and bucket REMOVED — no direct R2 access
  };
  woodpecker: {
    endpoint: string; // e.g. "https://woodpecker.freecodecamp.net"
    repo_id: number; // Woodpecker's internal repo ID (integer)
    // token loaded from WOODPECKER_TOKEN env var
  };
}
```

`.universe.yaml` in each constellation repo (example):

```yaml
name: hello-world
domain:
  production: hello-world.freecode.camp
  preview: hello-world--preview.freecode.camp
static:
  output_dir: dist
woodpecker:
  endpoint: https://woodpecker.freecodecamp.net
  repo_id: 42
```

The `repo_id` is obtained by calling `GET /api/repos/lookup/<owner>/<name>` once at registration time and persisted in the config.

#### 4.8.2 `universe deploy`

File: `universe-cli/src/commands/deploy.ts` — complete rewrite.

```typescript
export interface DeployOptions {
  json: boolean;
  branch?: string;
  follow?: boolean; // stream logs; default true in TTY, false in CI
}

export async function deploy(options: DeployOptions): Promise<void> {
  const config = loadConfig();
  const wp = resolveWoodpecker(config.woodpecker);
  const git = getGitState();
  enforceGitClean(git); // throws if dirty or no commits

  const pipeline = await wp.pipelines.create(config.woodpecker.repo_id, {
    branch: options.branch ?? git.branch,
    variables: {
      OP: "deploy",
      DEPLOY_TARGET: "preview",
    },
  });

  outputSuccess(ctx, `Deploy pipeline #${pipeline.number} started`, {
    pipelineNumber: pipeline.number,
    site: config.name,
    previewUrl: `https://${config.name}--preview.freecode.camp`,
  });

  if (options.follow) {
    await streamPipelineLogs(wp, config.woodpecker.repo_id, pipeline.number);
  }
}
```

Key changes from current implementation:

1. **No `createS3Client`, no `uploadDirectory`, no `writeAlias`.** The CLI does not touch R2.
2. **No `resolveDeployId` with collision retry.** Deploy IDs are generated by the pipeline.
3. **Adds `streamPipelineLogs`** using Woodpecker's SSE endpoint.
4. **Adds `enforceGitClean`** — deploys from a dirty working tree are rejected (use `git stash` or `--force` if implemented in P1).
5. **Config-side removes `rclone_remote` and `bucket`** — they are no longer referenced.

#### 4.8.3 `universe promote`

File: `universe-cli/src/commands/promote.ts` — complete rewrite.

```typescript
export async function promote(options: PromoteOptions): Promise<void> {
  const config = loadConfig();
  const wp = resolveWoodpecker(config.woodpecker);
  const git = getGitState();

  const pipeline = await wp.pipelines.create(config.woodpecker.repo_id, {
    branch: git.branch,
    variables: { OP: "promote" },
  });

  outputSuccess(ctx, `Promote pipeline #${pipeline.number} started`, {
    pipelineNumber: pipeline.number,
    site: config.name,
    productionUrl: `https://${config.name}.freecode.camp`,
  });

  if (options.follow) {
    await streamPipelineLogs(wp, config.woodpecker.repo_id, pipeline.number);
  }
}
```

Promote resolves the current preview deploy ID inside the pipeline (step `resolve-deploy-id`), so the CLI does not need to know it.

#### 4.8.4 `universe rollback`

```typescript
export async function rollback(options: RollbackOptions): Promise<void> {
  const config = loadConfig();
  const wp = resolveWoodpecker(config.woodpecker);

  if (!options.to) {
    throw new Error(
      "--to <deploy-id> is required. Use `universe history` to list deploys.",
    );
  }

  const pipeline = await wp.pipelines.create(config.woodpecker.repo_id, {
    branch: "main",
    variables: {
      OP: "rollback",
      ROLLBACK_TO: options.to,
    },
  });

  outputSuccess(ctx, `Rollback pipeline #${pipeline.number} started`, {
    pipelineNumber: pipeline.number,
    rollbackTo: options.to,
  });

  if (options.follow) {
    await streamPipelineLogs(wp, config.woodpecker.repo_id, pipeline.number);
  }
}
```

`universe history` (new subcommand, P1) lists deploy IDs by reading `_deploy-meta.json` files from R2. For v1, developers can read R2 directly (via the platform team's tooling) or the Woodpecker UI pipeline history.

#### 4.8.5 Site Name Validation

File: `universe-cli/src/validation/site-name.ts` (new).

```typescript
export const SITE_NAME_REGEX = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/;
export const SITE_NAME_MAX_LENGTH = 50;

export function validateSiteName(name: string): void {
  if (name.length === 0 || name.length > SITE_NAME_MAX_LENGTH) {
    throw new Error(
      `Site name must be 1–${SITE_NAME_MAX_LENGTH} chars, got ${name.length}`,
    );
  }
  if (!SITE_NAME_REGEX.test(name)) {
    throw new Error(
      `Site name must match ${SITE_NAME_REGEX}. ` +
        `Lowercase alphanumeric + hyphen, no leading/trailing hyphen, no "--".`,
    );
  }
  if (name.includes("--")) {
    throw new Error(
      `Site name must not contain "--" (reserved for preview routing).`,
    );
  }
  if (name.endsWith("-preview") || name.startsWith("preview-")) {
    // Soft warning rather than hard fail — user may want these for a reason.
    console.warn(
      `Site name "${name}" contains "preview" in a position that may be ` +
        `confusing with preview routing. Consider renaming.`,
    );
  }
}
```

Called by `universe create` (scaffold) and `universe register` (repo creation). Fails fast — no silent coercion.

#### 4.8.6 Woodpecker API Client

File: `universe-cli/src/woodpecker/client.ts` (new).

```typescript
export class WoodpeckerClient {
  constructor(
    private readonly endpoint: string,
    private readonly token: string,
  ) {}

  async createPipeline(
    repoId: number,
    options: { branch: string; variables?: Record<string, string> },
  ): Promise<Pipeline> {
    const resp = await fetch(`${this.endpoint}/api/repos/${repoId}/pipelines`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        branch: options.branch,
        variables: options.variables ?? {},
      }),
    });
    if (!resp.ok) {
      throw new WoodpeckerError(
        `Pipeline create failed: ${resp.status} ${await resp.text()}`,
      );
    }
    return resp.json();
  }

  async *streamLogs(
    repoId: number,
    pipelineNumber: number,
    stepId: number,
  ): AsyncGenerator<LogLine> {
    const url = `${this.endpoint}/api/stream/logs/${repoId}/${pipelineNumber}/${stepId}`;
    const resp = await fetch(url, {
      headers: { Authorization: `Bearer ${this.token}` },
    });
    const reader = resp.body!.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    while (true) {
      const { done, value } = await reader.read();
      if (done) return;
      buffer += decoder.decode(value, { stream: true });
      let idx: number;
      while ((idx = buffer.indexOf("\n\n")) >= 0) {
        const event = buffer.slice(0, idx);
        buffer = buffer.slice(idx + 2);
        const data = event
          .split("\n")
          .filter((l) => l.startsWith("data: "))
          .map((l) => l.slice(6))
          .join("\n");
        if (data) {
          yield JSON.parse(data) as LogLine;
        }
      }
    }
  }

  async getPipeline(repoId: number, pipelineNumber: number): Promise<Pipeline> {
    const resp = await fetch(
      `${this.endpoint}/api/repos/${repoId}/pipelines/${pipelineNumber}`,
      { headers: { Authorization: `Bearer ${this.token}` } },
    );
    if (!resp.ok) throw new WoodpeckerError(`${resp.status}`);
    return resp.json();
  }
}
```

#### 4.8.7 Credential Loading

`WoodpeckerToken` is loaded by `resolveCredentials` (new function, parallel to the existing `resolveCredentials` for rclone but scoped to Woodpecker only):

```typescript
export function resolveWoodpeckerToken(): string {
  const token = process.env.WOODPECKER_TOKEN;
  if (!token) {
    throw new CredentialError(
      "WOODPECKER_TOKEN not set. Create a token at " +
        "https://woodpecker.freecodecamp.net/user/token and export it " +
        "via direnv or your shell profile.",
    );
  }
  return token;
}
```

The old `resolveCredentials` (rclone-based) is **removed** — dead code after this RFC lands.

### 4.9 Operational Flows (Windmill)

Windmill's role in gxy-cassiopeia is narrow: a daily cleanup cron. Nothing in the deploy hot path.

#### 4.9.1 Old Deploy Cleanup Flow

- **Name:** `f/static/cleanup_old_deploys`
- **Trigger:** Windmill cron `0 4 * * *` (daily at 04:00 UTC)
- **Retention policy:**
  - Keep every deploy currently referenced by any alias (`production` or `preview`) in any site.
  - Keep the 3 most recent deploys per site regardless of age.
  - **Never delete any deploy modified in the last 1 hour** (grace window against promote/rollback races — D28).
  - Delete all other deploys older than 7 days.
- **Input:** `dry_run: bool` (default `true` on first run; flip to `false` after a dry-run review).
- **Output:** JSON report `{sitesProcessed, deploysRetained, deploysDeleted, bytesFreed, sitesSkippedDueToLock}` posted to an internal Slack/Chat channel.

**Concurrency control (D28):** The cron acquires an R2-backed lock before running, and re-reads each site's aliases immediately before deleting that site's prefixes. Without both guards, a promote or rollback between the cron's initial alias read and its `DeletePrefix` call can strand a live alias pointing at a deleted deploy (WARNING #16).

Pseudocode:

```typescript
const LOCK_KEY = "_ops/cleanup.lock";
const LOCK_TTL = 90 * 60; // 90 minutes — longer than worst-case cron runtime
const GRACE_MS = 60 * 60 * 1000; // 1-hour grace window

// 1. Attempt to acquire the R2 lock. If another run holds it, bail out.
if (!acquireLock(LOCK_KEY, LOCK_TTL, instanceId)) {
  report({ skipped: "cleanup already running" });
  return;
}

try {
  for (const site of listSitePrefixes(bucket)) {
    // 2. Per-site alias re-read AFTER the global lock — captures latest state.
    const productionId = await readAlias(`${site}/production`);
    const previewId = await readAlias(`${site}/preview`);
    const deploys = await listDeploysWithMtime(site); // sorted desc by mtime

    const recentIds = new Set(deploys.slice(0, 3).map((d) => d.id));
    const aliasIds = new Set([productionId, previewId].filter(Boolean));
    const now = Date.now();

    for (const deploy of deploys) {
      if (aliasIds.has(deploy.id)) continue;
      if (recentIds.has(deploy.id)) continue;
      if (now - deploy.mtime < GRACE_MS) continue; // 1-hour grace
      if (now - deploy.mtime < 7 * 86_400_000) continue; // 7-day age

      // 3. Final alias re-check immediately before delete. If it changed
      //    between step 2 and now (another promote fired), skip this deploy.
      const currentProd = await readAlias(`${site}/production`);
      const currentPreview = await readAlias(`${site}/preview`);
      if (deploy.id === currentProd || deploy.id === currentPreview) continue;

      if (input.dry_run) {
        report.pending.push({ site, deployId: deploy.id, mtime: deploy.mtime });
      } else {
        await deletePrefix(`${site}/deploys/${deploy.id}/`);
        report.deleted.push({ site, deployId: deploy.id });
      }
    }
  }
} finally {
  releaseLock(LOCK_KEY, instanceId);
}
```

**Lock semantics:**

- Lock key: `universe-static-apps-01/_ops/cleanup.lock`
- Content: JSON `{instanceId, acquiredAt, expiresAt}`.
- Acquire: read current lock, if absent or `expiresAt < now` then PutObject with new values. S3 PutObject is atomic but not conditional (no If-None-Match in R2 S3 API); for v1 the Windmill cron is the only writer, so the lock is advisory, not mutex. If a second writer appears, add conditional-put via R2 API.
- Release: DeleteObject at end of run.

**Dry-run workflow:** the first production run MUST be `dry_run: true`. Operator reviews the `pending` deletion list in Slack/Chat. Only after a clean review does the cron flip to `dry_run: false` (via Windmill variable).

### 4.10 Module Loading in Caddy

Caddy loads the `r2_alias` module at startup via the build-time import. The `UnmarshalCaddyfile` parses the directive tokens from the Caddyfile syntax. The module registers itself via:

```go
func init() {
    caddy.RegisterModule(R2Alias{})
    httpcaddyfile.RegisterHandlerDirective("r2_alias", parseCaddyfile)
}
```

Ordering is set globally in the Caddyfile (`order r2_alias before file_server`) so the user does not need per-route directives.

---

## 5. Alternatives Considered

### 5.1 (D1) CLI uploads directly to R2 (current universe-cli)

**Approach:** Keep the existing direct-S3 upload in the CLI.
**Pros:** Simpler code path; no CI dependency; faster feedback (no pipeline queue).
**Cons:** Every developer holds R2 credentials; a stolen laptop is a production-bucket compromise. Hard to rotate. Hard to audit. Violates the "no R2 keys for devs" user directive explicitly set in brainstorming.
**Rejected** per user directive.

### 5.2 (D2) Build on developer machine, upload artifacts

**Approach:** Developer runs `npm run build` locally; CLI uploads `dist/` to Woodpecker or to R2 staging.
**Pros:** Faster iteration — no "wait for Woodpecker to clone + install + build."
**Cons:** Non-reproducible builds (local node version, env, cache differ). Developer still needs a credential to push the tarball somewhere. Diverges from Netlify/Vercel model.
**Rejected.** CI is the single source of truth. Fast local iteration is handled by `docker compose up` per ADR-007, not by deploying local builds.

### 5.3 (D3) Hot disk + R2 fallback (ADR-007 as originally written)

**Approach:** Caddy serves from local SSD primary; R2 fallback on miss; rclone sidecar syncs on deploy trigger.
**Pros:** Lowest origin latency for warm requests. Matches ADR-007 literally.
**Cons:** More moving parts (rclone or targeted copy, agent on pod, ConfigMap or equivalent alias state). Caches and origins can disagree. Sync failures are silent.
**Rejected.** Cloudflare CDN absorbs the vast majority of requests; origin-to-R2 latency is not meaningfully worse than origin-to-local-SSD when both sit in FRA1. Can be added later (two-way door) if profiling shows origin latency is a real problem.

### 5.4 (D4) Use an existing Caddy plugin (caddy-s3-proxy, caddy-fs-s3)

**Approach:** Compose existing plugins without writing Go.
**Pros:** No owned Go code.
**Cons (draft):** Research confirmed no existing plugin supports reading an alias file then using its content as a path prefix. `caddy-s3-proxy` (lindenlab) is unmaintained (AWS SDK v1, Go 1.13, Caddy 2.6.4, last release 2021). `caddy-fs-s3` is active and in the build but cannot resolve aliases directly. `caddy-aws-transport` cannot target custom endpoints → cannot use R2.
**Initial rejection:** Scope of custom module is ~300 LOC; tractable. User confirmed willingness to maintain it given the existing xcaddy build already requires Go toolchain.

**Audit revisit (2026-04-18, post-D32).** `caddy-fs-s3`'s last release is v0.12.0 on 2026-02-01 (14 months ago at audit time). Not archived, but solo-maintainer silence through two Caddy security wave releases (2.11.1 Feb, 2.11.2 March) made D30's "14-day CVE-bump SLA" unenforceable. D32 (§5.30) resolves this by absorbing the S3 filesystem into the in-tree `r2alias` package as a sibling `caddy.fs.r2` module. D4's core thesis — "own the Go code to own the schedule" — now extends to the FS layer as well.

**Spike-revisit (post-review 2026-04-18):** The custom-module path represents 3.5 engineer-weeks (T01–T05 = Phase 0 critical path). Before committing, a 1-day spike (**T31**, beads `gxy-static-k7d.32`) validates whether `caddy-fs-s3` + Caddy built-in `map`/`rewrite`/sub-request primitives can resolve alias files using Caddyfile only. T31 produces `docs/rfc/spikes/gxy-cassiopeia-caddyfile-poc.md` with a VIABLE / VIABLE-WITH-CAVEATS / NOT-VIABLE verdict.

**Post-spike decision tree** (binds the CTO, not the spike agent):

| Verdict             | Action                                                                                                                                   |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| VIABLE              | Re-plan: cancel T01–T05; replace with a single "Package spike config as production chart" task. Update D4 to overturned.                 |
| VIABLE-WITH-CAVEATS | Re-scope T01–T05: keep alias-resolution module (~100 LOC), drop S3 serving (caddy-fs-s3 handles). Update D4 with hybrid decision.        |
| NOT-VIABLE          | Proceed with T01–T05 as planned. Update D4 with spike evidence confirming rejection — D4 becomes evidence-backed, not assumption-backed. |

T01 (`gxy-static-k7d.2`) is `blocks`-blocked by T31 in beads; dispatch will not proceed until the spike report lands.

### 5.5 (D5) Dedicated preview domain `*.preview.freecode.camp`

**Approach:** Preview URLs are `{site}.preview.freecode.camp`, e.g. `hello-world.preview.freecode.camp`.
**Pros:** Clean separation; no delimiter collisions.
**Cons:** Requires a second-level wildcard cert. Cloudflare free Universal SSL only covers `*.freecode.camp`. Cloudflare Advanced Certificate Manager at $10/mo or self-managed cert rotation.
**Rejected.** `{site}--preview.freecode.camp` costs nothing and fits the existing wildcard. The "cannot contain `--`" rule is a trivial validation.

### 5.6 (D6) ArgoCD manages alias ConfigMap

**Approach:** Alias state lives in a Kubernetes ConfigMap; Windmill flow or Woodpecker step updates it; ArgoCD syncs it.
**Pros:** GitOps-pure. All deploy state in git (if the ConfigMap is also committed).
**Cons:** Three systems coordinate on each deploy (pipeline → ConfigMap write → ArgoCD sync → Caddy reload). ArgoCD sync cycle adds 30s–3min latency. ConfigMap is mutable state masquerading as config — ArgoCD will fight imperative writes unless explicitly ignored.
**Rejected.** Aliases are state, not config. R2 is the right home for them. ArgoCD still manages Caddy's deployment, image tag, and Caddyfile — just not per-deploy alias state.

### 5.7 (D7) Woodpecker temporary on gxy-management

**Approach:** Stand up Woodpecker on gxy-management instead of provisioning gxy-launchbase.
**Pros:** Saves a cluster.
**Cons:** CI pods on gxy-management compete for RAM with ArgoCD, Windmill, Zot. Build pod failures can affect critical platform services. Moving Woodpecker later is a migration hazard.
**Rejected.** User directive: "If it means we need the launchbase first, so be it." gxy-launchbase exists for this reason per ADR-001.

### 5.8 (D8) Different bucket name (e.g. `freecodecamp-universe-static`)

**Approach:** Name the bucket after the product, not the galaxy.
**Pros:** Bucket name survives galaxy rename.
**Cons:** Loses the convention established by `gxy-static-1`. Makes galaxy ↔ bucket mapping implicit.
**Rejected.** Galaxy-suffixed naming is clearer; the `-1` suffix reserves room for future buckets if sharding is ever needed.

### 5.9 (D9) Separate pipeline files for deploy, promote, rollback

**Approach:** `.woodpecker/deploy.yaml`, `.woodpecker/promote.yaml`, `.woodpecker/rollback.yaml`.
**Pros:** Each file is simpler; easier to read.
**Cons:** 3× file count in every constellation repo. Secrets configuration triplicated. Image cache benefits diluted.
**Rejected.** Single pipeline with `OP` variable gates steps via `when: evaluate: 'env.OP == "…"'` — clearer flow, one place to grep.

### 5.10 (D10, D11) JSON alias files

**Approach:** Alias file is JSON `{"deployId": "…", "promotedAt": "…"}`.
**Pros:** Extensible; room for metadata.
**Cons:** The Caddy module has to parse JSON per-request. Plain text is simpler, atomic, and matches the current universe-cli convention.
**Rejected.** If we need more metadata, it goes in `_deploy-meta.json` at the deploy-prefix root.

### 5.11 (D12, D13) Larger nodes

**Approach:** 8vCPU/16GB nodes for both galaxies.
**Pros:** More headroom for concurrent builds and cache.
**Cons:** 2× cost. gxy-static (4vCPU/8GB) runs at ~3% CPU / ~16% RAM with real traffic (field notes 2026-04-13 — line 412).
**Rejected.** 4vCPU/8GB is proven sufficient. Room to upgrade nodes later if monitoring shows pressure.

### 5.12 (D14) Longer alias cache TTL (e.g. 60s)

**Approach:** Cache the alias for 60s instead of 15s.
**Pros:** Lower R2 request volume.
**Cons:** Deploys are not visible for up to 60s across 3 Caddy replicas. User expectation set by "thin Netlify/Vercel" is sub-30s.
**Rejected.** R2 GetObject cost is negligible at site volumes we expect. 15s is a reasonable balance.

### 5.13 (D15) Co-locate Caddy and Woodpecker in one namespace

**Approach:** `static` namespace hosts both.
**Pros:** Shorter names.
**Cons:** Mixing serving and CI violates blast-radius separation. Also Caddy and Woodpecker are on different galaxies — namespace conflation is nonsensical cross-cluster.
**Rejected trivially** — noted for completeness.

### 5.14 (D16) Cloudflare Full (Strict) TLS

**Approach:** Caddy terminates TLS with a Cloudflare Origin CA cert.
**Pros:** Encrypted link between CF and origin; stricter security.
**Cons:** Cert rotation. Caddy needs `auto_https on` with the cert loaded — more config surface. gxy-static runs Flexible today without apparent harm.
**Rejected for v1; P1 security TODO.** We accept CF-to-origin HTTP for v1 to match established baseline; harden later.

### 5.15 (D17) Tag-triggered production deploys

**Approach:** Pushing a git tag deploys to production (not just preview).
**Pros:** Integrates with semver release workflows.
**Cons:** Conflates "I cut a release" with "I am ready for users to see it." Universe staff use the promote step to decouple build from publish.
**Rejected for v1.** Can be added later as an additional `when: event: tag` trigger that sets `DEPLOY_TARGET=production`.

### 5.16 (D18) Separate repo for the Caddy module

**Approach:** `freeCodeCamp-Universe/caddy-r2-alias` standalone Go module repo.
**Pros:** Reusable beyond Universe; separable OSS artifact.
**Cons:** Two repos to coordinate; versioning concerns; xcaddy build needs external reference. Premature abstraction — the module is fCC-specific until proven otherwise.
**Rejected for v1.** Colocated with the xcaddy build in the infra repo. Extract later if there's external interest.

### 5.17 (D19) Looser site name regex

**Approach:** Allow uppercase, underscores, dots.
**Pros:** More permissive.
**Cons:** DNS labels are RFC-1123; deviations cause surprise. Uppercase is a footgun (DNS is case-insensitive but config tools may not be).
**Rejected.** Strict is safer.

### 5.18 (D20) Migrate gxy-static to the new architecture in place

**Approach:** Rewrite the gxy-static Helm chart to match gxy-cassiopeia, then cut over DNS.
**Pros:** One cluster, not two.
**Cons:** Risk a broken rewrite taking down the live site. Mixed-state window during migration. Larger change surface.
**Rejected per user directive.** Green-field gxy-cassiopeia is cleaner and reversible via DNS.

### 5.19 (D21) SQLite-on-PVC for Woodpecker persistence

**Approach:** Back the Woodpecker server with SQLite on a `local-path` PVC. Single-file DB, simple, no operator.
**Pros:** No CNPG operator install; fewer moving parts at bootstrap.
**Cons:** The PVC binds to a specific node. Node failure → pod cannot reschedule. All pipeline history, user tokens, repo activation state live on one disk. The "migrate to CNPG if unstable" posture is reactive: by the time instability is observed, data is lost. `etcd` snapshots cover cluster state, not application PVC data.
**Rejected.** CNPG at bootstrap is a one-time setup cost that pays back on the first node failure. Cross-galaxy data durability is part of the platform's job, not a follow-up.

### 5.20 (D22) Org-scope R2 credentials

**Approach:** Single R2 access key pair available as Woodpecker org secrets, used by every constellation pipeline.
**Pros:** One credential to provision and rotate.
**Cons:** A compromised build dependency in ANY constellation can exfiltrate the org-scope credential. That credential has write access to ALL deploys in the bucket, meaning one compromised repo → every site is overwritable. Supply-chain attacks against static sites commonly target exactly this (pre-install/post-install hooks in npm packages).
**Rejected.** Per-repo R2 credentials with [path conditions](https://developers.cloudflare.com/r2/api/tokens/) bound to `{site}/*` limit blast radius. Onboarding cost is a Windmill flow. Rotation cost is a Windmill flow. Correctness cost to the attacker: they can only corrupt the site they compromised, not the fleet.

### 5.21 (D23) Admin API on all interfaces

**Approach:** `admin :2019` binds Caddy's admin API on all pod interfaces (default Caddyfile pattern for many examples).
**Pros:** Remote admin access (e.g. via port-forward or cluster-internal tooling).
**Cons:** Any in-cluster pod (including compromised sidecars in other workloads) can POST config to Caddy and take over serving. The NetworkPolicy gap that allowed this in the initial draft is a concrete CVE-class risk.
**Rejected.** `admin 127.0.0.1:2019` restricts admin to the pod's loopback. Operators reach it via `kubectl exec` for diagnostics — an explicit, audited access path.

### 5.22 (D24) Write alias, then smoke-test, with no revert

**Approach:** Pipeline writes alias, then purges cache, then smoke-tests. If smoke-test fails, pipeline fails but alias stays broken. Operator manually fixes.
**Pros:** Linear pipeline, fewer steps.
**Cons:** Failed promote leaves production broken. Manual remediation takes minutes. The very failure mode §2 describes as unacceptable (site 404s during alias gaps) is reintroduced here — just triggered by smoke failures instead of rclone gaps.
**Rejected.** The pipeline snapshots the previous alias, flips, smoke-tests, and explicitly reverts on failure. The added steps are cheap (~5s each). First-deploy failures (no previous alias) hit a hard-stop with alerting; rare but bounded.

### 5.23 (D25) Informal DNS cutover checklist

**Approach:** Free-form checklist in the FLIGHT-MANUAL; operator verifies each site before DNS change.
**Pros:** Minimal scripting.
**Cons:** Human error at the worst possible moment. "All sites migrated" is a claim with no verification; a missed site 404s post-cutover. During stress (cutover window), people miss steps.
**Rejected.** `just cutover-preflight` is a shell script that enumerates sites in `gxy-static-1`, runs 8 checks per site, and exits non-zero on any failure. Green output is the only gate to cutover.

### 5.24 (D26) Immediate gxy-static decommission after 7-day soak

**Approach:** Original draft planned 7-day soak then user-led decommission.
**Pros:** Cost savings ($96/mo droplet × 3 = $288/mo).
**Cons:** 7 days is too short for regressions with slow blast radius (e.g., a gradual memory leak in the Caddy module that manifests at 14 days under production load). Once gxy-static is decommissioned, DNS revert has no target.
**Rejected for 30 days.** The decommission window is pushed to 30 days minimum post-cutover. $288/mo × 1 month is cheap insurance against an irreversible cutover regression.

**Known limitation (post-review 2026-04-18):** The "rollback substrate" is a DNS-level availability fallback, not a content-parity guarantee. See §6.9.1 for the caveat. A future RFC may introduce dual-target writes during the soak (tracked as §5.24.1 placeholder below) to close the content gap, but M1 ships with the caveat documented and runbook-enforced.

#### 5.24.1 Dual-target writes during soak (DEFERRED)

**Approach (not adopted for M1):** During the 30-day soak, the Woodpecker pipeline writes every successful deploy to BOTH universe-static-apps-01 AND gxy-static-1, keeping gxy-static in content parity so that rollback is fully transparent.
**Pros:** Rollback is a true rollback (no content regression).
**Cons:** Doubles R2 write cost during soak (~30 days × N deploys × 2); doubles pipeline step complexity (T21); requires gxy-static pipelines to accept the new deploy format (possible regression in itself); and delays M1 by 1–2 weeks.
**Deferred.** Cost of the content gap is tolerated for M1 in exchange for ship speed; revisit after first real post-cutover incident informs the trade-off. Filed as follow-up: "RFC gxy-cassiopeia §5.24.1 — dual-target writes" after M1 ships.

### 5.25 (D27) Unbounded sync.Map cache

**Approach:** Use `sync.Map` for alias caching — simple, no dependencies.
**Pros:** Zero dependency; idiomatic Go stdlib.
**Cons:** `sync.Map` has no size primitive — cannot bound. Host header is attacker-controlled; a subdomain-scan attack seeds arbitrary entries until OOM. The module's 512Mi limit is easily exhausted.
**Rejected.** `hashicorp/golang-lru/v2/expirable` provides bounded LRU with TTL. `golang.org/x/sync/singleflight` prevents cache-miss stampedes. Both are well-vetted; minor dependency cost.

### 5.26 (D28) Cleanup cron without lock or grace window

**Approach:** Cron reads aliases, deletes anything > 7 days old not in the alias set.
**Pros:** One query, one delete loop.
**Cons:** Between the alias read and the delete, a promote can flip the alias to point at a deploy the cron is about to delete. The 7-day age filter does NOT help because a freshly promoted deploy can be any age — its mtime at the deploy prefix is the original upload time, not the alias-flip time.
**Rejected.** R2 lock + 1-hour grace (no delete of anything modified in the last hour) + immediate pre-delete alias re-check closes the race. Dry-run mode on first run prevents a first-time cron bug from destroying history.

### 5.27 (D29) Unrestricted origin ingress

**Approach:** Caddy accepts traffic from any IP, relying on Cloudflare proxy for access control.
**Pros:** Simple NetworkPolicy.
**Cons:** Cloudflare proxy hides origin IPs only if the IPs were never exposed. Historical DNS (before proxy was enabled) leaks origin IPs permanently. Attackers with origin IPs can send `Host: <any-site>.freecode.camp` directly and enumerate bucket content by probing for 200 responses. Not catastrophic (content is public anyway), but leaks the site list and reveals pre-prod preview content.
**Rejected.** Allow-list Cloudflare's published IP ranges (`https://www.cloudflare.com/ips-v4/`) at the Cilium ingress layer. Weekly refresh via Windmill cron.

### 5.28 (D30) Caddy base image pin — version and CVE-driven bump policy

**Approach A:** `FROM caddy:2-builder` — track any 2.x release.
**Pros:** Automatic Caddy updates on rebuild.
**Cons:** Non-reproducible builds. A minor Caddy release introducing a module API change breaks the custom module silently on the next image build. Debugging "why does the image build fail now when it built fine last month" is painful.

**Approach B (original draft):** Pin `caddy:2.8-builder` and `xcaddy build v2.8.4`.
**Pros:** Full reproducibility.
**Cons:** Caddy 2.8.x was superseded by 2.9/2.10/2.11 and carries unpatched 2026 CVEs (CVE-2026-27585 file-matcher backslash bypass, CVE-2026-27587 MatchPath %xx bypass, CVE-2026-27588 MatchHost case-sensitivity bypass). Shipping 2.8.4 to production is non-starter.
**Rejected** after review (2026-04-18): pinning to a vulnerable release is worse than the debugging cost it was meant to avoid.

**Approach C (adopted):** Pin to the current CVE-patched stable. `FROM caddy:2.11-builder` + `xcaddy build v2.11.2` (2026-03-06 release). Bumping is a PR with regression tests, a CVE/changelog read, and a T04 integration re-run (against Adobe S3Mock per §11.2 post-audit).
**Policy:** When a Caddy security release lands, the pin MUST be bumped within 14 days (or sooner if the CVE affects a handler or matcher used by gxy-cassiopeia). Tracked by a recurring Windmill reminder (filed as follow-up after Phase 6 exit, not a blocker for M1).
**Audit revision (2026-04-18):** The original wording pinned `caddy-fs-s3@v0.12.0` alongside Caddy. That dep is dropped per D32 (§5.30) — the image now contains only `caddy-core` + our in-tree `r2alias` module. The 14-day SLA is enforceable again because we control every component on the build line.
**Adopted.**

### 5.29 (D31) No alerts at v1

**Approach:** Full alerting waits for gxy-backoffice.
**Pros:** Zero v1 setup cost.
**Cons:** The motivation §2 is precisely that undetected 404 storms on gxy-static triggered this RFC. Shipping gxy-cassiopeia with zero alerting repeats the mistake; the first incident goes undetected until a user complains.
**Rejected.** Cloudflare Notifications (zero infrastructure, configured via CF API) + Uptime Robot (free tier) provide zone-level 5xx alerts, origin error alerts, per-site uptime, and Woodpecker API health — all with no gxy-backoffice dependency. Deferred alerts remain deferred, but the minimum floor is non-negotiable.

### 5.30 (D32) Merge S3 filesystem into r2_alias — drop caddy-fs-s3 (2026-04-18 audit)

**Approach A (original D30):** Use `sagikazarmark/caddy-fs-s3@v0.12.0` for the filesystem backend + in-tree `r2alias` module for alias resolution. Two Caddy plugins, one image.
**Audit trigger (2026-04-18):** Dispatch of T04 (integration tests) surfaced that the test harness depended on MinIO, which was archived on 2026-02-12. Widening the scope to every third-party dep caught `caddy-fs-s3` at v0.12.0 (2026-02-01) with no activity since — 14 months stale. Not archived, but solo-maintainer silence through the Caddy 2.11.1 / 2.11.2 security waves made the D30 "14-day CVE-bump SLA" unenforceable in practice.

**Approach B (fork `freeCodeCamp-Universe/caddy-fs-s3`):** Take ownership via fork, absorb upstream maintenance burden (~500 LOC + AWS SDK upkeep + Caddy-API upkeep).
**Pros:** Minimal change to D30 wiring.
**Cons:** Fork maintenance surface is roughly the same as writing the module ourselves, without the benefit of shared config + shared S3 client + shared cache with `r2_alias`.

**Approach C (adopted):** Register a second Caddy module `caddy.fs.r2` from the same Go package as `r2_alias`. ~150 LOC (fs.FS + fs.StatFS + Caddyfile unmarshaller + Provision) + tests. Shared config conventions; shared AWS SDK client initialization; optional shared object cache for hot-path objects (deferred — alias cache already bounds misses).
**Pros:** No third-party Caddy plugins; entire serving path is one Go package we own; D30 SLA enforceable again; vendor-neutrality tenet preserved.
**Cons:** ~150 LOC of new production code to maintain; tests of fs.FS behavior need Adobe S3Mock (part of T04's new harness anyway).
**Adopted.**

**Migration impact:**

- T01–T03 (`r2alias` middleware handler) — unchanged. No refactor.
- T01b (new) — implements `R2FS`, `caddy.fs.r2` registration, Caddyfile grammar.
- T04 (integration tests) — uses Adobe S3Mock instead of MinIO; tests exercise the `r2_alias` + `caddy.fs.r2` pipeline end-to-end.
- T05 (Dockerfile + xcaddy build) — drops `--with github.com/sagikazarmark/caddy-fs-s3@v0.12.0`; adds only the in-tree module.
- §4.5.4 ConfigMap — `filesystem r2 r2 { ... }` (module name `r2` in our namespace) instead of `filesystem r2 s3 { ... }`.

Corresponding ADR update (if any) belongs to the Universe team; this RFC records the implementation decision only.

---

## 6. Migration and Rollout Strategy

### 6.1 Phase Gates

The rollout is 7 phases. Later phases depend on earlier ones. Any phase can be paused; no phase mutates live production traffic until Phase 6.

| Phase | Name                                      | Mutates Prod? | Reversible?               |
| ----- | ----------------------------------------- | ------------- | ------------------------- |
| 0     | Prep: module + image build                | No            | Yes (no deploy)           |
| 1     | Provision gxy-launchbase                  | No            | Yes (teardown playbook)   |
| 2     | Deploy Woodpecker                         | No            | Yes (helm uninstall)      |
| 3     | Provision gxy-cassiopeia                  | No            | Yes (teardown playbook)   |
| 4     | Deploy Caddy + R2 bucket                  | No            | Yes (helm uninstall)      |
| 5     | universe-cli v0.4 release                 | No            | Yes (pin to v0.3.x)       |
| 6     | DNS cutover (gxy-static → gxy-cassiopeia) | **Yes**       | Yes (revert DNS; 60s TTL) |
| 7     | Confirm + decommission window             | No            | N/A                       |

### 6.2 Phase 0: Prep (infra repo only)

- Write `r2_alias` module (§4.3.4 interface contract).
- Update `Dockerfile` (§4.3.8).
- Build image locally and tag `ghcr.io/freecodecamp-universe/caddy-s3:dev-<sha>`.
- Unit tests pass (§11.1).
- Image pushed to GHCR.
- **Exit criterion:** `kubectl run -it --rm --image=<tag> caddy:dev -- caddy list-modules | grep r2_alias` succeeds.

### 6.3 Phase 1: Provision gxy-launchbase

- Add `gxy_launchbase_k3s` group_vars (§4.1.1).
- ClickOps: provision 3× s-4vcpu-8gb-amd in DO FRA1 with `cloud-init/k3s-node.yaml`, tagged `_gxy-launchbase-k3s`.
- `just play k3s--bootstrap -e "target_hosts=gxy_launchbase_k3s"` (recipe name TBD per justfile review).
- Verify `kubectl get nodes` shows 3 Ready nodes.
- **Exit criterion:** Cluster responds to `kubectl version`, etcd snapshots uploading to S3.
- **Note:** Hetzner migration is deferred to post-M5 (see §13). When the Hetzner account is provisioned, a follow-up spike adds `ansible/inventory/hetzner.yml`, the `hetzner.hcloud` collection, and the single-node cloud-init parity dry-run.

### 6.4 Phase 2: Deploy Woodpecker

- Add `k3s/gxy-launchbase/apps/woodpecker/` with Helm chart pin, values, secret overlay.
- Register GitHub OAuth app; inject OAuth secrets via sops.
- `just helm-upgrade woodpecker`.
- Configure forge for `freeCodeCamp-Universe` org.
- Create org-scoped R2 secrets via `just woodpecker-secrets-apply`.
- Add DNS record `woodpecker.freecodecamp.net` → gxy-launchbase IPs.
- **Exit criterion:** Signing in as a platform-team member works; a dummy test pipeline runs end-to-end.

### 6.5 Phase 3: Provision gxy-cassiopeia

- Add `gxy_cassiopeia_k3s` group_vars (§4.1.2).
- ClickOps: provision 3 s-4vcpu-8gb-amd in DO FRA1.
- `just play k3s--bootstrap -e "target_hosts=gxy_cassiopeia_k3s"`.
- Verify 3 Ready nodes, etcd snapshots uploading.
- **Exit criterion:** Cluster responds to `kubectl version`.

### 6.6 Phase 4: Deploy Caddy and Provision R2

- Create R2 bucket `universe-static-apps-01` in Cloudflare UI.
- Create R2 access keys (1 rw for Woodpecker, 1 ro for Caddy).
- Store keys in `infra-secrets/gxy-cassiopeia/` as sops-encrypted yaml.
- Add `k3s/gxy-cassiopeia/apps/caddy/` chart (§4.5.2).
- `just helm-upgrade caddy` on gxy-cassiopeia.
- Verify Caddy pods Ready; `/healthz` responds 200.
- Manually upload a test site (via a throwaway Woodpecker job) to `universe-static-apps-01/test.freecode.camp/deploys/<id>/` + write `test.freecode.camp/production` alias.
- Add temporary DNS: `test.freecode.camp` → one gxy-cassiopeia node IP.
- `curl -H "Host: test.freecode.camp" http://<nodeIP>` returns the test page.
- `curl -H "Host: test--preview.freecode.camp" http://<nodeIP>` returns 404 (preview alias absent — expected).
- Upload preview content + write `test.freecode.camp/preview` alias; preview URL now returns 200.
- Delete test site; remove temporary DNS.
- **Exit criterion:** Smoke test against a real R2-backed site works through the full chain.

### 6.7 Phase 5: universe-cli v0.4

- Implement changes in §4.8.
- Unit + integration tests pass (§11).
- Release as `@freecodecamp/universe-cli@0.4.0-beta.1`.
- Platform team installs and smoke-tests against a new repo `freeCodeCamp-Universe/hello-world-cassiopeia`.
- **Exit criterion:** Full deploy/promote/rollback cycle works end-to-end from the CLI.

### 6.8 Phase 6: DNS Cutover

#### 6.8.1 Preflight (`just cutover-preflight`)

A machine-checked checklist (D25). DNS MUST NOT be changed until every item returns green. Ships as a justfile recipe wrapping a shell script in `scripts/cutover-preflight.sh`.

The script performs, for every site present in `gxy-static-1`:

| Check                                                                  | How                                                                                      | Pass criterion                                         |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| Site exists in `universe-static-apps-01`                               | `rclone lsd r2:universe-static-apps-01/<site>/deploys/`                                  | At least one `deploys/<id>/` prefix exists             |
| `production` alias exists in `universe-static-apps-01`                 | `rclone cat r2:universe-static-apps-01/<site>/production`                                | Returns a deploy ID matching `^[A-Za-z0-9._-]{1,64}$`  |
| Alias target exists                                                    | `rclone lsf r2:universe-static-apps-01/<site>/deploys/<id>/index.html`                   | File exists                                            |
| HTTP 200 via cassiopeia origin (host header + direct IP)               | `curl -sSI -H "Host: <site>" http://<gxy-cassiopeia-node>/`                              | Status 200                                             |
| HTTP 200 via cassiopeia origin for preview (if a preview alias exists) | `curl -sSI -H "Host: <site-short>--preview.freecode.camp" http://<gxy-cassiopeia-node>/` | Status 200                                             |
| Constellation is registered with Woodpecker                            | `woodpecker-cli repo info freeCodeCamp-Universe/<site>`                                  | Exit 0                                                 |
| Constellation has R2 secrets set in Woodpecker                         | `woodpecker-cli repo secret ls freeCodeCamp-Universe/<site>`                             | Contains `r2_access_key_id` and `r2_secret_access_key` |
| Site name passes validation                                            | Run validation regex from §4.8.5                                                         | Match                                                  |

The script exits non-zero on any failure and prints a per-site matrix. Cutover is gated: if `just cutover-preflight` fails, the operator fixes the failing sites and re-runs. No cutover without green.

#### 6.8.2 Execution

1. Announce a 1-hour quiet window to staff — **no promotes, no rollbacks, no new deploys**.
2. Run `just cutover-preflight`. **Must return green.** Halt if any site fails.
3. Take snapshots (for rollback): export current Cloudflare DNS records for `freecode.camp` via `just cf-dns-export freecode.camp > /tmp/cutover-dns-pre.json`.
4. In Cloudflare, replace `*`, `@`, `www` A records for `freecode.camp` from gxy-static IPs to gxy-cassiopeia IPs. Use `just cf-dns-cutover freecode.camp gxy-cassiopeia` (wraps Cloudflare API). TTL is already 1m.
5. Watch gxy-cassiopeia Caddy logs for incoming traffic (`kubectl logs -n caddy -l app.kubernetes.io/name=caddy -f`).
6. Watch gxy-static Caddy logs for traffic fall-off.
7. Watch the Cloudflare dashboard 5xx and edge-origin error panels for `freecode.camp`.

#### 6.8.3 Rollback

If step 5–7 surface a problem within 15 minutes of cutover:

1. Re-import the pre-cutover snapshot: `just cf-dns-restore /tmp/cutover-dns-pre.json`.
2. Actual DNS revert for proxied records is typically < 60s but is NOT guaranteed — test during Phase 4 on a temporary `cutover-test.freecode.camp` record and document the observed time in field notes. Set staff communication to "expect 1–5 min revert window."
3. Preserve gxy-cassiopeia pod/logs state for postmortem before any remediation.

#### 6.8.4 Exit Criterion

15 minutes of steady traffic on gxy-cassiopeia with:

- No 5xx spikes (CF dashboard zone 5xx rate < 0.5%).
- Apex (`freecode.camp`) and `www` redirects returning 302 to `www.freecodecamp.org`.
- Every site in the preflight matrix returning 200 on its canonical `*.freecode.camp` host.
- gxy-cassiopeia Caddy pod memory < 50% of limit.

### 6.9 Phase 7: Confirm and Decommission Window

- Run gxy-cassiopeia as sole traffic origin for a minimum of **30 days** post-cutover (D26, §5.24).
- **gxy-static MUST stay live during that 30-day window** to serve as a **limited rollback substrate**. If a gxy-cassiopeia regression surfaces during day 1–30, `just cf-dns-restore` reverts DNS to gxy-static and traffic continues.
- Daily health check: run `just cutover-preflight` (§6.8.1) against gxy-cassiopeia to detect alias/deploy drift.
- Monitor metrics (§9). Minimum viable alerts (§10.3) must be active.
- After day 30: user-led decommission of gxy-static. Decommission steps are out of scope for this RFC but MUST include (a) exporting the gxy-static R2 bucket manifest for historical reference, (b) torn-down droplets imported out of OpenTofu state, (c) DNS cleanup verification that no records still reference gxy-static IPs.
- **Non-decommission window:** between the 30-day soak and user-initiated decommission, gxy-static is a passive rollback target — no deploys go to it, but it keeps serving its last-known state.

#### 6.9.1 Rollback content-parity caveat (CRITICAL)

The "rollback substrate" guarantees **DNS-level availability**, not **content parity**. During the 30-day window, all new deploys flow exclusively to `universe-static-apps-01`; `gxy-static` is frozen at cutover-day state. A day-N rollback (N > 1) therefore serves the cutover-day snapshot, not the latest deploys — every constellation that shipped between cutover and day N silently regresses to older content.

**Operators invoking rollback MUST:**

1. Announce the rollback window and the regression (platform-team + all constellation owners in scope).
2. Track constellations that deployed between cutover and rollback via `woodpecker pipeline list --after <cutover-date> --status success --repo <constellation>`; these are the regressed sites.
3. Require site owners to re-deploy to gxy-static _during the rollback_, using the pre-Phase-2 legacy path, OR accept the content regression until gxy-cassiopeia is repaired and DNS re-flipped.
4. Mirror-deploy mitigation (deferred, §5.24.1): a follow-up RFC may introduce dual-target writes in the Woodpecker pipeline to keep gxy-static in content parity during the soak; not in scope for M1.

This caveat MUST be included verbatim in the `just cf-dns-restore` output and in `docs/runbooks/dns-cutover.md` §Rollback (T25 acceptance).

### 6.10 Rollback Plan

| Failure                                     | Rollback                                                                           | Content impact                         |
| ------------------------------------------- | ---------------------------------------------------------------------------------- | -------------------------------------- |
| Custom module crashes Caddy in Phase 4      | `helm rollback` to pre-deployment snapshot                                         | None (pre-cutover)                     |
| Caddy OOM under load in Phase 6             | DNS revert to gxy-static (60s)                                                     | Cutover-day snapshot only (§6.9.1)     |
| Alias cache returns stale deploy in Phase 6 | DNS revert; investigate in sandbox                                                 | Cutover-day snapshot only (§6.9.1)     |
| Woodpecker pipeline corrupts R2 bucket      | Restore from R2 versioning (if enabled — see §7.4); otherwise redeploy from source | Affected site only; no DNS flip needed |

Every row that says "DNS revert" inherits the §6.9.1 content-parity caveat. DNS revert is fast; content re-synchronization is not.

---

## 7. Protection Section

### 7.1 Stable Interfaces

These must NOT change without a follow-up RFC:

- **R2 key layout.** `{site}/deploys/{deploy-id}/*`, `{site}/production`, `{site}/preview`. The `_deploy-meta.json` filename, location, and JSON schema are also stable.
- **Alias file format.** Plain text, single line, UTF-8, deploy-ID only. Adding JSON would break the Caddy module.
- **Deploy ID regex.** The module accepts `^[A-Za-z0-9._-]{1,64}$`. The CLI produces `^\d{8}-\d{6}-([a-f0-9]{7}|dirty-[a-f0-9]{8})$`. Widening the CLI regex is safe; narrowing the module regex is not (it will 404 existing deploys).
- **Caddy module directive syntax.** `r2_alias { bucket… endpoint… }` is the public surface. Adding options is additive; renaming or removing is breaking.
- **Woodpecker pipeline variable names.** `OP`, `DEPLOY_TARGET`, `ROLLBACK_TO`. CLI depends on these.
- **Pipeline file path.** `.woodpecker/deploy.yaml` in each constellation repo.
- **universe-cli config schema.** The `woodpecker.endpoint` and `woodpecker.repo_id` fields.

### 7.2 Invariants

These must hold before and after any change to this system:

- **No R2 credentials on developer machines.** Any change that reintroduces direct R2 access from universe-cli is a protocol violation.
- **Alias writes are atomic.** No partial reads ever. (S3 PutObject guarantee on R2.)
- **Immutable deploys.** Once `{site}/deploys/{id}/*` is uploaded, it is never overwritten. Promote/rollback repoints aliases only.
- **Deploy prefix must exist before alias is written.** Woodpecker's `write-alias` step verifies with `rclone lsf` before writing.
- **No shared state between sites.** Site A's deploys never read/write Site B's keys.
- **404 on missing alias, not 500.** A dead site is "not found," not an error.

### 7.3 Migration Constraints

- **`universe-cli ≥ 0.4.0` is required** for gxy-cassiopeia. Older versions attempt direct R2 upload and will fail with credential-not-found errors.
- **Constellations existing on gxy-static** must re-deploy to universe-static-apps-01 before DNS cutover, or they 404 post-cutover.
- **`gxy-static` is not deleted by this RFC.** Decommission is the user's decision.

### 7.4 Data Integrity Guards

- R2 bucket versioning: **enable** during Phase 4 provisioning. Reduces blast radius of a bad cleanup cron or malicious overwrite to 30-day undelete window (R2's default version retention).
- Cleanup cron (§4.9) dry-run mode: on first deploy, runs with `DRY_RUN=true`, prints the deletion list, does not delete. Enable deletions only after one dry-run review.

---

## 8. Security Considerations

### 8.1 Credential Flow

| Credential                       | Lives in                         | Exposed to                                         | Rotation                                                                      |
| -------------------------------- | -------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------- |
| R2 rw access key (per-site, D22) | infra-secrets (sops) per site    | Woodpecker (repo-scoped secret for that site only) | 90 days; Windmill flow mints new token + updates sops + applies via CLI.      |
| R2 ro access key (org-wide)      | infra-secrets (sops)             | Caddy pods                                         | 90 days; helm values overlay update + pod rotation.                           |
| Woodpecker API token (per-user)  | Developer env (WOODPECKER_TOKEN) | Developer shell only                               | **90 days** or immediately on laptop loss (runbook §8.6).                     |
| Cloudflare API token             | infra-secrets (sops)             | Woodpecker (org secret)                            | 90 days; scoped to `freecode.camp` zone, `#zone.cache_purge` permission only. |
| GitHub OAuth app secret          | infra-secrets (sops)             | Woodpecker server                                  | On Woodpecker admin change.                                                   |

### 8.2 Attack Surface

**Public endpoints:**

- `*.freecode.camp` → Caddy on gxy-cassiopeia. Caddy serves static files only; no upload, no code execution, no auth. Origin IPs allow-list Cloudflare ranges only (D29, §5.27).
- `woodpecker.freecodecamp.net` → Woodpecker UI on gxy-launchbase. OAuth-gated to the `freeCodeCamp-Universe` GitHub org. **Cloudflare Access with email OTP restricted to the platform-team group is a Phase 2 exit criterion (§4.2.3), not deferred.**

**Internal attack paths:**

- Compromised GitHub OAuth app → attacker can r/w all `freeCodeCamp-Universe` repos (the `repo` scope is org-wide). Compensating controls: CF Access on Woodpecker UI, org-level 2FA enforcement, audit log shipping. Target end state: GitHub App with per-repo fine-grained permissions (D28).
- Compromised Woodpecker API token → attacker can trigger pipelines for repos the token's user can access. Mitigated by 90-day rotation + laptop-loss runbook.
- Compromised rw R2 key (per-site) → attacker can only overwrite that single site's deploys. Blast radius bounded by R2 path conditions (D22). R2 versioning retains 30 days.
- Compromised ro R2 key (Caddy) → attacker can read any deployed file (public anyway). Low blast radius.
- Compromised in-cluster pod attempting lateral movement via Caddy admin API → **blocked** (D23): admin binds to 127.0.0.1:2019 and NetworkPolicy does not allow :2019 ingress.
- Direct origin access (bypass Cloudflare via leaked origin IP) → **blocked** (D29): Cilium ingress allow-lists CF IP ranges only.

**Network policy boundaries:**

- Caddy (gxy-cassiopeia): egress only to `*.r2.cloudflarestorage.com:443` + DNS (§4.5.8).
- Woodpecker server (gxy-launchbase): egress to `api.github.com:443` (forge), `*.r2.cloudflarestorage.com:443` (pipeline uploads via rclone container in pod), `api.cloudflare.com:443` (cache purge).
- Woodpecker agents: egress as required per pipeline step — restricted via `WOODPECKER_POLICY` allow-list of image registries.

### 8.3 Secret Hygiene in Pipelines

- Woodpecker masks repo-scope and org-scope secrets in logs by default. External secrets (e.g. fetched from Vault) are NOT masked — do not fetch secrets mid-pipeline.
- The `echo ${AWS_SECRET_ACCESS_KEY}` pattern in pipeline steps is **forbidden** — reviewer MUST reject any such PR.
- Pipeline steps that source `.env` MUST not `set -x` (debug mode) — it leaks env vars.
- `.env` in the workspace MUST NOT contain R2 credentials or CF API tokens — only non-sensitive variables (`OP`, `TARGET`, `SITE`, `DEPLOY_ID`, `PREVIOUS_DEPLOY_ID`, `SMOKE_OK`). R2/CF credentials are injected via `environment.from_secret` into each step, never exported to `.env`.
- Rclone config with `access_key_id=` and `secret_access_key=` is created in memory (`rclone config create`), not on disk with stashed credentials.

### 8.4 Pull Request Events

Per Woodpecker defaults, secrets are NOT available to `pull_request` events. Deploys triggered by PR builds would fail at the upload step (no R2 credentials) — acceptable: PR builds run tests, not deploys. Preview deployments per-PR are a Won't-Have-Yet.

### 8.5 Path Traversal

- The Caddy module's deploy-ID regex (`^[A-Za-z0-9._-]{1,64}$`) explicitly rejects `..` sequences. Tested in §11.1.
- Host header parsing rejects control characters; Go's `net/http` strips these upstream.

### 8.6 Developer Laptop Compromise Runbook

When a platform-team member's laptop is lost, stolen, or suspected compromised, the following actions execute in parallel — not sequentially — within 60 minutes of detection:

1. **Revoke Woodpecker API token** for that user via Woodpecker UI (`/user/tokens`) or admin-side delete.
2. **Revoke GitHub OAuth session** by removing the user's authorized OAuth grant for the Woodpecker OAuth app in their GitHub settings.
3. **Rotate all per-site R2 rw credentials** via Windmill flow `f/ops/rotate_r2_all_sites` — assumes worst case that pipelines the user could trigger have already run with exfiltration payloads.
4. **Audit Woodpecker pipeline history** for the preceding 30 days for that user's triggered pipelines; any suspicious pipeline (unusual steps, off-hours) triggers escalation.
5. **Rotate Cloudflare API token** if the user had access to it (platform team admins only).
6. **Rotate GitHub OAuth app secret** if the user had admin access to Woodpecker (full credential rotation).

Runbook canonical location: `infra/docs/runbooks/laptop-compromise.md` (added in Phase 2).

### 8.7 DoS Surface

- Caddy alias cache absorbs most R2 lookups. A request burst against a single site still costs ~1 R2 GetObject per 15s.
- Bad actor sending requests to non-existent subdomains causes cache misses; bounded LRU (10k entries) + TTL sentinels (§4.3.5) cap memory and R2 request rate.
- Cloudflare DDoS protection is upstream.
- Origin access allow-list (D29) filters direct origin traffic at L3 — attackers cannot reach Caddy without traversing CF.

---

## 9. Performance and Scalability

### 9.1 Target Envelope (v1)

- **Sites:** up to 50 concurrent static constellations.
- **Traffic:** up to 1,000 origin RPS (after Cloudflare CDN).
- **Deploy latency:** end-to-end `universe deploy` → site live < 90 seconds (p95) for a 50-file site.
- **Alias visibility:** alias change → first request returning new deploy < 30 seconds (p95) at all 3 Caddy replicas.
- **Cold origin latency:** `Caddy → R2 → response` < 200ms p95 for assets < 100 KB, measured at origin (behind CDN is much faster).

### 9.2 Scaling Strategy

- **Caddy:** **Fixed 3 replicas for v1** (one per gxy-cassiopeia node via pod anti-affinity). Static serving through R2 is I/O-bound, not CPU-bound — CPU-based HPA does not reliably trigger under realistic load patterns. Horizontal scaling decisions are manual for v1, driven by the observability signals in §10.3 (CDN miss-rate climb, origin latency climb, memory pressure). When gxy-backoffice's metrics stack lands, revisit with HPA metrics that actually reflect Caddy's load (e.g. `caddy_http_requests_total` rate, `r2alias_alias_lookups_total` rate, or pod memory). Documented in Post-M5 TODO.
- **R2 GetObject calls:** dominant cost is alias lookups. At 15s cache TTL × 3 replicas, alias lookups are at most 0.2/site/sec. 50 sites × 0.2/sec = 10 req/sec. Negligible versus R2's per-bucket rate limits.
- **Woodpecker agents:** fixed at 3 (DaemonSet). Concurrent builds cap at 6 with `WOODPECKER_MAX_WORKFLOWS=2`. If queue depth grows, increase `MAX_WORKFLOWS` per-agent or add agent Deployment replicas to each node.
- **R2 bucket:** unbounded. No sharding needed for v1.
- **Alias cache growth:** bounded LRU at 10k entries per pod (D27, §5.25). Cannot inflate under Host-scan attack beyond that capacity.

### 9.3 Performance Testing (per §11.3)

- Load test with `vegeta`: 500 RPS for 10 min against `hello-world.freecode.camp` (after CDN). Assert p95 < 100ms, no 5xx.
- Origin-only load test (bypass CDN via host header spoof): 100 RPS. Assert p95 < 200ms.
- Alias-cache stampede test: 1000 concurrent requests to a fresh (uncached) site. Assert only 1 R2 GetObject is issued.

---

## 10. Observability

### 10.1 Logs

- **Caddy access logs:** JSON format, stdout. Fields: `request.host`, `request.uri`, `request.remote_addr`, `status`, `duration`, `size`, `r2_alias.site`, `r2_alias.alias_name`, `r2_alias.deploy_id`, `r2_alias.cache_hit`.
- **Caddy error logs:** JSON, stdout. All 5xx paths include upstream R2 response codes when applicable.
- **Woodpecker pipeline logs:** persisted in Woodpecker server; retained 90 days.
- **Log shipping:** k8s stdout → kubelet → journald. Vector DaemonSet (ADR-015) ships to ClickHouse when gxy-backoffice exists. For v1, `kubectl logs` is the interface.

### 10.2 Metrics

Caddy exposes Prometheus metrics at `/metrics` on :2019 (admin port). Scrape when VictoriaMetrics exists on gxy-backoffice. For v1, metrics are sampled manually via `kubectl exec`.

Key metrics:

- `caddy_http_requests_total{handler="r2_alias", status}` — request rate by status
- `caddy_http_request_duration_seconds{handler="r2_alias"}` — latency distribution
- Custom: `r2alias_cache_hits_total`, `r2alias_cache_misses_total`, `r2alias_s3_errors_total`, `r2alias_alias_lookups_total{site, alias_name}`

### 10.3 Alerts

**Minimum viable alerting at v1 (D31, §5.29).** The motivation for this RFC is that gxy-static's 404 storms went undetected; v1 MUST NOT repeat that. Full metric-based alerting waits for gxy-backoffice, but zero-infrastructure alerting using Cloudflare-side data is active from Phase 6.

**Active at Phase 6 cutover (required):**

| Alert                      | Source                                       | Condition                                                        | Target                            | Action                              |
| -------------------------- | -------------------------------------------- | ---------------------------------------------------------------- | --------------------------------- | ----------------------------------- |
| Zone 5xx rate spike        | Cloudflare Notifications                     | 5xx rate > 1% for 5m on `freecode.camp` zone                     | Platform team email + Google Chat | Investigate; rollback DNS if needed |
| Origin unreachable         | Cloudflare Notifications (Origin Error Rate) | Origin error rate > 5% for 5m                                    | Platform team email + Google Chat | Check Caddy pods; R2 status         |
| Per-site uptime            | Uptime Robot (free tier) or CF Health Checks | `https://<site>/` returns non-200 for 2 consecutive checks       | Google Chat                       | Triage specific site                |
| Woodpecker API unreachable | Uptime Robot                                 | `https://woodpecker.freecodecamp.net/api/healthz` non-200 for 5m | Google Chat                       | Check gxy-launchbase + pod state    |

Cloudflare Notifications are configured via `just cf-notifications-apply` (adds to `infra/cloudflare/notifications.yaml`). Uptime Robot monitors are checked in to `infra/uptime-robot/monitors.yaml` and applied via `just uptime-robot-apply`.

**Deferred to gxy-backoffice (Phase 2+):** metric-based alerts using the Prometheus-style metrics from §10.2:

- `sum(rate(caddy_http_requests_total{status=~"5.."}[5m])) / sum(rate(caddy_http_requests_total[5m])) > 0.01`
- `r2alias_s3_errors_total[5m]`
- `up{job="caddy"} == 0`
- `woodpecker_queue_depth` — CI queue > 10 for 10m
- `r2alias_cache_hit_ratio` — hit ratio drop below 90% (indicates cache thrash or attack)

### 10.4 Dashboards (deferred)

Grafana dashboard `gxy-cassiopeia` with panels for: request rate by site, alias cache hit ratio, R2 error rate, Caddy pod health, Woodpecker queue depth.

---

## 11. Testing Strategy

### 11.1 Unit Tests (Caddy R2 Alias Module)

Language: Go. Framework: standard `testing` + `stretchr/testify`.

| Test case                                              | Asserts                                                |
| ------------------------------------------------------ | ------------------------------------------------------ |
| Host → site + alias parsing (production)               | Correct split for `hello-world.freecode.camp`          |
| Host → site + alias parsing (preview with `--preview`) | Correct split for `hello-world--preview.freecode.camp` |
| Host without `root_domain` suffix                      | Returns 404 (not a configured root domain)             |
| Alias file valid deploy ID                             | Path rewritten correctly                               |
| Alias file with `..` in ID                             | 404 (path traversal rejected)                          |
| Alias file > 64 chars                                  | 404 (regex violation)                                  |
| Alias file empty                                       | 404                                                    |
| Alias file with trailing whitespace                    | Whitespace trimmed; valid                              |
| R2 returns 404 on alias                                | 404 to client; "missing" sentinel cached               |
| R2 returns 500 on alias                                | 503 to client; no cache                                |
| R2 returns 500 on file fetch                           | 503 to client                                          |
| Cache TTL boundary                                     | 15s after lookup, cache is invalidated                 |
| Cache concurrent stampede                              | Only one R2 call even with 1000 concurrent requests    |
| Caddyfile UnmarshalCaddyfile                           | All directive tokens parsed                            |

Target coverage: ≥ 85% statement coverage on the module.

### 11.2 Integration Tests (Go + testcontainers)

Run the full Caddy binary against an Adobe S3Mock container (`adobe/s3mock` — Apache 2.0, purpose-built for test harnesses) populated with test deploys. Hit `curl localhost:…` with various Host headers. Assert response content matches expected deploys.

**Dependency rationale (2026-04-18 audit).** The original draft specified MinIO. MinIO archived the community edition on 2026-02-12; Docker images stopped shipping in Oct 2025. Adobe S3Mock is the replacement: single-purpose S3 API mock, testcontainer-ready (Java backend, small image), actively maintained, Apache 2.0. LocalStack was considered but archived its public repo on 2026-03-23. See infra field notes §"Dependency audit" (2026-04-18) for the full evaluation.

Tests exercise both the `r2_alias` middleware (path rewrite) AND the `caddy.fs.r2` filesystem (object read) on the same Caddy instance — since D32, they live in the same Go package.

### 11.3 End-to-End Tests (Bash + Woodpecker sandbox)

- Spin up the Phase 4 test bucket (`universe-static-apps-01` with temp DNS on `test.freecode.camp`).
- Run `universe deploy --json` from a fixture repo; parse output for pipeline number.
- Poll pipeline status via Woodpecker API; assert completes within 90s.
- `curl https://test--preview.freecode.camp` returns expected content.
- Run `universe promote`; poll; `curl https://test.freecode.camp` returns the same content.
- Run `universe rollback --to <prev-id>`; assert production content changes back.

### 11.4 Load Tests

Documented in §9.3. Run during Phase 4 exit criterion.

### 11.5 Chaos / Failure-Mode Tests (Phase 4)

- Delete R2 alias file mid-load test → expect 404, not 500.
- Kill one Caddy pod → expect <5s recovery via k8s probes.
- Kill all 3 Caddy pods → expect traffic resumes when pods return; CDN serves cached during outage.
- Rotate R2 credentials mid-flight → Caddy picks up new creds on next pod restart (ConfigMap/Secret updates restart pods via `checksum/caddyfile` annotation).

### 11.6 Golden Path Manual Test (Phase 6 exit)

1. `git clone freeCodeCamp-Universe/hello-world-cassiopeia && cd hello-world-cassiopeia`
2. Edit `src/index.html`
3. `git commit -am 'update title' && git push`
4. Watch Woodpecker pipeline auto-trigger.
5. Visit `https://hello-world--preview.freecode.camp` — new title visible within 30s.
6. `universe promote`
7. Visit `https://hello-world.freecode.camp` — new title visible within 30s.
8. Old deploys remain in `universe-static-apps-01/hello-world.freecode.camp/deploys/`; alias files point to latest.
9. `universe rollback --to <old-id>`
10. Visit `https://hello-world.freecode.camp` — old title visible within 30s.

---

## 12. Dependencies and Risks

### 12.1 Dependencies

- **DigitalOcean account** with API token for gxy-launchbase and gxy-cassiopeia provisioning.
- **Cloudflare account** with API token (cache purge scope) for Woodpecker secrets.
- **GitHub OAuth app** under `freeCodeCamp-Universe` org.
- **Hetzner Cloud account** (post-M5 only) for gxy-launchbase migration; `hetzner.hcloud` Ansible collection deferred with it.
- **Woodpecker Helm chart v3.13.x.**
- **Caddy v2.11.2** (xcaddy build already in use). No third-party Caddy plugins — the `r2alias` module (both `http.handlers.r2_alias` and `caddy.fs.r2`) lives in-tree per D32.
- **Adobe S3Mock** (`adobe/s3mock`) — test harness only, replaces MinIO per 2026-04-18 audit.
- **`rclone/rclone:1.70.0`** Docker image for pipeline steps.
- **`@aws-sdk/client-s3` v3.x** — REMOVED from universe-cli runtime deps (still used by test fixtures).
- **GHCR push access** for `ghcr.io/freecodecamp-universe/caddy-s3` image.

### 12.2 Risks

| Risk                                                             | Likelihood   | Impact                                                                     | Mitigation                                                                                                                                                        |
| ---------------------------------------------------------------- | ------------ | -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Custom Caddy module bug serves wrong deploy                      | Medium       | Site serves wrong content to end users                                     | Strict regex, unit tests, staged rollout in Phase 4 test site before Phase 6                                                                                      |
| Custom module crashes Caddy under load                           | Low          | All sites down                                                             | Go panic recovery in ServeHTTP; livenessProbe restarts pod; CDN absorbs                                                                                           |
| R2 outage (R2 SLA is 99.9% ≈ 8.76h/year)                         | Low          | Sites 503 on cache miss; cached paths OK                                   | Accepted per §3.2.7. CDN absorbs cacheable. Status page language pre-written in FLIGHT-MANUAL.                                                                    |
| Woodpecker outage                                                | Medium       | No deploys possible; serving unaffected                                    | Acceptable (Woodpecker is not in serve path). Rebuild from Helm values + CNPG backup.                                                                             |
| Alias cache staleness after deploy                               | High         | Deploy not visible for up to 15s                                           | Accepted. Matches CDN invalidation patterns. Cache purge step clears CF edge BEFORE alias flip.                                                                   |
| Cache-fill attack on alias cache (Host header scan)              | Medium       | Caddy memory inflation                                                     | Bounded LRU (10k entries) + singleflight. Attack cannot exceed cache capacity (D27).                                                                              |
| Preview SSL breaks on `{site}--preview.freecode.camp`            | Low          | Preview URL invalid cert                                                   | Validated in Phase 4 test site. Single-level wildcard confirmed.                                                                                                  |
| Deploy ID collision (same timestamp + 7-char SHA)                | Very Low     | One deploy overwrites another                                              | 7-char SHA × second-granularity timestamp. Retry in CLI if needed.                                                                                                |
| Cleanup cron deletes live deploy (TOCTOU)                        | Low          | Alias points at deleted deploy → 404                                       | R2 lock + 1-hour grace + pre-delete alias re-check (D28). Dry-run mode on first run.                                                                              |
| Woodpecker API token leak                                        | Medium       | Attacker triggers pipelines in repos                                       | Per-user 90-day rotation, revocable. Scope limited by GH perms. Incident runbook on laptop loss.                                                                  |
| Supply-chain attack via compromised build dep in one site        | Medium       | R2 writes limited to that one site                                         | **Per-repo R2 secrets (D22)** bound blast radius to single constellation, not org.                                                                                |
| DO FRA1 outage                                                   | Low          | No deploys AND sites down (shared region)                                  | DNS revert to gxy-static (still live for 30d). Hetzner migration (post-M5) separates launchbase from serving region. Long-term: multi-region.                     |
| Hetzner migration regresses CI (post-M5)                         | Low          | Temporary deploy outage                                                    | Separate epic with its own cloud-init parity dry-run, staged rollout, and gxy-static still available for rollback if mid-migration.                               |
| Woodpecker CNPG cluster loses primary                            | Low          | Brief pipeline queue stall                                                 | CNPG promotes replica automatically. WAL-archived to DO Spaces. Monthly restore drill (D21).                                                                      |
| Woodpecker v3 project stalls or pivots                           | Low          | Replacement requires CLI+template rewrite                                  | CLI's Woodpecker client is isolated in `universe-cli/src/woodpecker/` — one module to swap.                                                                       |
| caddy-fs-s3 upstream stalled (RESOLVED 2026-04-18 via D32)       | (historical) | Would have broken the 14-day CVE SLA in D30                                | **Resolved.** Absorbed S3 filesystem into the in-tree `r2alias` package as `caddy.fs.r2` (D32 §5.30). Dep removed from Dockerfile. No third-party Caddy plugins.  |
| Cloudflare cache purge API rate-limited during heavy promote day | Low          | Cache purges silently drop, stale reads                                    | CF purge has generous limits (1000/min zone-scoped); monitor via `purge-cache-pre` exit code.                                                                     |
| GitHub OAuth session compromise (before GitHub App migration)    | Low          | r/w to all freeCodeCamp-Universe repos                                     | CF Access on woodpecker domain, 2FA mandatory at org, audit log shipping. GitHub App is target end state (D28).                                                   |
| Cold site origin latency at high RPS (R2-direct, no disk cache)  | Medium       | p95 latency climbs                                                         | Cloudflare CDN handles warm traffic. If cold traffic becomes routine, reintroduce disk cache (two-way door §3.2.7). Trigger: CDN miss rate > 20% sustained.       |
| Day-N rollback serves cutover-day content (content regression)   | Medium       | Constellations that deployed during soak silently regress to stale content | DNS-level rollback only (§6.9.1). Operator must announce regression and require site re-deploys. Dual-target writes (§5.24.1) deferred. Runbook-enforced via T25. |
| Caddy CVEs unpatched on pinned version                           | Medium       | Matcher-bypass / ACL-bypass on r2_alias                                    | D30 revised (§5.28): pin to latest CVE-patched stable (2.11.2); 14-day bump SLA on security releases. Tracked by Windmill reminder cron (filed post-M1).          |
| Cache-fill attack detection lag (LRU thrash → CF 5xx hours late) | Medium       | Attack detected only via downstream CF 5xx, not origin metric              | T24 adds canary-site p95 latency alert + CF origin-response-time threshold. Primary-signal detection <5min vs hours.                                              |

---

## 13. Timeline and Milestones

Estimates in engineering-weeks. Work can parallelize across the repos; sequencing shown assumes one person per stream.

| Phase | Work                                            | Stream    | Effort | Blockers                  |
| ----- | ----------------------------------------------- | --------- | ------ | ------------------------- |
| 0     | Caddy r2_alias module + tests                   | infra     | 1w     | none                      |
| 0     | Dockerfile update + image build + GHCR push     | infra     | 0.5w   | 0a                        |
| 1     | gxy-launchbase provisioning + group_vars (DO)   | infra     | 0.5w   | none                      |
| 2     | Woodpecker Helm chart + secrets wiring          | infra     | 1w     | Phase 1                   |
| 3     | gxy-cassiopeia provisioning + group_vars        | infra     | 0.5w   | parallel with Phase 2     |
| 4     | Caddy Helm chart + R2 bucket + test deploy      | infra     | 1w     | Phases 0, 3               |
| 5a    | universe-cli Woodpecker client + deploy rewrite | cli       | 1w     | Phase 2 (Woodpecker live) |
| 5b    | universe-cli promote + rollback rewrite         | cli       | 0.5w   | 5a                        |
| 5c    | universe-cli site name validation               | cli       | 0.2w   | parallel with 5a/b        |
| 5d    | Cleanup cron (Windmill flow)                    | windmill  | 0.5w   | Phase 4                   |
| 5e    | Pipeline template `.woodpecker/deploy.yaml`     | cli/infra | 0.3w   | Phase 2                   |
| 6     | DNS cutover + confirm                           | infra     | 0.2w   | All above                 |

**Total:** ~7 weeks sequentially, ~3–4 weeks with two streams (infra + cli). Matches user "focused feature work, weeks" scope.

**Milestones:**

- **M0 (week 1):** Caddy module merged and image built.
- **M1 (week 2):** gxy-launchbase and Woodpecker live; a hello-world pipeline succeeds.
- **M2 (week 3):** gxy-cassiopeia live; test site served end-to-end via Caddy + R2 alias.
- **M3 (week 4):** universe-cli v0.4 released; full deploy/promote/rollback cycle verified.
- **M4 (week 5):** DNS cutover done; gxy-cassiopeia is production. 30-day soak window opens. gxy-static remains live as rollback substrate.
- **M5 (week 9+):** After 30-day soak completes, user decommissions gxy-static at their discretion.
- **Post-M5 (TBD, unblocked by Hetzner account):** Migrate gxy-launchbase to Hetzner CX32 FSN1 — separate epic. Adds `ansible/inventory/hetzner.yml`, `hetzner.hcloud` collection, single-node cloud-init parity dry-run, then 3-node rebuild. Keeps DO launchbase live until Hetzner is green to avoid deploy outage.

---

## 14. Open Questions

| #   | Question                                                                                      | Owner          | Due           | Blocking? / Resolution                                                                                             |
| --- | --------------------------------------------------------------------------------------------- | -------------- | ------------- | ------------------------------------------------------------------------------------------------------------------ |
| 1   | GHCR vs Zot for caddy-s3 image hosting?                                                       | Infra team     | Before M0     | Resolved: GHCR for v1; Zot deferred until Zot is live on gxy-management.                                           |
| 2   | Does the cleanup cron live on gxy-backoffice (future) or gxy-management?                      | Infra team     | Before M3     | Resolved: runs on gxy-management (where Windmill lives) for v1.                                                    |
| 3   | Should `universe history` ship in v0.4 or v0.5?                                               | CLI team       | Before M3     | Resolved: deferred to v0.5 unless implementation is trivial.                                                       |
| 4   | Woodpecker repo_id discovery — manual or automated?                                           | CLI team       | Before M3     | Resolved: manual for v1; automated via `universe register` in Phase 2.                                             |
| 5   | When does Cloudflare Access get added to `woodpecker.freecodecamp.net`?                       | Platform team  | M2 exit       | **Promoted to blocking (§4.2.3 CRITICAL #1):** CF Access with email OTP is a Phase 2 exit criterion, not deferred. |
| 6   | Migrate to Cloudflare Full (Strict) TLS?                                                      | Platform team  | Post-M5       | Not blocking — P1 security TODO.                                                                                   |
| 7   | ~~Does Woodpecker's SQLite backend survive a single-pod restart safely?~~                     | ~~Infra team~~ | ~~Before M2~~ | **Resolved by D21:** CNPG at bootstrap, no SQLite. Removed as an open question.                                    |
| 8   | GitHub App migration path for Woodpecker forge (per D28)                                      | Platform team  | Post-M5       | Not blocking v1. Target: replace OAuth app with fine-grained GitHub App; scoped per-repo permissions.              |
| 9   | When does origin-IP allow-list (D29) get reconciled against CF's published IP list?           | Infra team     | Before M4     | Resolved: weekly Windmill cron refresh; first sync done manually at Phase 4.                                       |
| 10  | Dry-run expectations for cleanup cron — how many dry-runs before flipping to `dry_run=false`? | Infra team     | Post-M4       | Resolved: minimum 2 dry-runs with clean review; then enable. Documented in FLIGHT-MANUAL.                          |
| 11  | Per-site R2 token issuance flow: Windmill flow or Terraform/OpenTofu?                         | Infra team     | Before M3     | Not blocking v1. Windmill flow for now; OpenTofu import when CF provider supports R2 tokens.                       |

All open questions are either resolved with a default for v1, blocking a specific milestone exit (Q5), or post-M5 work. None block M0 start.

---

## 15. References

### Specs and ADRs

- [ADR-001: Infrastructure and Topology](../../../../fCC-U/Universe/decisions/001-infrastructure-topology.md)
- [ADR-007: Developer Experience](../../../../fCC-U/Universe/decisions/007-developer-experience.md) — lines 166–248 are the static-stack contract this RFC implements
- [ADR-008: Data Storage](../../../../fCC-U/Universe/decisions/008-data-storage.md)
- [ADR-009: Networking and Domains](../../../../fCC-U/Universe/decisions/009-networking-domains.md)
- [Spike Plan](../../../../fCC-U/Universe/spike/spike-plan.md)
- [Infra Field Notes — Static stack drift from ADR-007 (2026-04-15)](../../../../fCC-U/Universe/spike/field-notes/infra.md)

### External Documentation

- [Woodpecker CI API Reference](https://woodpecker-ci.org/api)
- [Woodpecker CI Workflow Syntax](https://woodpecker-ci.org/docs/usage/workflow-syntax)
- [Woodpecker CI Secrets](https://woodpecker-ci.org/docs/usage/secrets)
- [Woodpecker CI Kubernetes Backend](https://woodpecker-ci.org/docs/administration/configuration/backends/kubernetes)
- [Caddy — Extending Caddy (custom modules)](https://caddyserver.com/docs/extending-caddy)
- [caddy-fs-s3 (sagikazarmark)](https://github.com/sagikazarmark/caddy-fs-s3)
- [AWS SDK for Go v2 — S3](https://pkg.go.dev/github.com/aws/aws-sdk-go-v2/service/s3)
- [Cloudflare R2 S3 API](https://developers.cloudflare.com/r2/api/s3/api/)
- [Cloudflare Purge Cache API](https://developers.cloudflare.com/api/operations/zone-purge)
- [rclone rcat reference](https://rclone.org/commands/rclone_rcat/)

### Research Findings (this spec)

- Q1: Caddy S3 proxy plugin feasibility — custom module required; existing plugins cannot do alias resolution.
- Q2: Woodpecker API — fully supports REST-triggered pipelines with variables, Bearer auth, SSE log streaming.
- Q3: Deploy without git push — "build in CI" pattern is the only one satisfying "no R2 keys on dev machines."
- Q4: gxy-launchbase sizing — 3× 4vCPU/8GB handles ~6 concurrent static builds (WOODPECKER_MAX_WORKFLOWS=2).
