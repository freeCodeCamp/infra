# Universe Platform State — 2026-05-29

Live-verified snapshot of the freeCodeCamp Universe platform: what is what, what runs, how it is deployed and updated, where automation is missing, and where the docs diverge from reality.

Successor in spirit to [`adr-drift-2026-05-10.md`](./adr-drift-2026-05-10.md) (that report = ADR-vs-reality only; all its AD-1..AD-8 actions are closed). This report is broader: ADR design + on-disk code + **live cluster reads** + CI/automation posture, in one place. Design rationale stays in the Universe ADRs (001-019) — not duplicated here.

| Axis            | Source                                                                                    |
| --------------- | ----------------------------------------------------------------------------------------- |
| Design          | `~/DEV/fCC-U/Universe/decisions/001..019` + `spike/spike-plan.md`                         |
| Repo reality    | `infra/` (justfile, k3s, ansible, terraform), `artemis/`, `veritas/`, `windmill/` on disk |
| Cluster reality | `doctl compute droplet list` + `kubectl` reads, this date                                 |
| CI reality      | `.github/workflows/` across all repos; `renovate.json` presence                           |

**Method:** 7 parallel read-only research agents (one per repo/domain) + direct `doctl`/`kubectl` probes against the three live galaxies. Where an agent claim and a live read disagreed, the live read won.

______________________________________________________________________

## 1. Repo map — what is what

| Repo          | Path                       | Role                                                                                                                                                                   |
| ------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| infra         | `~/DEV/fCC/infra`          | IaC executor: `justfile` dispatcher, ansible bootstrap, per-galaxy k3s charts/manifests, terraform (legacy only), runbooks + flight-manuals                            |
| infra-secrets | `~/DEV/fCC/infra-secrets`  | sops+age vault (single org key). Hard-coded sibling `../infra-secrets`. No secrets in infra repo                                                                       |
| artemis       | `~/DEV/fCC/artemis`        | Go service on `uploads.freecode.camp`. Sole R2 writer. GitHub-team authz → mints deploy JWT → streams uploads to R2 with atomic alias flip. Deployed to gxy-management |
| veritas       | `~/DEV/fCC-U/veritas`      | TypeScript auth IdP (BetterAuth embedded). `login.` + `account.freecodecamp.org`. Active source repo. CI carries cosign + SBOM                                         |
| Universe      | `~/DEV/fCC-U/Universe`     | Design repo: 19 ADRs + spike-plan. No code, no CI. Authoritative architecture model                                                                                    |
| windmill      | `~/DEV/fCC-U/windmill`     | Windmill IaC (wmill CLI sync). "Apollo-11" = staff repo request/approve via Google Chat + React SPA. Tenant on gxy-management. EA-live for staff                       |
| universe-cli  | `~/DEV/fCC-U/universe-cli` | `universe` CLI (deploy / sites registry). v0.7.0 on npm                                                                                                                |

## 2. Cluster status — LIVE vs PARKED (live-verified)

9 droplets, all DigitalOcean FRA1, all `active`. 3 galaxies × 3 nodes.

| Galaxy         | Crit | Hosting              | Reality (this date)                                                                                                             | Design says                 |
| -------------- | ---- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| gxy-management | P1   | DO FRA1 forever      | **LIVE** — artemis 3/3 Running on `0.3.0` (4d3h up), valkey, windmill                                                           | matches                     |
| gxy-cassiopeia | P2   | DO FRA1 forever      | **LIVE** — caddy 3/3 (R2 static serve). `cnpg-system` ns ~4d old (operator pre-staged). **No `veritas` / `veritas-staging` ns** | matches; veritas planned    |
| gxy-launchbase | P4   | DO FRA1 → bare metal | **LIVE but idle** — CNPG operator only, no DB workloads                                                                         | matches                     |
| gxy-triangulum | P3   | Hetzner              | **NOT provisioned** (zero droplets)                                                                                             | PARKED — gates ADR-013 Q-24 |
| gxy-backoffice | P5   | Hetzner              | **NOT provisioned** (zero droplets)                                                                                             | PARKED — gates auth epic    |
| ~~gxy-static~~ | —    | —                    | RETIRED 2026-04-27 → cassiopeia                                                                                                 | matches                     |

Legacy, out-of-Universe-scope (retire post-Universe): `ops-backoffice-tools` (outline + appsmith), `ops-mgmt`, plus Linode/Azure Docker-Swarm stacks.

## 3. Live service inventory + image pins

Pins are git-tracked in `k3s/<cluster>/apps/<app>/values.production.yaml` and were confirmed against running pods.

| Cluster    | Service                      | Image (live)                                         | Pin style                                |
| ---------- | ---------------------------- | ---------------------------------------------------- | ---------------------------------------- |
| management | artemis                      | `ghcr.io/freecodecamp/artemis:0.3.0@sha256:b3ee09b…` | semver + **digest** OK                   |
| management | valkey (artemis registry KV) | `valkey/valkey:8.1.4-alpine`                         | tag-only, no digest                      |
| management | windmill                     | windmill-labs remote chart                           | **no version pin** — pulls latest        |
| management | windmill PG backup CronJob   | `postgres-rclone@sha256:294e8b…`                     | digest-only OK                           |
| cassiopeia | caddy-s3                     | `caddy-s3:sha-712c6e34…@sha256:e024af…`              | sha + **digest** OK                      |
| cassiopeia | CNPG operator                | cnpg chart `0.28.0` (pinned via `.deploy-flags.sh`)  | pinned OK                                |
| launchbase | CNPG operator                | cnpg chart                                           | **no version pin** — install-time latest |

## 4. Deploy + update model

Uniform, manual, operator-laptop driven.

1. Code change → CI builds image to GHCR. **artemis / veritas** auto-build on `v*` tag push; **caddy-s3 / postgres-rclone** are `workflow_dispatch`-only; `landing` auto-builds on push (floating `latest`, no digest).
1. Operator resolves the digest, hand-edits `image.tag` in `values.production.yaml`, commits.
1. `just release <cluster> <app>` from a laptop — self-exports KUBECONFIG (`justfile:79`, sops-decrypted), layers chart values + sops overlay, runs `helm upgrade --install` (and `kubectl apply -k` for kustomize apps).
1. `just verify-<app>` E2E gate. Rollback = revert the pin commit + re-release (digest pins make this deterministic).

Cluster build path: DO droplets via **ClickOps** (OpenTofu never adopted — ADR-002 drift) → ansible `k3s--bootstrap` (k3s `v1.34.5+k3s1`, **Cilium 1.19.2** CNI with kube-proxy replacement, Traefik ingress, etcd snapshots → DO Spaces every 6h).

Authoritative procedures: `docs/runbooks/02-deploy-artemis-service.md`, `docs/flight-manuals/`.

## 5. Veritas — the active frontier (built, NOT deployed)

The platform's next leap (universal SSO) is where current work concentrates. infra is on branch **`feat/veritas`** (≈10 commits past the 2026-05-25 QoL merge); veritas source repo and Universe ADRs all moved on this date.

State:

- **Source** (`~/DEV/fCC-U/veritas`): HEAD `feat(auth): scope v0 to Google-only; defer GH per ADR-004 amendment` — dated 2026-05-29.
- **Image built:** `ghcr.io/freecodecamp/veritas:0.1.0@sha256:f6fcc7…` (prod) + `main-0795d6d` (staging floating tag, `pullPolicy: Always` by design).
- **Charts on disk:** `k3s/gxy-cassiopeia/apps/{veritas,veritas-staging}/` (staging is a symlink to the veritas chart). infra HEAD `feat(veritas): drop GITHUB_* from chart per ADR-004 amendment`.
- **CNPG operator pre-staged** on cassiopeia (ns ~4d old) — first stateful pillar prep per ADR-019.
- **NOT deployed:** no `veritas` / `veritas-staging` namespace exists. PARKED, ready-to-bootstrap.

**This date's cross-repo decision** (propagated through 3 repos in lockstep): v0 ships **Google-only + email magic-link; GitHub deferred to v1**. Root cause: GitHub OAuth Apps allow exactly one callback URL (verified against GitHub docs); the earlier multi-callback-reuse plan was wrong for GitHub. See Universe ADR-004 amendment, veritas `feat(auth): scope v0 to Google-only`, infra `feat(veritas): drop GITHUB_*`.

Design (ADR-004 / ADR-019): BetterAuth library embedded; two-domain split (`login.` = IdP surface / `account.` = user-data surface); OAuth 2.1 + PKCE; audience-scoped JWTs (15 min); per-galaxy R2 WAL backup `cassiopeia-cnpg-backups`. Runs **alongside** existing Auth0 learner-auth — does not replace it in v0.

## 6. Automated-update posture + gaps

| Layer                         | Automated?                                                                                                                   | Evidence                                  |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| Image build                   | PARTIAL — artemis/veritas auto on `v*` tag; caddy-s3/postgres-rclone dispatch-only; landing auto-on-push (floating `latest`) | per-repo `.github/workflows/docker*.yml`  |
| Image → cluster               | **MANUAL** — edit pin, commit, `just release`                                                                                | runbook 02; `values.production.yaml`      |
| Helm charts                   | **MANUAL**                                                                                                                   | `justfile:69` `release`                   |
| Dependency updates (renovate) | PARTIAL — `infra` + `windmill` only. **artemis / veritas / universe-cli have none**                                          | `renovate.json` presence                  |
| k3s node patching             | **MANUAL** for Universe — scheduled ansible targets legacy Linode/Azure only                                                 | `ansible--housekeeping.yml`               |
| Windmill live sync            | **MANUAL** laptop `just apply`; CI is validate/dry-run only (may not be enabled on repo)                                     | `windmill/.github/workflows/validate.yml` |
| Secrets rotation              | **MANUAL** ClickOps + sops, no expiry alerting                                                                               | runbook 05                                |
| Rollback                      | **MANUAL** revert + re-release; no canary / health-gate                                                                      | runbook 02                                |

**There is no GitOps/CD.** Zero ArgoCD/Flux/image-updater anywhere; zero `kubectl`/`helm`/`just release` in any CI workflow. Every cluster mutation = operator laptop + decrypted KUBECONFIG. ArgoCD/Kargo/Atlantis remain parked until ≥3 constellation-serving galaxies need multi-galaxy GitOps (ADR-005). Supply-chain enforcement (cosign / Kyverno / Grype / Trivy / Syft) has been down since Woodpecker retired 2026-05-03 — only image digest-pinning + lockfiles remain (ADR-011).

Biggest gaps, ranked:

1. **No CD → operator-laptop bottleneck** (bus-factor; no continuous reconcile; drift undetectable).
1. **veritas — the auth IdP — has zero dependency automation** despite the strongest build hygiene. Worst place for stale crypto deps.
1. **caddy-s3 / postgres-rclone builds are dispatch-only** → two manual steps (build, then deploy); easy to forget the build half.
1. **Floating tags:** windmill chart (no version pin), launchbase CNPG (no pin), valkey (tag-only), `landing` (`latest`, no digest).
1. **No automated node patching / secret rotation / rollback** for Universe.

## 7. Docs-vs-reality drift (scouted, ranked)

| ID  | Drift                                                                                                                                    | Reality                                                                                                                                                                                                                                                                           | Where                                                  |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| D1  | **Veritas operationally undocumented**                                                                                                   | Charts + image + CNPG operator staged, chart churning this date, but no flight-manual chapter and no runbook. Runbook `08-veritas-edge-bootstrap` was added (`c2310069`) then reverted (`4a27e164`) → absent. New public surfaces `login.`/`account.` have zero operator coverage | runbooks stop at 07                                    |
| D2  | k3s-general.md wrong cloud                                                                                                               | Says `nyc3` / `ops-vpc-k3s-nyc3` / `10.108.0.0/20`; reality `fra1` / `universe-vpc-fra1` / `10.110.0.0/20`                                                                                                                                                                        | `infra-guides/k3s-general.md:55-69`                    |
| D3  | backup-valkey works but docs say "deferred / not running"                                                                                | `just backup-valkey` is a real BGSAVE → `kubectl cp` recipe                                                                                                                                                                                                                       | `justfile:777` vs `gxy-management.md §C.5/§G`          |
| D4  | artemis Chart.yaml `appVersion: 0.1.0` lags deployed `0.3.0`; artemis repo CLAUDE.md names wrong cluster (cassiopeia; real = management) | live pods on 0.3.0 on gxy-management                                                                                                                                                                                                                                              | chart + repo CLAUDE.md                                 |
| D5  | infra CLAUDE.md points to `docs/architecture/rfc-gxy-cassiopeia-ga.md` as live                                                           | file lives at `.archive/2026-05-26-prose-trim/rfcs-shipped/rfc-gxy-cassiopeia-ga.md`                                                                                                                                                                                              | CLAUDE.md §Doc-ownership (fixed alongside this report) |
| D6  | launchbase CNPG not version-pinned (no `.deploy-flags.sh`) vs cassiopeia pinned 0.28.0                                                   | install-time latest                                                                                                                                                                                                                                                               | `k3s/gxy-launchbase/apps/cnpg-system/`                 |
| D7  | Dormant woodpecker config still in tree post-retire                                                                                      | `.woodpecker/caddy-s3-build.yaml` (manual-only)                                                                                                                                                                                                                                   | retired 2026-05-03                                     |
| D8  | ADR-004 §Fallback still says "deploy Zitadel on gxy-triangulum"; ADR-016 names repo `freeCodeCamp/uploads` (real = artemis)              | stale ADR bodies (noted in amendment trail)                                                                                                                                                                                                                                       | Universe ADRs                                          |
| D9  | Hostname-zone drift                                                                                                                      | `uploads.freecode.camp` should be `uploads.freecodecamp.net` (internal tool) — deferred                                                                                                                                                                                           | ADR-009 / ADR-016                                      |
| D10 | Broken / inconsistent runbook refs                                                                                                       | `05-r2-keys-rotation.md` → `docs/rfc/gxy-cassiopeia.md §4.4` (never existed); `07-…restore.md` secret paths use subdir style ≠ flat convention                                                                                                                                    | runbooks 05 / 07                                       |
| D11 | artemis repo-creation shipped-but-dark                                                                                                   | `/api/repo*` handlers built but Apollo-11 App creds unwired in prod chart → routes unmounted. Live repo-create runs via the windmill Apollo flow instead (duplication)                                                                                                            | artemis `secret-env.yaml`                              |

D2-D4, D6-D11 are **not fixed by this report** — recorded for a follow-up hygiene pass. D5 fixed in the same commit batch (the report's own pointer).

## 8. In-flight + parked

- **infra:** active on `feat/veritas` (chart pivots + runbook-08 add-then-revert). No open dossier. Last sprint merged + deployed 2026-05-25 (artemis 0.3.0, universe-cli 0.7.0).
- **windmill:** one live dossier (Phase 4 EA-baseline); `main` ahead of origin (run `git -C ~/DEV/fCC-U/windmill rev-list --count @{u}..HEAD`). Blocked task on a global-hook overmatch, not repo logic. Open: `infra-secrets/windmill/.env.sample` missing `APOLLO_*`; CI may never have been enabled.
- **veritas:** active source repo, ahead of origin (run `git -C ~/DEV/fCC-U/veritas rev-list --count @{u}..HEAD`).
- **Unspawned successor dossiers:** `terraform-absorb` (re-add 3 dropped TF workspaces post-deploy), `bare-promote-deprecation` (artemis, telemetry-gated), `universe-reorg`.
- **Gating triggers (none fired):** triangulum ← first containerized constellation OR >$2.5k/mo cloud spend (now ≈$432) OR >50 constellations; backoffice ← auth epic complete; Zot / supply-chain ← first container image to protect.

## Relationship to other docs

- [`adr-drift-2026-05-10.md`](./adr-drift-2026-05-10.md) — prior ADR-vs-reality snapshot; all actions closed. This report supersedes its live-state framing, not its historical record.
- Universe `decisions/018-early-access-baseline.md` + `019-cassiopeia-shared-services.md` — canonical forward design. This report records execution state against them.

## Out of scope

- Fixing drift D2-D4, D6-D11 (follow-up hygiene pass).
- Trimming the Universe ADR/spike doc surface (separate, operator-requested).
- Branch push state (operator-owned).
