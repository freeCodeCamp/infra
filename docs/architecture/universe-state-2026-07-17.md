# Universe Platform State — 2026-07-17

Live-verified snapshot + full 20-ADR-vs-reality audit of the freeCodeCamp Universe platform: what runs, what the ADRs claim, where they diverge, and what is knowingly parked.

Supersedes [`archive/2026-07-17/universe-state-2026-07-06.md`](./archive/2026-07-17/universe-state-2026-07-06.md) — that snapshot predates the Windmill retirement + gxy-launchbase decommission (both 2026-07-07) and covers no ADR-by-ADR reconciliation. Design rationale stays in the Universe ADRs (001–020) — not duplicated here.

> **Freshness + method:** 92-agent audit run 2026-07-17 (per-ADR extraction, 6 empirical probes — kubectl both live clusters, doctl, dig/curl, repo desired-state, prior baselines — per-claim reconciliation, adversarial re-verification of every drifted/not-built finding), plus direct kubectl/doctl reads same day. 242 claim-level verdicts. Version pins drift fast — artemis bumped twice in the 11 days before this snapshot. Re-scout before acting on any pin.

> **Known blind spots (not probed):** Cloudflare zone config (Access/WAF), R2 bucket inventory (sops-gated), SES/DKIM state (AWS-creds-gated), Hetzner plans (nothing exists to probe), DO dollar figures (droplet inventory verified, billing not).

| Axis         | Source                                                                               |
| ------------ | ------------------------------------------------------------------------------------ |
| Design       | `~/DEV/fCC-U/Architecture/decisions/001..020` + `spike/spike-plan.md`                |
| Audit        | 2026-07-17 workflow `wf_e3c5796b-bd8` (session-local journal; findings inlined here) |
| Repo reality | `infra/` (justfile, k3s, ansible, terraform), `artemis/`, `veritas/` on disk         |
| Live cluster | `kubectl` via `k3s/<galaxy>/.kubeconfig.yaml` (tailnet), `doctl`, 2026-07-17         |

## 1. Cluster status (live-verified 2026-07-17)

| Galaxy         | Role               | State                                                                                        |
| -------------- | ------------------ | -------------------------------------------------------------------------------------------- |
| gxy-management | Control plane      | **LIVE** — 3 nodes Ready, k3s v1.34.5+k3s1. artemis 3/3, hatchet-engine 1/1, valkey 1/1      |
| gxy-cassiopeia | Static-serve plane | **LIVE** — 3 nodes Ready, k3s v1.34.5+k3s1. caddy 3/3, CNPG operator 1/1 (zero clusters)     |
| gxy-launchbase | Pending rebuild    | **DECOMMISSIONED 2026-07-07** — zero droplets (doctl-verified), kubeconfig dead. Not retired |

Droplets: 6 galaxy VMs + `exit-node-atlanta` (tailnet exit node). Both galaxies share one VPC `gxy-vpc-fra1` (10.110.0.0/20) — see §4 network finding. Retired: `gxy-static` (2026-04-27). Legacy out-of-scope: `ops-mgmt`, `ops-backoffice-tools`.

## 2. Live service inventory + image pins (pod-spec reads 2026-07-17)

| Service                       | Galaxy / ns              | Live image                                              | Pin state                                                                                                       |
| ----------------------------- | ------------------------ | ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| artemis                       | gxy-management / artemis | `ghcr.io/freecodecamp/artemis:1.6.1@6bd30695…`          | ✅ digest (rolled 2026-07-17, `b38bbbe1`)                                                                       |
| hatchet-engine                | gxy-management / artemis | `hatchet-engine:v0.88.6` (no digest in running pod)     | ⚠️ values pin digest (`d532ecb9` 2026-07-06) but pod predates pin (started 2026-06-06) — takes effect next roll |
| artemis PostgreSQL            | gxy-management / artemis | `postgres:16.14-alpine@16bc17c6…`                       | ✅ digest                                                                                                       |
| Valkey (registry cache-front) | gxy-management / valkey  | `valkey/valkey:8.1.4-alpine` (no digest in running pod) | tag only live (sts 67d old); SoT = artemis PG since v1.4.0 (`6807518`), valkey = OnChange cache                 |
| postgres-rclone               | artemis ns (backup cron) | `ghcr.io/freecodecamp/postgres-rclone@294e8b27…`        | ✅ digest, nightly 02:00 runs confirmed 07-15/16/17                                                             |
| caddy-s3                      | gxy-cassiopeia / caddy   | `ghcr.io/freecodecamp/caddy-s3:sha-712c6e34…@e024af67…` | ✅ digest                                                                                                       |
| CNPG operator                 | gxy-cassiopeia only      | `ghcr.io/cloudnative-pg/cloudnative-pg:1.29.0`          | ❌ chart-float; **zero `Cluster` CRs** (no orphan — settled 2026-07-17)                                         |

Ingress: Gateway API only (`artemis-gateway` + HTTPRoute `uploads.freecode.camp`); zero classic Ingress objects on either cluster. Windmill: zero remnants on-cluster (ns/PVC/CRD/DNS all gone).

## 3. ADR-vs-reality verdict (20/20 ADRs)

242 verdicts: **124 aligned (51%) · 34 retired-by-amendment, clean (14%) · 29 not-built (12%) · 29 drifted (12%) · 18 partially-built (7%) · 8 unverifiable (3%)**. Amendment discipline is good — most gaps the ADRs already self-track. Findings below survived adversarial re-verification (independent agent reran the underlying command). Note: the GitOps-stack absence is one underlying fact counted across ADR-001/003/005/018/019 — the not-built tally overstates distinct gaps.

| ADR | Net       | Delta                                                                                                                                                                                                                                                                                      |
| --- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 001 | partial   | 2/5 galaxies live; container-pillar + Veritas parked/not-built                                                                                                                                                                                                                             |
| 002 | aligned\* | `ansible/playbooks/` verify-path dead; no rolling-upgrade automation exists                                                                                                                                                                                                                |
| 003 | partial   | shared platform-maintained Helm chart never built — every app bespoke                                                                                                                                                                                                                      |
| 004 | not-built | Veritas zero deploy (chart on unmerged `feat/veritas`, ~100 commits behind); amendment wrong re `/internal/apps`                                                                                                                                                                           |
| 005 | not-built | ArgoCD/Atlantis/`platform/` repo/app-registry: zero footprint; `platform.yaml` files exist, nothing reads them                                                                                                                                                                             |
| 006 | partial   | send API + scope gating live; email-change flow absent; CAN-SPAM gap untracked (GA blocker)                                                                                                                                                                                                |
| 007 | drifted   | CLI surface + buildpacks pipeline stale vs amendment snapshot (npm 0.12.0 live)                                                                                                                                                                                                            |
| 008 | not-built | Rook-Ceph/RGW/Percona/Litestream: nothing exists; mgmt PVCs on `local-path`, zero DO volumes                                                                                                                                                                                               |
| 009 | drifted   | launchbase CIDR mismatch — **group_vars fixed to 10.3/10.13 2026-07-17** pre-rebuild; default-deny CNP overstated (`enable-policy: default`); argocd/registry/grafana DNS = NXDOMAIN. ADR-009 2026-07-17 amendment records all three                                                       |
| 010 | drifted   | envelope inventory stale (38→29 prod, 32 incl scratchpad; `k8s/o11y/` deleted 2026-07-14; `r2-read/` undocumented); root `.envrc` loaded `global/` repo-wide contra ADR claim — **fixed 2026-07-17** (`INFRA_ADMIN=1` gate + ADR-010 amendment); veritas envelope residuals operator-gated |
| 011 | partial   | zero ResourceQuota/LimitRange anywhere; shared VPC + firewall ≠ "separate networks". PSS finding **refuted** — `enforce=baseline` wired at apiserver via ansible bootstrap, Restricted labels on constellation namespaces                                                                  |
| 012 | drifted   | etcd RPO doc 24h vs actual 6h (`0 */6 * * *` in group_vars); Apollo backup row = dead component; registry SoT history Git→Valkey (`f115198` 05-10)→artemis PG (`6807518`, v1.4.0, prod 07-06; Valkey = cache-front). All fixed via ADR-012 2026-07-17 amendment                            |
| 013 | aligned\* | droplet inventory matches; 3-galaxy run-rate headline overstated (2 live); dollar figures unchecked                                                                                                                                                                                        |
| 014 | aligned   | correctly still Proposed; gates (D003/D004/D015) unmet                                                                                                                                                                                                                                     |
| 015 | aligned   | o11y stack parked on unprovisioned gxy-backoffice per own status; zero footprint verified; interim Sentry SaaS posture amendment-acknowledged                                                                                                                                              |
| 016 | aligned\* | near-exact source/live match; repo-approval queue is Postgres-only in prod (Valkey impl exists but unwired, contra 2026-05-29 amendment)                                                                                                                                                   |
| 017 | partial   | pillars GHCR-direct ✅; "Zot remains live" false (no release, no chart dir); rehearsal doc at `gxy-management.md` §D.5 not UNIVERSE.md §99, predates current PG shape                                                                                                                      |
| 018 | drifted   | version cites stale (artemis 1.3.0→1.6.1, cli→0.12.0); "windmill repo archived" was false 07-07→07-17 — **closed 2026-07-17** (cron disarmed `c99fa1d` + repo archived). ADR-018 amendment records both                                                                                    |
| 019 | partial   | P1 missing ArgoCD/Atlantis; P2 Veritas absent; venue/backup-floor text correct                                                                                                                                                                                                             |
| 020 | aligned\* | Hatchet/GC live + correct; both "known limitations" fixed in artemis v1.4.0 (`cf9644a`/`fc72a64`, 2026-07-06) yet 07-07 amendment still lists them open                                                                                                                                    |

\* = aligned with material caveats.

## 4. Confirmed high-severity drift (each independently re-verified)

1. **GitOps phantom** — ArgoCD/Atlantis zero footprint 3 months past "parked"; `platform/` GitHub repo + `app-registry.yaml` never existed (org has 76 repos, none match).
1. **Veritas undeployed** — chart only on unmerged `feat/veritas`; `login./account.freecodecamp.{org,dev}` → raw Traefik 404 via Cloudflare. ADR-004's 2026-07-07 amendment falsely claims `/internal/apps` was never implemented — it is implemented, tested, wired.
1. **ADR-008 storage layer nonexistent** — no Rook-Ceph/RGW/Percona/Litestream anywhere; gxy-management state on disposable `local-path`, zero DO Block Storage volumes.
1. **Network isolation weaker than doc** — one shared VPC + one firewall admitting k3s ports from the whole 10.110.0.0/20; Cilium policy mode default-allow; ADR-011 "separate networks" false as stated.
1. **Secrets** — root `.envrc` auto-loaded `global/.env.enc` + `r2-read/.env.enc` on every `cd` (contradicted ADR-010's own security claim; never was true). **Fixed 2026-07-17**: both gated behind `INFRA_ADMIN=1` (ADR-010 2026-07-17 amendment). Open (operator): veritas prod envelope still carries `GITHUB_CLIENT_*`; staging envelope missing.
1. **DR doc rot** — RPO 6h not 24h; Apollo backup row dead; registry SoT history Git→Valkey→artemis PG (v1.4.0) — registry now rides the tested PG backup, G11 premise changed. Fixed by ADR-012 2026-07-17 amendment + RFC G11 re-evaluation note.
1. **Windmill IaC teardown incomplete** — repo unarchived, `cleanup_old_deploys` cron committed `enabled: true, dry_run: false` (inert only because cluster is gone). Runbook-12 Phases 2+8 never executed. Cluster side fully clean. **Closed 2026-07-17**: cron disarmed (`c99fa1d`), repo archived on GitHub.
1. **ADR-020/016/018 stale in own favor** — fixed limitations still listed open; version cites lag production by 2–3 releases.

Refuted (do not chase): ADR-011 PSS "unenforced" — verifier proved cluster-wide `enforce=baseline` admission config baked in at bootstrap.

## 5. Retirement ledger (docs vs reality)

| Item                        | Docs claim                      | Reality                                       | Agree          |
| --------------------------- | ------------------------------- | --------------------------------------------- | -------------- |
| Windmill (cluster)          | retired 2026-07-07              | zero remnants, DNS NXDOMAIN                   | ✅             |
| Windmill (IaC repo)         | "archived read-only"            | `isArchived: false`, cron still armed in-repo | ❌ open (task) |
| Apollo / repo-creation      | folded into artemis + CLI       | `/api/repos` live traffic, 6 CLI subcommands  | ✅             |
| gxy-launchbase              | decommissioned, pending rebuild | zero droplets, kubeconfig dead                | ✅             |
| gxy-static                  | retired 2026-04-27              | zero tagged droplets                          | ✅             |
| Woodpecker / Kyverno / SBOM | parked/retired                  | zero footprint                                | ✅             |
| ArgoCD/Atlantis/Zot/Kargo   | parked                          | zero footprint (see §4-1 for framing gap)     | ✅             |

## 6. Automation posture + gaps

- **Backups:** artemis PostgreSQL nightly → R2 ✅ (runs confirmed 07-15/16/17) — now also carries registry state (PG SoT since v1.4.0). **G11 needs re-score:** premise (registry durability = single valkey PVC) invalidated by PG cutover; residual exposure = cache-front availability, not durability. See RFC §E note 2026-07-17.
- **Monitoring:** in-cluster scrape parked (gxy-backoffice unbuilt); live paging = artemis Sentry SaaS DSN.
- **Quotas:** zero ResourceQuota/LimitRange on either cluster — no tenant resource enforcement exists.
- **Image float:** CNPG chart-float; hatchet + valkey digest pins land on next roll (pinned in values, running pods predate).

## 7. Unverifiable (8) — settling checks

SES DKIM/warm-up (AWS creds) · R2 backup buckets (`wrangler r2 bucket list`, sops-gated) · OAuth callback URLs (provider consoles) · Tailscale SSH-only scope (node access) · DO billing CSV (console) · launchbase storageclass (post-rebuild) · docker-compose dev template (external template repo) · CF Access posture (CF dashboard).

## 8. Open actions

Closed 2026-07-17: windmill repo archive + cron disarm · ADR-012 fixes · ADR-010 `.envrc` scope-down · launchbase CIDR (group_vars → 10.3/10.13) · ADR-004 `/internal/apps` correction · ADR-006/009/011/016/017/018/020 audit amendments · CAN-SPAM gap filed as GA blocker (ADR-006). Open: ResourceQuota/LimitRange baseline (needs sizing) · G11 re-score (RFC §E) · veritas envelope residuals (deferred until veritas unfreezes, ADR-010).

## Relationship to other docs

- Design authority: Universe ADRs 001–020 + `spike/spike-plan.md`.
- Historical ADR-vs-reality provenance: [`adr-drift-2026-05-10.md`](./adr-drift-2026-05-10.md) (immutable, closed 2026-06-01).
- Prior snapshots: [`archive/2026-07-17/`](./archive/2026-07-17/README.md).
- Operator rebuild: `docs/flight-manuals/` (start `UNIVERSE.md`). cassiopeia GA gates: `rfc-gxy-cassiopeia-ga.md`.

## Out of scope

Legacy fCC (`ops-mgmt`, `ops-backoffice-tools`). Veritas feature delivery (owned by `veritas` dossiers). Design rationale (ADRs).
