# TODO Park — Deferred Items

Items deferred from the Universe static-apps MVP (sprint 2026-04-21). Each
entry lists activation trigger, owner, and linked ADR / decision.

Not a backlog — a graveyard of "not now, but when _X_". Revisit during
sprint planning when an activation trigger fires.

## Supply chain + image security

### Zot push + image registry as source of truth

- **Activation trigger:** first containerized constellation lands on
  `gxy-triangulum`. Until then, no images are built for this platform.
- **Owner:** infra team.
- **Ref:** ADR-003 (platform controller chain), ADR-005 (image registry),
  ADR-011 §Image provenance.

### cosign keyless signing (Sigstore)

- **Activation trigger:** same as Zot push. Signs the first image built by
  Woodpecker before Zot push.
- **Owner:** infra team.
- **Ref:** ADR-003 §Hardened CI pipeline, ADR-011 §Supply Chain Security.

### Grype + Trivy dual vulnerability scan

- **Activation trigger:** same as Zot push. Adds scan step between build
  and push.
- **Owner:** infra team.
- **Ref:** ADR-011 §Non-negotiable guardrails.

### Kyverno `verifyImages` admission policy

- **Activation trigger:** same as Zot push. Deploys Kyverno to every galaxy
  running containerized workloads (gxy-triangulum first).
- **Owner:** infra team.
- **Ref:** ADR-011 §Image provenance.

### Syft SBOM generation + OCI attestation

- **Activation trigger:** same as Zot push.
- **Owner:** infra team.
- **Ref:** ADR-003 §Hardened CI pipeline.

## Toolchain

### oxfmt wiring on universe-cli (T32 follow-up)

- **Activation trigger:** next universe-cli sprint touch — pre-commit
  format consistency desired before next contributor wave.
- **Owner:** universe-cli maintainer (single dispatch, ~half-day).
- **Ref:** Windmill toolchain mandate 2026-04-08 (oxfmt + oxlint +
  vitest + Bun + pnpm + husky); T32 closure HANDOFF note 2026-04-27.
- **Why parked.** T32 worker shipped CLI v0.4 with `oxlint` + `tsc`
  gates green but `oxfmt --check` not run — package never installed
  in repo despite T32 dispatch + T33 HANDOFF reference. Out-of-scope
  for T32 closure (proxy-pillar critical path); blocks G1 only if
  formatting drift surfaces during T34 smoke.
- **Scope (single dispatch).**
  - `pnpm add -D oxfmt` (devDep, pinned)
  - `package.json` scripts: `format`, `format:check`
  - husky `pre-commit`: add `oxfmt --check` before existing `tsc` gate
  - One-shot `oxfmt --write` over `src/` + `test/` (separate commit
    from wiring commit so review diffs split cleanly)
  - Verify CI workflow picks up `format:check` step
- **Open question.** Whether to gate CI on `format:check` (hard fail)
  or report-only (advisory) for first sprint after wire-in. Default
  hard fail — matches windmill repo posture.

## Automation

### Atlantis for OpenTofu PR automation

- **Activation trigger:** first IaC PR pain point — when manual
  `tofu plan` / `tofu apply` cycles block delivery. Likely after 3–5 active
  OpenTofu workspaces.
- **Owner:** infra team. Lands on `gxy-management`.
- **Ref:** ADR-001 §Component placement, ADR-002 §IaC Tooling.

### ArgoCD deployment on gxy-management

- **Activation trigger:** static-apps MVP shipped end-to-end (staff push →
  cassiopeia live). ArgoCD is not crit-path for the MVP chain; Windmill +
  Woodpecker cover the control plane until then.
- **Owner:** infra team. Lands on `gxy-management`.
- **Ref:** ADR-001 §Component placement (GitOps controller).
- **Note:** Prior release `argocd (argo-cd-9.4.17 / v3.3.6)` removed during
  the 2026-04-22 `gxy-mgmt → gxy-management` reprovision (#22). Apps were
  reproducible from git; zero state loss. Redeploy per
  `docs/flight-manuals/gxy-management.md` Phase 5.

### Build-residency migration (T-build-residency)

- **Activation trigger:** decision on sprint slot — file as dispatch in active
  sprint (currently 2026-04-26, proxy-pillar focused) or open dedicated sprint
  after current closes.
- **Owner:** infra team (audit + migrations + flight-manuals); Universe team
  (ADR ratification).
- **Ref:** `~/DEV/fCC-U/Universe/spike/field-notes/infra.md` §2026-04-26
  Build-residency rule for Universe platform pillars.

**Why parked.** Caddy-s3 GHA migration shipped under T-r2alias-dot-scheme
(closed 2026-04-26). Residency principle established in field-note.
Remaining work needs sizing + sprint placement before dispatch.

**Scope (3 phases).**

_Phase 1 — Audit (single dispatch, ~half-day)._ Discovery only. Sweep
`.woodpecker/*.yaml` across `fCC/infra`, `fCC-U/Universe`, `fCC-U/windmill`,
`fCC/freeCodeCamp`, sister repos. Classify each pipeline pillar (in Universe
recovery path) vs tenant (Universe is target). Output: table — pipeline
path · classification · target image · migration verdict.

_Phase 2 — Migrations (per-pillar dispatch, sized post-audit)._ Conditional
on Phase 1 finding additional pillars. For each: write GHA workflow per
`docker--caddy-s3.yml` pattern; validate push + tagging + `GITHUB_TOKEN`
auth; update consumers (chart values + flight-manuals); retire or downgrade
Woodpecker pipeline; smoke on real cluster.

_Phase 3 — Cleanup (one dispatch, always runs)._

- `.woodpecker/caddy-s3-build.yaml` retirement OR header-comment fix
  (suspected filename drift: comment references `caddy-s3-build.yml`,
  actual canonical is `docker--caddy-s3.yml`).
- `gxy-static` stale namespace —
  `k3s/gxy-static/apps/caddy/charts/caddy/values.yaml:4` still
  `ghcr.io/freecodecamp-universe/caddy-s3`. Cluster being retired but stays
  live during cutover. Pin to last-good SHA from old namespace + comment
  "frozen — retires Phase 3 sprint-2026-04-26"; or migrate to new
  `freecodecamp/caddy-s3` namespace if cleanup window short.
- Flight-manual sweep — `gxy-launchbase.md` cross-link to residency rule;
  any pillar moved in Phase 2.
- Field-note close-out — resolve `Next:` block in
  `Universe/spike/field-notes/infra.md`.
- Cross-ref ADR once filed.

**ADR — Universe team owned.** Field-note `Next:` proposes ADR titled
"Build residency for Universe platform pillars". Next free ADR slot:
verify against `~/DEV/fCC-U/Universe/decisions/` (D016 taken by deploy-
proxy). Boundary table + rationale already in field-note; ADR can ratify
inline or amend ADR-003 (platform controller chain).

**Sizing note.** If Phase 1 finds caddy-s3 was only pillar, T-build-residency
collapses to Phase 1 + Phase 3 — single dispatch, no sprint expansion.
Phase 2 only opens if cross-repo audit surfaces additional pillars.

## Auth + identity

### BetterAuth + Account Service

- **Activation trigger:** first 10 constellations live. Per spike defers.
- **Owner:** Universe team (builds Account Service).
- **Ref:** ADR-004 §Auth and Identity, ADR-006 §Email Delivery (auth emails
  via SES from BetterAuth).

## Galaxies

### gxy-triangulum provisioning

- **Activation trigger:** first dynamic constellation ready to ship + bare
  metal evaluation (`gxy-static-k7d.30`) closed.
- **Owner:** infra team.
- **Ref:** ADR-001 §Galaxy Topology (production galaxy, Hetzner BM).
- **Placeholder manual:** `docs/flight-manuals/gxy-triangulum.md`.

### gxy-backoffice provisioning + observability stack

- **Activation trigger:** static-apps MVP shipped + staff team onboarded.
  Second wave of platform maturity.
- **Owner:** infra team.
- **Ref:** ADR-001 §Component placement, ADR-015 §Observability (phased
  adoption: VM → ClickHouse+Vector → HyperDX → GlitchTip).
- **Placeholder manual:** `docs/flight-manuals/gxy-backoffice.md`.

## Migration

### Hetzner bare metal migration (launchbase + cassiopeia + backoffice)

- **Activation trigger:** Talos / k0s distro evaluation closes
  (`gxy-static-k7d.30`). Per D13 revised 2026-04-17, post-M5.
- **Owner:** infra team. Rebuild cluster on Hetzner, migrate state, cut
  DNS.
- **Ref:** ADR-001 §Hosting roadmap, ADR-013 §Cost Model.
- **Constraint:** do NOT open a Hetzner project or cut DNS until the distro
  evaluation lands. Early migration locks distro choice + strands etcd
  state on source cluster.

## Storage + data

### Rook-Ceph on bare metal

- **Activation trigger:** gxy-triangulum provisioned on Hetzner. Ceph
  serves production DB volumes + RGW object storage.
- **Owner:** infra team.
- **Ref:** ADR-008 §Storage Platform.

### CNPG barman-cloud plugin

- **Activation trigger:** first production DB lands on gxy-triangulum. Until
  then gxy-launchbase runs preview tier DBs where base-backup-only is fine.
- **Owner:** infra team.
- **Ref:** ADR-008 §Databases, CNPG release notes
  (native `barmanObjectStore` deprecated ≥ 1.26).

### ArgoCD multi-cluster wiring

- **Activation trigger:** gxy-launchbase or gxy-cassiopeia needs GitOps
  sync for app manifests managed centrally. Currently single-cluster on
  gxy-management is sufficient.
- **Owner:** infra team.
- **Ref:** ADR-001 §Component placement (ArgoCD multi-cluster on mgmt).

### R2 lifecycle GC for orphan deploy prefixes (artemis)

- **Activation trigger:** first prod-load on `uploads.freecode.camp` —
  when `<site>/deploys/<ts>-<sha>/` orphan prefixes accumulate from
  failed / aborted deploys (CLI re-init after mid-upload crash leaves
  old prefix behind). Estimate: when bucket size grows >10% above
  current-alias keep-set, or after 30 days of real deploy traffic.
- **Owner:** infra team. R2 lifecycle rule, NOT artemis svc concern —
  keeps artemis stateless + idempotent.
- **Ref:** ADR-016 §Failure semantics (deploy retry idempotency model);
  T31 dispatch §Retry-and-failure (no queue, no state, idempotent by
  `deployId`).
- **Scope:** R2 bucket `universe-static-apps-01` lifecycle rule
  matching prefix `*/deploys/*` with age > N days (initial guess: 14d;
  tune from observed deploy cadence). MUST NOT match alias keys
  `<site>/preview` / `<site>/production` (no `/deploys/` segment) or
  `caddy.fs.r2` cache keys.
- **Why parked.** v1 artemis is single-tenant, deploys/day not /sec.
  Orphan accumulation is cosmetic until storage cost or list-objects
  latency surfaces. Premature GC rule risks deleting last-good preview
  during long-running deploy retry windows. Defer until trigger fires
  with real traffic shape.
- **Open question.** Whether to keep last-N successful deploys per
  site (rollback depth) or rely on alias key history alone. ADR-016
  amend candidate at activation.

## Reliability

### DR runbook with tested RTO / RPO targets

- **Activation trigger:** post-M1 (after first constellation in production).
  Need measurable failure scenarios + operator rehearsal.
- **Owner:** infra team.
- **Ref:** ADR-012 §Disaster Recovery and Backups (currently Proposed /
  TBD).

## Legacy

### `ops-mgmt` teardown (legacy fCC)

- **Activation trigger:** post-Universe launch + confirmed no legacy
  dependencies remain.
- **Owner:** infra team.
- **Ref:** `fCC/infra/CLAUDE.md` §Clusters (Legacy section).

### `ops-backoffice-tools` teardown (legacy fCC)

- **Activation trigger:** same as `ops-mgmt`.
- **Owner:** infra team.
- **Ref:** `fCC/infra/CLAUDE.md` §Clusters (Legacy section).

## Reactivation workflow

When a trigger fires:

1. Remove the entry from this file.
2. Add a new epic / task in beads with the trigger summary as the spec
   rationale.
3. Amend the related ADR with a dated resolution note if applicable (see
   `GUIDELINES.md` §ADR lifecycle).
4. Link the new work back to this archive via the commit that removes the
   entry — `git log --follow docs/TODO-park.md` is the audit trail.

Do not let entries rot silently. Monthly trim reviews this file for
entries whose triggers may have fired without anyone noticing.
