# Sprint 2026-04-21 — Q/A recommended defaults

Operator decisions gate task #23 (new MASTER sprint plan). This doc proposes
pragmatic defaults per question with short rationale. Scan, tick, redirect
where wrong. Each Q tracked as a Tasks-API item (#28–#35); resolution lands
as a one-line addendum to the matching ADR amendment.

**Lens:** ship static-apps MVP fast; defer everything that doesn't block
staff push → site live. Complexity lands in Phase 2.

## Q1 — Alias-write mechanism (#28)

**Recommended: (a) Woodpecker pipeline step.**

- Last step of the canonical `.woodpecker/deploy.yaml` writes the alias
  file to R2 after the upload step succeeds.
- **Why:** atomic per deploy (no extra service hop); fewer failure modes;
  no dependency on launchbase Windmill being healthy for a staff push to
  go live; matches ADR-007 "Windmill as glue, not hot path".
- **Cost:** staff repos need a consistent last step. Solved by the
  template we ship (task #24).
- **When Windmill wins:** promote/rollback across multiple sites — batch
  operations — can live as Windmill flows that call the same API.

## Q2 — CF R2 admin cred path (#29)

**Recommended: (c) dedicated provisioning-scope token at
`infra-secrets/platform/cf-r2-provisioner.secrets.env.enc`.**

- Token has "Admin Read & Write" over the single bucket
  `universe-static-apps-01`. Scoped to that bucket only; cannot mint
  data-plane tokens for other buckets.
- Per-site data-plane tokens minted by the provisioning flow are stored
  at the path decided in Q3.
- **Why:** blast radius is separated from data-plane; rotation of the
  provisioner token does not invalidate any site's runtime token. Avoids
  stuffing the admin cred into `do-primary/.env.enc` (T11 worker flagged
  this as anti-pattern).

## Q3 — Per-site secret sops path (#30)

**Recommended: `infra-secrets/constellations/<site>.secrets.env.enc`.**

- Flat, site-scoped; sibling to `infra-secrets/k3s/` rather than nested
  under it.
- **Why:** per-constellation portability. If a site moves between
  galaxies (cassiopeia now, triangulum later for dynamic content), the
  secret path is stable. Matches the ADR-007 mental model where a
  constellation is a platform primitive, not a galaxy detail.
- `.sops.yaml` creation_rule: `path_regex:
^constellations/.*\.secrets\.env\.enc$` with the platform age key.

## Q4 — Origin IP allow-list enforcement (#31)

**ACCEPTED 2026-04-22: (b) DO Cloud Firewall, simple mode — no CF-IP
allow-list, no per-galaxy split.**

- `gxy-fw-fra1` keeps 80/443 open to `0.0.0.0/0`. Traffic already gated
  behind CF proxy (SSL Full Strict); CF WAF + CF DDoS absorb the
  abuse surface.
- No Windmill cron to diff CF IPs. No tag split per galaxy. KISS.
- Post-MVP triggers to reconsider: one of (a) first scraper-driven DO
  bandwidth spike, (b) CF-bypass attack signature observed in logs,
  (c) compliance ask for explicit IP allow-list.
- **Why simpler now:** T32 stamp-2 field note flagged Cilium CNP with
  FQDN allow-lists as a footgun under 1.19. Adding CF-IP rules on the
  DO side trades that footgun for a weekly-cron dependency; we don't
  need the protection yet.

## Q5 — Staff-site DNS pattern (#32)

**ACCEPTED 2026-04-22: platform-owned two-level pattern.**

- Prod: `<site>.freecode.camp` A record → cassiopeia node public IPs,
  CF proxied, SSL Full (Strict) via `*.freecode.camp` CF Origin cert
  (already live).
- Preview: `<site>.preview.freecode.camp` A record → same IPs, CF proxied,
  SSL Full (Strict) via `*.preview.freecode.camp` CF Origin cert
  (already issued via ACM, CF activated).
- Onboarding = Woodpecker/Windmill flow accepts `<site>`, creates both
  A records (or a single flat entry plus a preview entry as needed),
  writes caddy route/alias mapping.
- **Why:** fastest onboarding; zero registrar API work for MVP; two CF
  zones' worth of certs already in place; aligns with gxy-static's
  current pattern. Preview sibling unlocks Q7.
- **Phase 2:** BYO domain via `universe` CLI per ADR-009 flat DNS model.
  Staff owns full domain; platform provisions CF Origin Cert per domain.
  Deferred until first staff asks.

## Q6 — Rollback SLO (#33)

**Recommended: (b) minutes — target ≤ 2 minutes.**

- `r2_alias` caches alias file per-request with ~60s LRU TTL. Worst-case:
  live request resolves old alias for up to 60s after promote/rollback.
- Smoke harness polls at 30s intervals after promote; green after 2
  consecutive hits.
- **Why:** static content acceptably serves old version briefly; sub-30s
  SLO forces CDN cache purge + shorter LRU TTL which hurts steady-state
  cache hit rate. 2-min SLO matches CF cache TTL defaults.
- **Phase 2:** tiered SLO (sub-minute for prod-critical sites) when a
  site demands it.

## Q7 — Preview environments in MVP (#34)

**ACCEPTED 2026-04-22: prod + preview in MVP (flipped from default).**

- DNS cert infra is already in place: `*.preview.freecode.camp` CF
  Origin cert live alongside `*.freecode.camp`. No additional registrar
  or CF work needed to serve preview traffic.
- Each deploy writes two alias files in R2: `<site>/production` and
  `<site>/preview`. `universe promote` repoints `<site>/production` to
  the current preview prefix atomically.
- Cleanup cron (Q8) treats both aliases as "in use" — same 7d retention
  for unreferenced prefixes.
- **Why flipped:** default assumed preview DX cost > MVP value. With
  certs pre-issued the incremental cost collapses to R2 prefix
  bookkeeping. Preview path becomes the staff safety net for prod
  cutover, which is load-bearing for any content edit-and-ship loop.

## Q8 — Cleanup retention (#35)

**Recommended: (a) hard 7d per ADR-007 default; no override for MVP.**

- Windmill cron deletes deploys older than 7 days, except currently
  aliased (production + preview).
- **Why:** KISS; no platform.yaml plumbing needed; 7d covers typical
  rollback window.
- **Phase 2:** per-site override via `platform.yaml`
  `static.retention: <N>d` when first ask lands.

## Summary table — ACCEPTED 2026-04-22

| Q   | Topic                | Decision                                                                                      |
| --- | -------------------- | --------------------------------------------------------------------------------------------- |
| Q1  | Alias-write          | Woodpecker pipeline step                                                                      |
| Q2  | CF R2 admin cred     | `infra-secrets/platform/cf-r2-provisioner.secrets.env.enc`                                    |
| Q3  | Per-site sops path   | `infra-secrets/constellations/<site>.secrets.env.enc`                                         |
| Q4  | Origin IP allow-list | DO Cloud Firewall, no CF-IP allow-list, no per-galaxy split                                   |
| Q5  | Staff-site DNS       | Prod `<site>.freecode.camp` + preview `<site>.preview.freecode.camp` (both certs CF-resident) |
| Q6  | Rollback SLO         | ≤ 2 minutes                                                                                   |
| Q7  | Preview envs         | Prod + preview both in MVP (flipped — certs already issued)                                   |
| Q8  | Cleanup retention    | Hard 7d; preview alias pins its prefix same as prod                                           |

## How to adopt

1. Operator reviews each Q above; ticks or redirects.
2. Decisions land as one-line addenda to the relevant ADR amendments
   (ADR-003 / 007 / 008 / 011 carry them).
3. Resolved Qs close their Tasks-API items (#28–#35).
4. Task #23 (MASTER sprint plan) writes with decisions locked in.
5. Task #24 (MVP chain) implements.
