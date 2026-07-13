# Universe Platform State — 2026-07-06

> **Post-snapshot update:** as of 2026-07-07, Windmill was retired (see [`docs/runbooks/archive/2026-07-07/12-windmill-decommission.md`](../runbooks/archive/2026-07-07/12-windmill-decommission.md)) and gxy-launchbase was decommissioned (idle droplets deleted, pending rebuild). This 2026-07-06 snapshot predates both changes.

Live-verified snapshot of the freeCodeCamp Universe platform: what is what, what runs, how it is deployed and updated, where automation is missing, and where the docs diverge from reality.

Supersedes [`universe-state-2026-05-29.md`](./universe-state-2026-05-29.md) — that snapshot predates the durable-execution subsystem (ADR-020 / Hatchet / artemis stage-2 / runbook-09), all live since 2026-06-05. Design rationale stays in the Universe ADRs (001-020) — not duplicated here.

> **Freshness:** live cluster reads on 2026-07-06 across all three galaxies (kubectl over tailnet). Figures are as-of that date. Version specifics drift — re-scout before acting on a pin.

| Axis         | Source                                                                                         |
| ------------ | ---------------------------------------------------------------------------------------------- |
| Design       | `~/DEV/fCC-U/Architecture/decisions/001..020` + `spike/spike-plan.md`                          |
| ADR drift    | `infra/.scratchpad/ADR_RECONCILIATION.md` (2026-07-04, ratified `d14257b`/`2361287`/`e420787`) |
| Repo reality | `infra/` (justfile, k3s, ansible, terraform), `artemis/`, `veritas/`, `windmill/` on disk      |
| Live cluster | `kubectl` reads via `k3s/<galaxy>/.kubeconfig.yaml` (tailnet), 2026-07-06                      |

## 1. Repo map — what is what

- `infra/` — IaC for the Universe platform (this repo). k3s per-galaxy apps, ansible, terraform, justfile lifecycle verbs, runbooks + flight-manuals.
- `artemis/` — static-apps deploy proxy (`uploads.freecode.camp`). Go. Durable execution via Hatchet. Prod **v1.3.0**.
- `veritas/` — BetterAuth IdP (`login.freecodecamp.org`). **Built, deploy-frozen** (ADR-004 hold).
- `windmill/` — Windmill IaC (CLI sync for the gxy-management workspace). ADR-020 demoted role (interactive-tooling tenant).
- `~/DEV/fCC-U/Architecture/` — Universe design repo (ADRs 001-020, spike-plan). Absolute path, not a sibling.

## 2. Cluster status — LIVE vs STANDBY (live-verified 2026-07-06)

All three galaxies: 3 nodes each, all `Ready`, k3s `v1.34.5+k3s1`, ~74d uptime.

| Galaxy         | Role               | State                                                                                   |
| -------------- | ------------------ | --------------------------------------------------------------------------------------- |
| gxy-management | Control plane      | **LIVE** — artemis (3/3), Hatchet engine, Valkey registry, Windmill                     |
| gxy-cassiopeia | Static-serve plane | **LIVE** — caddy-s3 (3/3), Gateway Programmed, fronts `*.freecode.camp` from R2         |
| gxy-launchbase | Standby            | **IDLE** — CNPG operator only (1.29.0), no workload since Woodpecker retired 2026-05-03 |

Retired: `gxy-static` (2026-04-27, cutover to cassiopeia; orphan `gxy-static-k3s` DO tag harmless). Legacy out-of-scope: `ops-mgmt`, `ops-backoffice-tools`.

## 3. Live service inventory + image pins

| Service             | Galaxy / ns               | Live image                                                     | Digest-pinned?      |
| ------------------- | ------------------------- | -------------------------------------------------------------- | ------------------- |
| artemis             | gxy-management / artemis  | `ghcr.io/freecodecamp/artemis:1.3.0@c3dbc2d2…`                 | ✅ yes              |
| hatchet-engine      | gxy-management / artemis  | `ghcr.io/hatchet-dev/hatchet/hatchet-engine:v0.88.6@5f4e17be…` | ✅ yes (2026-07-06) |
| artemis PostgreSQL  | gxy-management / artemis  | `postgres:16.14-alpine` (bundled, shared with Hatchet)         | tag only            |
| Valkey (registry)   | gxy-management / valkey   | `valkey/valkey:8.1.4-alpine@e706d121…` (chart pins digest)     | ✅ yes              |
| Windmill            | gxy-management / windmill | `ghcr.io/windmill-labs/windmill:1.703.2` (+ extra + workers)   | ❌ chart-float      |
| Windmill PostgreSQL | gxy-management / windmill | `postgres:18`                                                  | tag only            |
| caddy-s3            | gxy-cassiopeia / caddy    | `ghcr.io/freecodecamp/caddy-s3:sha-712c6e34…@e024af67…`        | ✅ yes              |
| CNPG operator       | cassiopeia + launchbase   | `ghcr.io/cloudnative-pg/cloudnative-pg:1.29.0`                 | ❌ chart-float      |
| PG backup image     | artemis + windmill ns     | `ghcr.io/freecodecamp/postgres-rclone@294e8b27…`               | ✅ yes              |

## 4. Deploy + update model

- **Lifecycle verbs** (post-`cd3b3a32`): `just release/configure/inspect/destroy/backup <galaxy> <app>` from repo root. Recipe self-exports `KUBECONFIG` from `k3s/<galaxy>/.kubeconfig.yaml`.
- **Helm source:** `apps/<app>/charts/<chart>/repo` (one-line URL) → remote chart; absent → local chart dir. Per-app `.deploy-flags.sh` appends `EXTRA_HELM_ARGS`.
- **Cluster auth:** kubeconfig over tailnet (server = `100.64/10` CGNAT). DO-API / R2 / sops-secret ops need the galaxy `.envrc` (`use_sops …do-universe/.env.enc`) — operator-run.
- **artemis update:** GHCR image → pin digest in `k3s/gxy-management/apps/artemis/values.production.yaml` → `just release gxy-management artemis` → runbook 03 postdeploy.

## 5. Durable execution subsystem — ADR-020 (LIVE, was absent from 2026-05-29)

- **Model:** artemis deploy/GC flows run as **Hatchet** durable workflows (engine `v0.88.6`, gxy-management/artemis ns), backed by the shared bundled PostgreSQL. Tranche-1 (deploy-GC) **shipped 2026-06-06**; tranche-2 (constellation provision/teardown) is governance-only, impl deferred → Windmill still carries those flows.
- **artemis stage-2:** durable-execution cutover complete + prod-verified (v1.3.0). Design + known-limitations in `artemis/docs/design/0001-durable-execution-model.md`.
- **Runbook:** `docs/runbooks/09-hatchet-engine-deploy.md` (deploy/upgrade the engine). Slots 07-09 reclaimed from archived Woodpecker runbooks.
- **Windmill (ADR-020 demote):** role reframed platform-ops → interactive-tooling tenant (`windmill` commit `7a6229c`). Still hosts privileged Apollo-11 staff-approval flows — CF Access gating elevated to P1 (ADR-009 amendment).

## 6. Automation posture + gaps

- **Backups (nightly `0 2 * * *`, → R2 via postgres-rclone):** artemis PostgreSQL ✅, Windmill PostgreSQL ✅.
- **GAP — Valkey site-registry has NO backup.** Registry (`REGISTRY_BACKEND=valkey`) durability = single local-path PVC `data-valkey-0` (2Gi, one node). No R2 copy, no replica. = cassiopeia GA gate **G11 UNMET**. Parked (high-viz): `TODO-park.md` §Reliability. See `rfc-gxy-cassiopeia-ga.md` §E.
- **Monitoring:** in-cluster scrape parked — sanctioned o11y (Vector/vmagent/GlitchTip) lives on gxy-backoffice, unbuilt (ADR-018 epic 3). Live paging = Sentry SaaS (artemis DSN real + verified 2026-07-05). No ServiceMonitor on gxy-management (no prometheus-operator there).
- **Image float:** Windmill + CNPG charts pull latest chart-version each release (no `.deploy-flags.sh` version pin). All first-party images digest-pinned.

## 7. Docs-vs-reality drift

Resolved since 2026-05-29:

- artemis `0.7.0` → **`1.3.0`** (durable-exec); Hatchet subsystem now live + documented.
- ADR reconciliation ratified (`d14257b`/`2361287`/`e420787`): 18/19 ADRs Accepted, ADR-020 live-tracked.
- ADR-009 preview scheme corrected everywhere: `<site>.preview.freecode.camp` dot-scheme + own wildcard (was `{site}--preview`).
- cassiopeia GA gates live-verified + RFC stamped 2026-07-06 (G1/G2/G4/G6 met; G11 open).
- Hatchet images digest-pinned (`d532ecb9`).

Remaining:

- **runbook-01** — teaches a nonexistent GHA-OIDC identity chain + stale "Woodpecker today" + wrong org literal. UNFIXED (held for operator review). ADR-reconciliation blocker 2.
- **G11** Valkey registry backup (§6 gap).
- Windmill / CNPG chart-version float (§6).
- ADR-014 (Onboarding) still `Proposed` — gated on ADR-003/004/015 shipping.

## 8. In-flight + parked

- **Live dossier (infra):** `2026-07-04-universe-consol-decommission` (consolidation hub). `universe-doc-trim` paused.
- **artemis:** v1.3.0 shipped; live dossier `artemis-o11y-sentry` (Sentry o11y overhaul, planned).
- **veritas:** deploy-frozen (ADR-004 hold); dev continues (idp-local-proof, near-complete). 67 commits unpushed by design.
- **Parked (unblock triggers in `TODO-park.md`):** gxy-backoffice + observability, gxy-triangulum, Hetzner BM migration, Windmill CF Access, Valkey registry backup, gxy-static etcd purge.

## Relationship to other docs

- Design authority: Universe ADRs 001-020 + `spike/spike-plan.md`.
- ADR drift detail: `.scratchpad/ADR_RECONCILIATION.md`.
- Operator rebuild: `docs/flight-manuals/` (index `00-index.md`, start `UNIVERSE.md`).
- cassiopeia GA gates: `docs/architecture/rfc-gxy-cassiopeia-ga.md`.

## Out of scope

Legacy fCC (`ops-mgmt`, `ops-backoffice-tools`) — retire post-Universe. Veritas feature delivery — owned by `veritas` dossiers. Design rationale — Universe ADRs, not restated here.
