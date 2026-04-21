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

**Recommended: (b) DO Cloud Firewall at node level.**

- Rule on `gxy-fw-fra1`: allow 80/443 only from published Cloudflare IPv4
  - IPv6 ranges (`https://www.cloudflare.com/ips-v4/` +
    `/ips-v6/`).
- Windmill cron refreshes the rule weekly via DO API (list diffs CF IPs,
  calls firewall update).
- **Why:** T32 stamp-2 field note flagged Cilium CNP with FQDN
  allow-lists as a footgun under 1.19; node-level firewall avoids cluster
  DNS dependencies. Fails open on rule misconfiguration (still gated by
  CF WAF), which is safer for static public content than Cilium's
  fail-closed default.
- Applies to `gxy-cassiopeia` only for MVP; no effect on `gxy-management`
  / `gxy-launchbase` which are org-gated and do not serve public traffic.

## Q5 — Staff-site DNS pattern (#32)

**Recommended: (a) platform-owned `<site>.freecode.camp` subdomain per
site, MVP-only.**

- `<site>.freecode.camp` A record → cassiopeia node public IPs, CF proxied,
  SSL Full (Strict) via `*.freecode.camp` origin cert.
- Onboarding = Windmill flow accepts `<site>`, creates CF DNS record,
  writes caddy route to ConfigMap.
- **Why:** fastest onboarding; zero registrar API work for MVP; one CF
  zone to reason about; aligns with gxy-static's current pattern (easy
  cutover).
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

**Recommended: (a) prod-only MVP.**

- Ship prod path first. Preview path lands in Phase 2 once prod stable.
- **Why:** preview doubles the moving parts (preview R2 prefix, preview
  alias, preview DNS, preview cleanup cadence). Staff-unblock goal is
  prod first; preview is DX polish.
- **Compensating:** staff can test locally via `universe` CLI's
  `--preview` flag dry-run against a scratch R2 prefix after Phase 2.

## Q8 — Cleanup retention (#35)

**Recommended: (a) hard 7d per ADR-007 default; no override for MVP.**

- Windmill cron deletes deploys older than 7 days, except currently
  aliased (production + preview).
- **Why:** KISS; no platform.yaml plumbing needed; 7d covers typical
  rollback window.
- **Phase 2:** per-site override via `platform.yaml`
  `static.retention: <N>d` when first ask lands.

## Summary table — recommended MVP defaults

| Q   | Topic                | Recommended default                                        |
| --- | -------------------- | ---------------------------------------------------------- |
| Q1  | Alias-write          | Woodpecker pipeline step                                   |
| Q2  | CF R2 admin cred     | `infra-secrets/platform/cf-r2-provisioner.secrets.env.enc` |
| Q3  | Per-site sops path   | `infra-secrets/constellations/<site>.secrets.env.enc`      |
| Q4  | Origin IP allow-list | DO Cloud Firewall (node-level)                             |
| Q5  | Staff-site DNS       | Platform-owned `<site>.freecode.camp` subdomain            |
| Q6  | Rollback SLO         | ≤ 2 minutes                                                |
| Q7  | Preview envs         | Prod-only MVP (preview Phase 2)                            |
| Q8  | Cleanup retention    | Hard 7d (override Phase 2)                                 |

## How to adopt

1. Operator reviews each Q above; ticks or redirects.
2. Decisions land as one-line addenda to the relevant ADR amendments
   (ADR-003 / 007 / 008 / 011 carry them).
3. Resolved Qs close their Tasks-API items (#28–#35).
4. Task #23 (MASTER sprint plan) writes with decisions locked in.
5. Task #24 (MVP chain) implements.
