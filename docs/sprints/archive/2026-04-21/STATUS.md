# Sprint 2026-04-21 — STATUS

Updated: 2026-04-26 (Pivot — D016 deploy-proxy plane; T11 SUPERSEDED) · Branch: `feat/k3s-universe` · Ahead of origin: 25 (recovery + Wave A.1 + T-r2alias)

**🔄 PIVOT 2026-04-26 evening.** Operator command — ownership model
broken; session governs end-to-end. Wave A.3 (T11 per-site R2 token
mint) **SUPERSEDED** by D016 deploy-proxy plane. Per-site R2 tokens
violate platform tenet (staff devs ship sites with only `platform.yaml`

- GitHub identity). New plane: Go microservice at
  `uploads.freecode.camp` holds sole R2 admin credential; CLI authenticates
  via GitHub identity → proxy validates team membership → proxy streams
  upload to R2 → proxy atomic-writes alias.

**✅ Wave A.1 GREEN** (pre-pivot, holds). RFC §6.6 Phase 4 exit gate
cleared. Caddy on cassiopeia rolled to
`ghcr.io/freecodecamp/caddy-s3:sha-712c6e3@sha256:e024af67…`. Serve
plane untouched by pivot.

Canonical session-roll output. Overwritten each `roll the session`. Read
this **before** PLAN.md or DECISIONS.md.

## Shipped (committed, not pushed)

Phase 0 — Foundation: (unchanged from prior roll; see HANDOFF for refs)

Sprint scaffolding (since operator's last push):

- S1–S13 (sprint scaffolding + roll commits) — see HANDOFF
- T15 — Phase 4 smoke runbook + script + recipes — `1e3b439`
- T16-T20 dispatch closures — `96b5b52` (universe-cli `feat/woodpecker-pivot` — **archaeology, never merged post-pivot**)
- G1.0a — `windmill/.env.enc` complete + Resource `u/admin/cf_r2_provisioner` + `c_cf_r2_provisioner` resource type live; infra-secrets `7d8edcb`; sprint-doc closure `22dd9e21`
- G1.0b — Woodpecker admin PAT + Resource `u/admin/woodpecker_admin` + `c_woodpecker_admin` resource type — **RETIRED post-pivot** (proxy does not push secrets to Woodpecker); resources kept on platform workspace as archaeology; infra-secrets `749ee09`; sprint-doc closure `61cc885a`
- T11 — windmill flow `f/static/provision_site_r2_credentials` artifact at `windmill@010d577` + Bug 1+2+C+D fixes (`d44783a`, `e1db0be`, `c5d9f92`, `63488b7`). **SUPERSEDED 2026-04-26 by D016.** Source retained with boneyard header (incoming commit). Live preview never run.
- G1.1 — `R2_BUCKET=universe-static-apps-01` exported in `k3s/gxy-cassiopeia/.envrc` — `6ee679bf`
- T-r2alias-dot-scheme — D35 module fix + GHA canonical builder + namespace flip + RFC scrub — `d6360c7f` `9c96a9c8` `842a7fd9` `eb5ddca1` `712c6e34` `51de48c1` `3a8d9933`
- G1.1.smoke — `phase4-20260426-080726` smoke run green
- Universe (cross-repo): field-note infra entries — `799022b`, `e48c3d7`; field-note windmill T11 entries `3d90dec`, `01e45c6`

## Open — POST-PIVOT WORK

### New dispatches (incoming commit batch — governing session)

| Dispatch                               | Repo                                                                  | Status                     |
| -------------------------------------- | --------------------------------------------------------------------- | -------------------------- |
| **T30** — D016 ADR                     | `~/DEV/fCC-U/Universe` (cross-repo, broken ownership)                 | pending → in-progress next |
| **T31** — uploads svc (Go)             | `~/DEV/fCC-U/uploads` (NEW repo, greenfield)                          | pending                    |
| **T32** — universe-cli v0.4 rewrite    | `~/DEV/fCC-U/universe-cli` branch `feat/proxy-pivot` (NEW off `main`) | pending                    |
| **T33** — `platform.yaml` v2 schema    | universe-cli `feat/proxy-pivot`                                       | pending                    |
| **T34** — Caddy + DNS + smoke retarget | infra `feat/k3s-universe`                                             | pending                    |

### Operator-owned actions (post session ship)

- DNS A record `uploads.freecode.camp` → uploads svc galaxy public IP (CF proxied)
- GHCR image build for uploads svc (CI workflow lands in T31; first build via `gh workflow run`)
- Helm install: `just helm-upgrade <galaxy> uploads` (T34 deploy)
- Smoke run: T34 retargeted script
- npm publish `@freecodecamp/universe-cli@0.4.0` after smoke green
- Cleanup deferred: `gh secret delete GHCR_PUSH_USER -R freeCodeCamp/infra`, etc. (carried from prior roll)

### Decisions to ratify with team (post broken-ownership session)

D016 baked Q9–Q15 leans. Universe team can amend post-hoc via append-only ADR amendment block. No round-trip required tonight.

### Boneyard (kept as archaeology, do not invoke)

- windmill: `f/static/provision_site_r2_credentials.{ts,test.ts,resource-type.yaml}` + Resources `u/admin/cf_r2_provisioner` (proxy reuses) + `u/admin/woodpecker_admin` (retired)
- universe-cli: branch `feat/woodpecker-pivot` (4 commits ahead of `main`, never merged)
- T21 dispatch (`.woodpecker/deploy.yaml` template) — demoted to optional reference

## Other state

- Cluster gxy-management: GREEN. Windmill restored. Will host uploads svc per T34 lean (Option A).
- Cluster gxy-launchbase: GREEN. Woodpecker live. **Demoted from critical path post-pivot.**
- Cluster gxy-cassiopeia: GREEN. Caddy 3/3 on `caddy-s3:sha-712c6e3@sha256:e024af67…` D35 dot-scheme. Adds `uploads.freecode.camp` upstream rule via T34.
- Cluster gxy-static: Live, retiring at #26 cutover.
- CF account: `ad45585c4383c97ec7023d61b8aef8c8` (`freeCodeCamp`).
- CF zones: `freecodecamp.net` + `freecode.camp` proxied. Origin certs `*.freecodecamp.net`, `*.freecode.camp`, `*.preview.freecode.camp` ACM-issued + CF-activated. **Add to provision:** `uploads.freecode.camp` A record (T34 / operator clickops).
- DNS: `test.freecode.camp` + `test.preview.freecode.camp` resolve.
- R2 bucket: `universe-static-apps-01` (single bucket, prefix-scoped). **Layout unchanged by pivot.**
- GHCR canonical builder: GHA `.github/workflows/docker--caddy-s3.yml`. New uploads svc gets `.github/workflows/docker--uploads.yml` in T31.
- Tools verified: sops, age, doctl, wmill, direnv, aws-cli v2, **Go 1.26.2 (`/opt/homebrew/bin/go`)**.

## Resume prompt — paste in fresh session

▎ Resume Sprint 2026-04-21. **PIVOTED 2026-04-26 to D016 deploy-proxy
plane.** Wave A.1 holds (Caddy + R2 + smoke). T11 per-site R2 token
mint SUPERSEDED — proxy holds sole R2 admin credential; CLI auths via
GitHub identity. New work: T30 (D016 ADR in Universe repo, broken
ownership), T31 (Go microservice in NEW repo `~/DEV/fCC-U/uploads`),
T32 (universe-cli v0.4 fresh on `feat/proxy-pivot` branch off `main`),
T33 (`platform.yaml` v2 schema), T34 (Caddy + DNS + smoke retarget on
infra). Old `feat/woodpecker-pivot` archaeology. Per-task covenant:
TDD, title-only `type(scope): subject`, broken-ownership session
governs, operator pushes at sprint close. Tree on `feat/k3s-universe`,
ahead of origin by 25 (incoming infra pivot-docs commit makes it 26).
