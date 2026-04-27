# Sprint 2026-04-26 — HANDOFF (history log)

Append-only dated log of what shipped each session. **Not a resume doc** — see [`STATUS.md`](STATUS.md) for live cursor and resume prompt. Plan + decisions live in [`PLAN.md`](PLAN.md) + [`DECISIONS.md`](DECISIONS.md).

Convention:

- One entry per session at top of "Journal".
- Dated `YYYY-MM-DD — <one-line summary>`.
- Body: what shipped, what failed, what blocked, links to commits.
- Never edit past entries — append correction entry referencing the original.

## Journal

### 2026-04-27 — T34 live verify GREEN — sprint G1 ticks

Operator-gated live verify against the 2026-04-27 T34 closure
(commit `0b8d6238`). Five mid-flight fixes surfaced before the smoke
went green; all retroactively committed under the T34 closure scope:

**Closing commits (T34 live-verify chain):**

- infra `feat/k3s-universe`: `da5a5855` — `fix(justfile): sops --config for mirror-artemis-secrets`
  - sops walks `.sops.yaml` from input file's parent up; recipe ran from infra repo root → no `.sops.yaml` found → `--config` flag added.
- infra `feat/k3s-universe`: `cee53e5d` — `feat(artemis): drop TLS — CF Flexible (cassiopeia parity)` (already in T34 closure scope; surfaced during live preflight when cassiopeia caddy chart confirmed CF zone is on Flexible SSL, no origin cert at k8s layer).
- infra `feat/k3s-universe`: `b4567c10` — `refactor(justfile): unify deploy verb; drop artemis slop`
  - Operator flagged that `artemis-deploy` and `mirror-artemis-secrets` recipes were one-off slop. Refactor: smart-dispatch `deploy` recipe (helm if `charts/`, kustomize if `manifests/`, both if both), per-app `apps/<app>/.deploy-flags.sh` convention for extras, mirror logic moved inline to runbook §5. CRIT entries landed in `infra/CLAUDE.md` + sprint PLAN; slop-sweep itself executed early.
- infra `feat/k3s-universe`: `5f725a09` — `fix(artemis): env keys + secure-headers MW + CNP`
  - Three live-deploy bugs:
    1. **Wrong env key names + placeholders.** Chart used `ALIAS_PRODUCTION` / `ALIAS_PREVIEW` and `{site}/deploys/{deployId}/`. Artemis expects `ALIAS_PRODUCTION_KEY_FORMAT` / `ALIAS_PREVIEW_KEY_FORMAT` and `<site>` / `<ts>-<sha>` placeholders. Pod CrashLoopBackOff at startup with `invalid DEPLOY_PREFIX_FORMAT … must contain <site> and <ts>-<sha>`.
    2. **Missing secure-headers Middleware.** HTTPRoute referenced `secure-headers` Middleware in artemis ns; chart only created `artemis-ratelimit`. Each gxy-management app creates its own `secure-headers` per windmill / zot / argocd precedent. Added `templates/middleware-secure-headers.yaml`.
    3. **Vanilla NetworkPolicy blocked Traefik (hostNetwork) cross-node.** Cluster CNI = Cilium; vanilla `networking.k8s.io/v1` NetworkPolicy `namespaceSelector` cannot resolve hostNetwork pods to their k8s namespace → blocked Traefik on 2 of 3 nodes (1 of 3 worked = same-node). Converted chart to `CiliumNetworkPolicy` with `fromEntities: [cluster, host]` matching cassiopeia caddy precedent.
- infra `feat/k3s-universe`: `813d0171` — `fix(artemis): R2 site key uses FQDN`
  - **Contract mismatch between artemis and cassiopeia caddy r2_alias module.** Caddy's `parseSiteAndAlias` returns site = `<sitePrefix> + .<rootDomain>` (full FQDN — `docker/images/caddy-s3/modules/r2alias/host.go`). Cache key `<bucket>/<site-fqdn>/<alias>` → S3 key `<site-fqdn>/<alias>`. Artemis was writing bare `<site>/preview` (no `.freecode.camp` suffix). Fix landed in chart values: `ALIAS_PRODUCTION_KEY_FORMAT=<site>.freecode.camp/production`, same for preview, same for `DEPLOY_PREFIX_FORMAT`. Comment in `values.production.yaml` references the caddy source line for future debug.

Plus operator-side action:

- **artemis GHCR package visibility flipped to public.** Repo stays
  PRIVATE; only the OCI package goes public. Anonymous Bearer flow
  required for kubelet pull (no imagePullSecret plumbing). Matches
  caddy-s3 precedent. Decision irreversible per GitHub policy
  (public packages cannot revert to private).

**Phase 5 E2E smoke — GREEN end-to-end** (`scripts/phase5-proxy-smoke.sh`):

```
[1/8] preflight                                   ✓
[2/8] POST /api/deploy/init  site=test            ✓ → deployId=20260427-064419-fe7342d
[3/8] PUT  /api/deploy/{id}/upload                ✓
[4/8] POST /api/deploy/{id}/finalize mode=preview ✓ → https://test.preview.freecode.camp
[5/8] preview content marker match                ✓
[6/8] POST /api/site/test/promote                 ✓ → https://test.freecode.camp
[7/8] prod content marker match (≤2min SLO D38)   ✓
[8/8] PASS  marker: phase5-20260427-064417-14413
```

`/api/whoami` (GH token) → `{"authorizedSites":["test"],"login":"raisedadead"}` confirms full GH OAuth Bearer + team-membership probe path.

**G1 state (sprint-2026-04-26):** ticks. All sprint code lanes
closed; all operator-gated live verifies green. Phase 2 (npm publish
`@freecodecamp/universe-cli@0.4.0` + T22 live verify) unblocked.

**Lessons learned — feed forward (CRIT-grade):**

1. **Pattern study covers the whole adjacent app, including templates the candidate template depends on.** The `secure-headers` Middleware is an HTTPRoute filter ref; missed by reading only the chart templates list, present only when reading the manifests of windmill / argocd / zot. Future rule (added to `infra/CLAUDE.md` §CRIT in a follow-up commit): when a chart references a Middleware by name, grep adjacent apps for that middleware definition + ensure the chart provides one in its own ns.
2. **Cluster CNI dictates which NetworkPolicy CRD applies.** This cluster runs Cilium → must use `CiliumNetworkPolicy` (not vanilla `networking.k8s.io/v1`) for hostNetwork-aware ingress. Cassiopeia caddy precedent was visible in `caddy/charts/caddy/templates/networkpolicy.yaml`. Future rule: read existing NetPol patterns in adjacent apps before writing new.
3. **Service contract validation is dispatch-time work, not deploy-time.** The artemis env key shape (`*_KEY_FORMAT` + `<site>`/`<ts>-<sha>` placeholders) and the R2 site key contract (FQDN vs bare) were both findable in artemis source + cassiopeia caddy source. Future rule: read the service's `.env.sample` AND its config-loader source AND the consumer's contract module BEFORE writing chart `env:` values. Compare keys character-by-character.
4. **Deploy-time pod readiness gating.** Phase5 smoke ran while artemis was still rolling out → 504 on init. The `just deploy` recipe rolls helm + kubectl rollout status (artemis-deploy had `--timeout=120s` builtin); generic `deploy` lacks that wait by design. Operators should bracket with explicit `kubectl rollout status` before smoke-test invocation. Smoke script could also poll-then-fail. Park as `phase5-smoke` enhancement.

**Final infra commit chain (this verify cycle, all on `feat/k3s-universe`):**

- `0b8d6238` feat(artemis): close T34 — chart + Path X reframe
- `62dbb4e2` docs(sprints): T34 reconcile <incoming> → 0b8d6238
- `cee53e5d` feat(artemis): drop TLS — CF Flexible (cassiopeia parity)
- `8a1a2375` docs(crit): justfile slop discipline + slop sweep park
- `ab241418` docs(claude): force-track + CRIT justfile slop entry
- `da5a5855` fix(justfile): sops --config for mirror-artemis-secrets
- `b4567c10` refactor(justfile): unify deploy verb; drop artemis slop
- `5f725a09` fix(artemis): env keys + secure-headers MW + CNP
- `813d0171` fix(artemis): R2 site key uses FQDN

Push owned by operator (per session covenant). Branch ahead of
origin by 35+ commits.

### 2026-04-27 — T34 closed: artemis chart + Path X reframe (drop Tailscale, drop Caddy/cassiopeia hop)

T34 worker session in `~/DEV/fCC/infra` (branch `feat/k3s-universe`)
shipped the artemis Helm chart, justfile recipes, phase5 E2E smoke,
operator runbook, and gxy-management flight-manual section. Mid-flight
two architectural reframes landed:

**Reframe A — RUN-residency clause (image pull path).** Operator
flagged: artemis chart cannot pull from `zot.management.tailscale.fcc`
(zot lives on the same galaxy → cluster-wipe rebuild deadlocks).
Documented as 2026-04-27 amendment to the 2026-04-26 build-residency
field-note entry; auto-memory feedback file added; TODO-park
T-build-residency Phase 1 audit scope extended to cover
`image.repository` fields in pillar charts.

**Reframe B — Path X (drop Tailscale + Caddy/cassiopeia hop).**
Operator flagged: dispatch's proposed
`uploads → CF → Caddy/cassiopeia → Tailscale → artemis` conflicts
with ADR-009 (Tailscale Operator rejected). Reframe to
`uploads → CF → gxy-management public IP → Traefik Gateway/HTTPRoute
→ artemis Service` — windmill / zot / argocd pattern, single galaxy
hop. Caddy/cassiopeia stays on `*.freecode.camp` tenant traffic only,
no involvement in `uploads.freecode.camp` path. Caddy values change
in original dispatch dropped as N/A.

**Reframe C — auth (path A).** Confirmed artemis = programmatic API
(GH OAuth Bearer per ADR-016, no CF Access). Compensating controls:
chart-internal Traefik rate-limit Middleware + CF WAF rules.

**Closing commits:**

- infra `feat/k3s-universe` (not pushed): `0b8d6238` —
  `feat(artemis): close T34 — chart + Path X reframe`
  (single closure commit covers chart + recipes + smoke + runbook +
  flight-manual + sprint-doc state flip + DECISIONS amend block +
  TODO-park RUN-residency amend + Universe field-note RUN-residency
  entry + auto-memory feedback file + .prettierignore for chart
  templates)

**Files landed (this commit):**

```
.prettierignore                                                     (NEW — exclude helm template trees from Prettier)
docs/TODO-park.md                                                   (RUN-residency amend block on T-build-residency entry)
docs/runbooks/deploy-artemis-service.md                             (NEW — operator runbook)
docs/flight-manuals/gxy-management.md                               (NEW §Phase 7 Artemis)
docs/sprints/2026-04-26/{STATUS,PLAN,DECISIONS,HANDOFF}.md          (close + amend)
docs/sprints/2026-04-26/dispatches/T34-caddy-dns-smoke.md           (Path X amend + close)
justfile                                                            (NEW recipes: artemis-deploy, mirror-artemis-secrets, phase5-smoke)
k3s/gxy-management/apps/artemis/charts/artemis/Chart.yaml           (NEW)
k3s/gxy-management/apps/artemis/charts/artemis/values.yaml          (NEW — chart defaults, fail-fast required helpers)
k3s/gxy-management/apps/artemis/charts/artemis/templates/_helpers.tpl
k3s/gxy-management/apps/artemis/charts/artemis/templates/namespace.yaml
k3s/gxy-management/apps/artemis/charts/artemis/templates/configmap.yaml      (env + sites.yaml ConfigMaps)
k3s/gxy-management/apps/artemis/charts/artemis/templates/secret-env.yaml     (5 secret env keys, sops overlay)
k3s/gxy-management/apps/artemis/charts/artemis/templates/secret-tls.yaml     (CF Origin cert, sops overlay)
k3s/gxy-management/apps/artemis/charts/artemis/templates/middleware-ratelimit.yaml
k3s/gxy-management/apps/artemis/charts/artemis/templates/gateway.yaml
k3s/gxy-management/apps/artemis/charts/artemis/templates/httproute.yaml      (web→redirect-https + websecure→Service)
k3s/gxy-management/apps/artemis/charts/artemis/templates/service.yaml
k3s/gxy-management/apps/artemis/charts/artemis/templates/deployment.yaml
k3s/gxy-management/apps/artemis/charts/artemis/templates/networkpolicy.yaml
k3s/gxy-management/apps/artemis/values.production.yaml              (image digest pin, replicas, prod env, ratelimit tunables)
k3s/gxy-management/apps/artemis/README.md                           (chart docs)
scripts/phase5-proxy-smoke.sh                                       (NEW — E2E init/upload/finalize/preview/promote/prod)
~/.claude/auto-memory/feedback_universe_run_residency.md            (cross-repo — auto-memory; not part of infra commit)
~/DEV/fCC-U/Universe/spike/field-notes/infra.md                     (cross-repo — RUN-residency entry; separate Universe commit)
```

**Gates evidenced (worker handoff):**

- `helm lint charts/artemis` → 1 chart linted, 0 failed
- `helm template artemis charts/artemis ...` → 12 resources render
  (Namespace, NetworkPolicy, 2× Secret, 2× ConfigMap, Service,
  Deployment, Gateway, 2× HTTPRoute, Middleware) — `[INFO]
Chart.yaml: icon is recommended` informational only
- `bash -n scripts/phase5-proxy-smoke.sh` → OK
- `just --list` → `artemis-deploy`, `mirror-artemis-secrets`,
  `phase5-smoke` recipes registered

**Operator-gated actions (G1 tick):**

1. CF dashboard — mint Origin cert for `*.freecode.camp` (if not
   already minted by cassiopeia caddy work — verify and reuse if so).
2. Export `ARTEMIS_TLS_CERT` + `ARTEMIS_TLS_KEY` paths.
3. `just mirror-artemis-secrets` — produces sealed YAML overlay at
   `infra-secrets/k3s/gxy-management/artemis.values.yaml.enc`.
   Commit + push from infra-secrets.
4. `git -C ~/DEV/fCC-U/artemis pull --ff-only` — ensure
   `config/sites.yaml` current.
5. `cd ~/DEV/fCC/infra && just artemis-deploy` — helm install.
6. `curl -fsS https://uploads.freecode.camp/healthz` — expect
   `{"ok":true}`.
7. `just phase5-smoke` — E2E green ⇒ G1 ticks.

**Out-of-scope deferrals (parked):**

- CF Access service-token hardening for artemis (Path C from auth
  decision menu) — defer; revisit post-G2 if abuse appears. Rate-
  limit + WAF compensating controls are the v1 surface. (Park location:
  see TODO-park §Application config later sprint.)
- Single-envelope unification (drop dotenv envelope OR drop YAML
  overlay — currently mirror via `just mirror-artemis-secrets`).
  Park alongside dual-envelope fragility analysis.
- `gxy-management` cluster-wipe rebuild rehearsal with zot
  unreachable (RUN-residency operational invariant). Add to
  flight-manual rebuild calendar.

**Sprint state delta this commit:**

- PLAN top-level dispatch matrix row T34 → `[x] done`.
- STATUS Open table T34 → `done` (operator-gated).
- STATUS header — `Updated:` line refreshed; ahead-of-origin bumped.
- STATUS concurrency plan — all code lanes closed; only operator
  gates remain for G1.
- DECISIONS — D43 amendment block (Path X reframe; RUN-residency
  clause; auth Path A confirmed).
- HANDOFF — this entry.

### 2026-04-27 — artemis sites.yaml seeded (T34 precondition #5; broken ownership)

Operator delegated: "do it for me." Governor session created the
seed in artemis repo per realigned T34 §step 5 (commit `c9dd8817`,
prior entry).

**Closing commits:**

- artemis `main` (not pushed): `49d2f32` — `feat(config): seed sites.yaml + un-gitignore`
  - Created `config/sites.yaml` with single-site seed for `test`
    site → `[staff]` (narrowest team while smoke shakes out;
    enables T34 §smoke retarget against `test.freecode.camp` +
    `test.preview.freecode.camp`)
  - Removed `config/sites.yaml` from `.gitignore` — drift from
    ADR-016 §sites.yaml lifecycle (line 178: "PRs reviewed by
    platform team" → committed source of truth, not operator-private).
    T31 worker had gitignored it as runtime/local config; ADR
    explicit otherwise.
  - In-file comment block documents schema, lifecycle, fCC GitHub
    teams reference (verified via `gh api` 2026-04-27), and parked
    follow-up cross-ref to TODO-park §Application config.

- infra `feat/k3s-universe`: `<incoming>` — `docs(sprints): seed artemis sites.yaml — T34 precondition`
  - STATUS Shipped log gains artemis `49d2f32` + `7d6eed3` (CI fix
    that landed post-T31 closure; matches GHCR `:sha-7d6eed3c...`
    image)
  - STATUS header — preconditions 5/5 GREEN
  - HANDOFF — this entry

**fCC GH org teams reality (verified `gh api /orgs/freeCodeCamp/teams`):**

```
bots, classroom, curriculum, dev-team, devdocs, i18n, mobile,
moderators, none, ops, staff
```

`platform` team **does not exist** in `freeCodeCamp` org. Operator's
mental model used "platform" generically. Seed uses `staff` (narrowest
match for "platform team / operator" semantics). Operator may either:

- create `platform` team in freeCodeCamp org for cleaner separation
  of concerns; then re-seed `config/sites.yaml` with both teams
- continue using `staff` as universal authorized team

Either path: edit artemis `config/sites.yaml`, PR + merge in artemis
repo, `just helm-upgrade gxy-management artemis` re-renders
ConfigMap.

**T34 fire-readiness:** all 5 preconditions GREEN (DNS, OAuth App,
GHCR image, sops envelope, sites.yaml seed). T34 worker can fire.

### 2026-04-27 — sites.yaml ADR realignment (option A; T34 §step 5 fix)

**Drift correction.** Prior T34 §step 5 (commit `5e42cc80`,
2026-04-27 earlier) pinned `sites.yaml` source-of-truth to
`infra/k3s/gxy-management/apps/artemis/sites.yaml`. Wrong per
ADR-016 §sites.yaml lifecycle (line 178) — source of truth is
**artemis repo** `config/sites.yaml`; infra-side ConfigMap is the
**render target**, not the source.

**Operator zoom-out.** Operator surfaced cross-cutting concerns +
"we're drifting from ADR goals." Reset performed: re-read ADR-016

- ADR-004 + ADR-008. Identified 4 drift items (path location,
  proposed schema slim, premature migration ladders, CLI-only
  register endpoint violating interaction-agnostic tenet).

**Decision matrix presented:** A (hold ADR as written, fix path
drift only), B (slim schema — fixed teams env + flat sites
allowlist; needs ADR-016 amendment + artemis worker re-fire),
C (KV-backed register; multi-ADR design pivot, post-MVP).

**Operator picked A** for sprint 2026-04-26 close (unblock T34;
zero artemis re-fire risk). B + C parked together as single
follow-up dispatch — embedded SQLite/lightweight KV registry +
schema slim, both honor ADR-016 §trust-collapse + vendor-neutral
tenets.

**Closing commits:**

- infra `feat/k3s-universe`: `<incoming>` —
  `docs(sprints): T34 sites.yaml ADR realign`
  - T34 dispatch §step 5 rewritten — source-of-truth re-pinned to
    artemis repo `config/sites.yaml`; infra render target via Helm
    `--set-file` from operator's local checkout (v1 default);
    ArgoCD multi-source documented as future path; image-bake
    rejected (defeats fsnotify hot-reload locked in ADR)
  - Operator-action block updated to artemis-repo-first workflow
  - This HANDOFF entry
  - STATUS shipped log + ahead-origin count
- infra `feat/k3s-universe`: `<incoming-2>` —
  `docs(todo-park): artemis sites slim + embedded KV`
  - New §Application config section in TODO-park
  - Combined entry for B (schema slim) + C (embedded SQLite/KV
    registry) — single future dispatch covers both
  - Activation triggers + ADR amendment requirements documented

**No artemis code changed; no ADR amendments filed.** Pure sprint-
doc realignment. T34 fire-readiness preserved (operator action
shifts from "edit infra path" to "seed artemis-repo file" — same
half-line edit, different repo).

**Cross-ref.** ADR-016 §sites.yaml lifecycle (line 178);
§Authn/authz Q11 (line 35); §design tenet interaction-agnostic
(line 41); §trust-collapse (line 219). ADR-008 §Storage matrix
(no KV primitive in current set). ADR-004 §scope-out 2026-04-26
(BetterAuth governs constellation auth, not platform tools).

### 2026-04-27 — pillar audit pass + 3 follow-up commits (broken ownership)

Operator-requested grounded-truth audit across all 5 repos touched by
the static-apps proxy pillar. 5 parallel Explore subagents, one per
repo + Universe ADRs. Reports landed at
`docs/sprints/2026-04-26/audit/{artemis,universe-cli,windmill,infra,universe-adrs}.md`.

**Verdict roll-up:** GREEN with 1 known YELLOW gap (T32 addendum
already filed) + 2 documentation drifts (windmill T11 boneyard
headers + Universe spike-plan artemis placement). No G1 blockers;
T34 fire-ready.

**Three follow-up commits landed (broken ownership at operator
request — governor session edited worker-team repos directly):**

1. **windmill `main`: `f8e99b9`** — `chore(static): boneyard T11 files + fmt pass`
   - Boneyard headers added to T11 source files marking
     `provision_site_r2_credentials.{ts,test.ts,script.yaml}` archaeology
     post-2026-04-26 pivot
   - Resource-type `c_woodpecker_admin.resource-type.yaml` description
     updated with retired marker (`u/admin/cf_r2_provisioner` left
     alive — proxy reuses)
   - oxfmt save-hook reformatted file bodies (266 lines) — included in
     same commit; tests 412/412 still green
   - Files do NOT participate in live wmill flow; archive-only marker

2. **Universe `main`: `c5a1144`** — `docs(spike-plan): add artemis on gxy-management`
   - Galaxy placement matrix gains artemis row (gxy-management,
     Sprint 2026-04-26, Option A locked)
   - "What NEVER moves" bullet added — artemis stays on gxy-management
   - Universe-team owns spike-plan; operator approved governor edit

3. **infra `feat/k3s-universe`: `<incoming>`** — `docs(sprints): T34 sites.yaml + audit trail`
   - T34 dispatch §step 5 rewritten — sites.yaml landing path pinned
     to `infra/k3s/gxy-management/apps/artemis/sites.yaml` (chart-
     internal default; plain YAML; hot-reload via fsnotify; rotation
     via PR+merge cycle)
   - This HANDOFF entry

**Cross-ref.** Audit reports remain on disk for follow-up. Operator
reads each for full file:line refs + tables.

### 2026-04-27 — T32 addendum filed: bake `UNIVERSE_GH_CLIENT_ID` default

Operator verify pass 2026-04-27 (artemis GHCR image + CF DNS +
GH OAuth App) flagged design gap in T32 closure: `login.ts:50` reads
`UNIVERSE_GH_CLIENT_ID` from env at runtime; npm-published v0.4
binary refuses `universe login` out-of-the-box on user laptops. OAuth
client_id is public-grade (device flow, no client_secret) — bake
default in source matches `gh` / `vercel` / `supabase` CLI patterns.
Operator approved bake-at-build 2026-04-27.

**Commits:**

- infra `feat/k3s-universe`: `<incoming>` — `docs(sprints): T32 addendum bake gh client_id` (T32 dispatch §Addendum 2026-04-27 + STATUS Open table note + STATUS resume prompt for addendum worker)

**Why correction-style append (not edit of T32 closure entry).**
T32 main work closure (above entry) accurately reflects what
shipped — main rewrite + closure notes. Addendum is **new work**
deferred from closure scope; per HANDOFF discipline (never edit
past entries) appended as standalone correction.

**Scope (single follow-up commit on `feat/proxy-pivot`).** See T32
dispatch §Addendum 2026-04-27. Fold or new `src/lib/constants.ts`,
`login.ts` env-fallback wiring, test for env-unset case, README +
CHANGELOG (`0.4.0-alpha.2`).

**Blocks G2 (npm publish), not G1.** Can fire in parallel with T34
or after T34 smoke green; G1 close does not depend.

**Cross-ref.** Verify report 2026-04-27 (governor session) confirmed
artemis envelope `GH_CLIENT_ID` matches the live OAuth App
(`Iv23li...`, 20 chars; same value goes into the source constant).

### 2026-04-27 — T32 closed: universe-cli v0.4 rewrite

T32 worker session in `~/DEV/fCC-U/universe-cli` (branch
`feat/proxy-pivot`) shipped CLI v0.4 — namespaced static surface
(`universe login`, `whoami`, `static deploy/promote/rollback/ls`)
per ADR-016 §Authn/authz + amended T32 dispatch §CLI surface (CLI
ns pivot 2026-04-27). Worker discipline clean: own repo + own
dispatch Status flip already committed at `infra@b1f1f3e4`.

**Closing commits:**

- universe-cli `feat/proxy-pivot` (not pushed): `24d6fa1` — T32 closure (CLI v0.4 rewrite)
- infra `feat/k3s-universe`: `b1f1f3e4` — `docs(sprints): close T32 — universe-cli@24d6fa1` (worker-flipped Status header)

**Gates evidenced (worker handoff):**

- `pnpm test` → 265/265 across 23 files
- `pnpm lint` (oxlint) → 0 warn / 0 err
- `pnpm typecheck` → clean
- `pnpm build` → ESM 47.63 KB / CJS 859.32 KB; no Woodpecker refs in dist
- AWS SDK deps purged (4 packages removed — proxy contract holds R2 creds)

**In-scope deferrals (recorded in dispatch closure notes):**

- per-file PUT vs multipart upload — wording clarified in dispatch
- OIDC slot stub — placeholder retained for future GHA / WP OIDC wiring
- husky `tsc` gate — pre-commit hook added

**Out-of-scope deferrals (parked):**

- `oxfmt --check` not run — package never installed in repo despite
  T32 dispatch + T33 HANDOFF mention. Follow-up dispatch needed:
  add `oxfmt` to `devDependencies` + wire into `package.json` scripts
  - husky pre-commit. Parked at `docs/TODO-park.md` §Toolchain.

**Sprint state delta this commit (infra):**

- PLAN top-level task chain row T32 → `done` w/ `universe-cli@24d6fa1`.
- PLAN dispatch matrix row T32 → `[x] done`.
- STATUS Open table T32 → `done` (oxfmt deferred); Shipped section
  gained universe-cli `24d6fa1` + worker close `b1f1f3e4` + sops
  T34 update `a7bfbc4c` + R2 GC TODO-park `e99da31b`; concurrency
  plan rewritten — only T34 lane open (blocks on artemis GHCR image).
- HANDOFF — this entry.

### 2026-04-27 — T22 closed: cleanup cron Windmill flow

T22 worker session in `~/DEV/fCC-U/windmill` shipped 7d-retention
sweep flow per dispatch §Behavioral gates + ADR-007 retention + D39
hard-7d + D41 admin S3 keys. Worker discipline clean: own repo +
own dispatch Status flip (already committed at `infra@a967cf24`).

**Closing commits:**

- windmill `main` (not pushed): `016a868` — `feat(static): add cleanup cron for R2 deploys (T22)`
- infra `feat/k3s-universe`: `a967cf24` — `docs(sprints): close T22 cleanup cron (windmill)` (worker-flipped Status header)

**Files landed (windmill `f/static/`):**

- `cleanup_old_deploys.{ts,test.ts,script.yaml,script.lock,schedule.yaml}`
- `package.json` + `pnpm-lock.yaml` (`@aws-sdk/client-s3@3.1037.0`)

**Gates evidenced:**

- Tests: 12 vitest cases new (RED → GREEN); full suite 412/412 green across 30 files
- Lint/format: `oxfmt --check` + `oxlint` clean; `tsc` clean for T22 files (38 pre-existing errors unchanged — out-of-scope drift)
- `just plan` dry-run: 4 adds, 0 deletes (script + lock + script.yaml + schedule.yaml)
- `windmill-reviewer` agent verdict CLEAR; 3 advisories applied: atomic CAS via `IfNoneMatch: "*"`; schedule skill marker; Resource handoff documented

**Operator-owned post-deploy gates (per closure block):**

1. Provision Resource `u/admin/r2_admin_s3` (native `s3` type) — admin R2 S3 keys
2. `runScriptPreviewAndWaitResult` MCP with `dry_run=true` against live Windmill
3. Flip `schedule.enabled: true` (still `dry_run=true`) → review pending list
4. Switch `args.dry_run: false` for live retention sweep

**Sprint state delta this commit (infra):**

- PLAN top-level task chain row T22 → `done`.
- PLAN dispatch matrix row T22 → `[x] done`.
- STATUS Open table T22 → `done` + operator-gates note; Shipped section
  gained windmill block (`016a868`) + worker close (`a967cf24`) + CLI
  ns pivot commit (`22140aed`); concurrency plan rewritten (CLI ns
  pivot landed pre-T32; T32 + T34 are remaining lanes).
- HANDOFF — this entry.

### 2026-04-27 — CLI surface namespace pivot (pre-T32 fire)

Operator caught design risk before T32 worker fired: top-level
`universe deploy` / `promote` / `rollback` / `ls` would lock CLI into
static-app semantics, forcing breaking change for future surfaces
(workers, dbs, queues). Pivot decision: namespace deploy verbs under
`static` subcommand; reserve top-level `universe` for cross-cutting
auth + identity + version commands.

**Closing commits:**

- Universe `main` (not pushed): `df255b9` — `docs(decisions): D016 amend CLI namespace static`
  (3rd dated amendment block in ADR-016)
- infra `feat/k3s-universe`: `22140aed` — `docs(sprints): pivot CLI surface to static ns`
  (T32 dispatch §CLI surface rewritten; PLAN sprint goal +
  G2 gate + success criteria 2/7/8 namespaced; README goal namespaced;
  STATUS governor-resume namespaced; DECISIONS amendment-log entry)

**Pre/post surface delta:**

| Pre                 | Post                          |
| ------------------- | ----------------------------- |
| `universe deploy`   | `universe static deploy`      |
| `universe promote`  | `universe static promote`     |
| `universe rollback` | `universe static rollback`    |
| `universe ls`       | `universe static ls`          |
| `universe login`    | `universe login` (top-level)  |
| `universe logout`   | `universe logout` (top-level) |
| `universe whoami`   | `universe whoami` (top-level) |

**T32 worker scope add:** single text fix in T33-shipped
`docs/platform-yaml.md` (`universe deploy` → `universe static deploy`)
folded into T32 commit (universe-cli repo, worker-owned). Governor did
not cross repo lines.

**Out-of-band drift noted:** infra `docs/TODO-park.md` carries an
unstaged "T-build-residency" parking entry from a separate session
(not pivot scope, not T22 scope). Left unstaged for operator triage.

### 2026-04-27 — T31 closed: artemis Go svc greenfield scaffold

T31 worker session in `~/DEV/fCC-U/artemis` (greenfield repo) shipped
full Go microservice scaffold per dispatch §Files + §API surface +
§Acceptance. Single commit allowed for greenfield init.

**Closing commit (artemis `main`, NEW remote, not pushed):**

- `861e4c4` — `feat: initial artemis service scaffold`

**Worker dispatch close commit (infra `feat/k3s-universe`):**

- `7465ce41` — `docs(sprint): close T31 — artemis@861e4c4` (worker
  flipped dispatch Status header per multi-session discipline; governor
  reconciles PLAN matrix + STATUS + this HANDOFF in separate commit
  below).

**Sprint state delta this commit (infra):**

- PLAN top-level task chain row T31 → `done`.
- PLAN dispatch matrix row T31 → `[x] done` (also corrected area label
  `uploads (new repo)` → `artemis (new repo)` + dispatch path).
- STATUS Open table T31 → `done`; Shipped section gained artemis block
  - `7465ce41` worker close + this reconciliation commit; concurrency
    plan rewritten (T34 + T32 unblocked).
- HANDOFF — this entry.

**Unblocks:** T34 (Caddy reverse proxy + DNS + smoke retarget) — needs
first GHCR image tag from artemis CI before Helm install (operator:
`gh workflow run` on artemis repo). T32 (universe-cli v0.4 commands)
fully unblocked — both artemis API contract live + T33 schema landed.

### 2026-04-27 — T33 closed: `platform.yaml` v2 schema + validator + doc

T33 worker session in `~/DEV/fCC-U/universe-cli` shipped v2 schema
strip-and-replace per D016 §`platform.yaml` schema + dispatch
acceptance gates. Branch `feat/proxy-pivot` cut fresh off `main`
(per Q14); `feat/woodpecker-pivot` archaeology untouched.

**Closing commits (universe-cli `feat/proxy-pivot`, not pushed):**

- `8788648` — `feat(lib): add platform.yaml v2 schema + parser`
- `5d7b6ef` — `docs(platform-yaml): add v2 schema reference + migration`

**Files landed:**

- `src/lib/platform-yaml.schema.ts` — zod v2 schema (strict, prefault for nested defaults)
- `src/lib/platform-yaml.ts` — `parsePlatformYaml(text) → {ok,value} | {ok,error}` + v1 marker detector
- `tests/lib/platform-yaml.test.ts` — 32 tests (RED → GREEN)
- `docs/platform-yaml.md` — schema reference + v0.3→v0.4 migration delta
- `CHANGELOG.md` — `[Unreleased]` BREAKING entry
- `README.md` — Configuration section + doc link

**Gates:**

- Tests: 252/252 (24 files; new file 32/32)
- Lint: 0 warn / 0 err (oxlint, 50 files)
- `tsc --noEmit`: clean

**Behavioral verified:**

- v1 markers detected: `r2`, `stack`, `domain`, `static`, `name` — error template per dispatch §Behavioral gates
- Defaults applied: `build.output: "dist"`, `deploy.preview: true`, `deploy.ignore: ["*.map","node_modules/**",".git/**",".env*"]`
- Site name validator carries D19 + D37 (lowercase, digits, single hyphens, 1–63 chars, no leading/trailing/consecutive hyphens)

**Sprint state delta this commit (infra):**

- T33 dispatch Status `pending → done`; closing-commit SHAs recorded;
  closure checklist boxes ticked.
- PLAN top-level task chain row T33 → `done`.
- PLAN dispatch matrix row T33 → `[x] done`.
- STATUS Open table T33 → `done`; Shipped section gained universe-cli
  block; concurrency plan rewritten (T33 ✅, T32 unblocked for schema
  consumption).
- HANDOFF — this entry.

**Unblocks:** T32 (universe-cli v0.4) can now consume the validator
surface for `deploy` / `promote` / `rollback` command wiring. T31 still
in-flight (independent lane). T34 still blocks on T31 image.

### 2026-04-26 (late evening) — T30 closed: ADR-016 landed in Universe

Governing session under broken-ownership authorization wrote
`~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md` per T30 dispatch
brief. ADR mirrors ADR-015 conventions; nine sections present (Context,
Decision, Architecture, Authn/Authz, R2 layout, Operational surface,
Migration, Consequences, Cross-references) plus empty Amendments block.
Q9–Q15 verbatim leans recorded; cross-refs ADR-003 / ADR-004 / ADR-008 /
ADR-009 / ADR-010 / ADR-011, RFC cassiopeia (D33–D42), and supersedes
prior-sprint dispatch T11. Universe `decisions/README.md` Accepted list
gained ADR-016 row.

**Closing commit:** `Universe@e2a9356` —
`feat(decisions): D016 deploy proxy plane`. Universe now ahead of
`origin/main` by 4 commits (3 prior field-notes + this ADR). Operator
pushes at sprint close.

**Sprint state delta this commit (infra):**

- T30 dispatch Status flipped `pending → done`; closing-commit SHA
  recorded; closure checklist boxes ticked.
- PLAN top-level task chain row T30 → `done`.
- PLAN dispatch matrix row T30 → `[x] done`.
- HANDOFF — this entry.
- DECISIONS D43 row already cross-refs `016-deploy-proxy.md` from sprint
  open; no edit required.

**Next move:** open T31 — Go scaffold + endpoints + tests in NEW
greenfield repo `~/DEV/fCC-U/uploads/`. Module path
`github.com/freeCodeCamp/uploads`. Go 1.26.2 verified on host.

### 2026-04-26 (late evening) — Sprint opens at branch point

Governing session in `~/DEV/fCC/infra` (branch `feat/k3s-universe`).

**Predecessor:** [`../archive/2026-04-21/`](../archive/2026-04-21/).
That sprint shipped Wave A.1 (Caddy `r2_alias` D35 dot-scheme + R2
single-bucket layout + Phase 4 smoke harness) green. Wave A.2
(`universe-cli@feat/woodpecker-pivot`) shipped but is archaeology
post-pivot. Wave A.3 (T11 per-site R2 token mint) SUPERSEDED by D016
deploy-proxy plane (logged in archived sprint HANDOFF 2026-04-26
evening + this sprint DECISIONS D43).

**This sprint scope:** Phase 1 sub-deliverables P1.1 + P1.7 + P1.8
(deploy-proxy svc + universe-cli v0.4 + `platform.yaml` v2 schema). T22
cleanup cron carried forward (post-T31 live verification).

**Authority:** Broken ownership for tonight's session per operator
command 2026-04-26 evening. Session governs cross-repo (Universe ADRs

- universe-cli + windmill + new uploads repo) without per-team
  round-trip. Logged here for transparency. Teams can amend post-hoc via
  append-only blocks.

**Sprint state delta this commit:**

- Created sprint dir `docs/sprints/2026-04-26/` with README, STATUS, PLAN, DECISIONS, HANDOFF (this file).
- Moved 6 active dispatches from prior sprint dir: T22 + T30–T34.
- Archived prior sprint dir → `docs/sprints/archive/2026-04-21/` (full content preserved; closure entry appended to its HANDOFF).
- DECISIONS D43 row + Q9–Q15 brainstorm rationale landed.
- PLAN: Phase 1 sub-deliverables + dispatch graph clean-rewritten (no pre/post pivot mixing).
- STATUS: live cursor focused on T30→T34→T22 sequence; resume prompt rewritten.
- README: read order + layout + predecessor pointer + authority model.

**Carries forward (commits not pushed):** all Phase 0 foundation + Wave
A.1 commits + T11 artifact at `windmill@010d577`. Operator pushes at
sprint close (4 repos + new uploads remote).

**Next move:** open T30. Write `~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md`.
Single Universe commit. Then T31 (uploads svc Go scaffold + endpoints + tests).

**Tooling verified for incoming work:** Go 1.26.2 darwin/arm64
(`/opt/homebrew/bin/go`). Universe-cli toolchain (Bun + vitest + oxfmt

- oxlint + tsup + husky) unchanged. ctx-mode v1.0.98 healthy
  (`ctx_doctor` PASS).
