# Sprint 2026-04-26 — PLAN

Stable plan. Patched only when scope/phases/dispatch-graph change. Live cursor lives in [`STATUS.md`](STATUS.md). Locked Q/D rows in [`DECISIONS.md`](DECISIONS.md). Per-task briefs in [`dispatches/T<N>-<slug>.md`](dispatches/).

## Sprint goal

Staff dev runs `universe static deploy` from **any environment** (laptop, GHA, Woodpecker, etc.) with **only `platform.yaml`** + GitHub identity in their hands. Zero R2 credentials persist outside cluster. Site live at `<site>.freecode.camp` (production) and `<site>.preview.freecode.camp` (preview siblings). Vendor-neutral throughout (R2 = S3-compat; portable to MinIO/Backblaze/Wasabi).

## Branches

- infra `feat/k3s-universe`
- universe-cli `feat/proxy-pivot` (NEW, off `main` — `feat/woodpecker-pivot` orphaned archaeology)
- windmill `main`
- Universe `main`
- uploads `main` (NEW repo, greenfield)
- infra-secrets sops-encrypted main (no branch)

## Predecessor

[`../archive/2026-04-21/`](../archive/2026-04-21/) — Wave A.1 ✅ shipped Caddy + R2 + smoke. Wave A.2 (universe-cli `feat/woodpecker-pivot`) archaeology. Wave A.3 (T11 per-site R2 token mint) SUPERSEDED by D016 → this sprint.

## Tracking model

Filesystem-driven. Per-task dispatch docs at `dispatches/T<N>-<slug>.md` carry status header (`pending → in-progress → done`). Worker flips header in same commit that closes the task. Sprint matrix below mirrors dispatch-doc Status. Beads + bead IDs deprecated for this sprint stack.

## Galaxy role matrix

| Galaxy         | State          | Role this sprint                                               |
| -------------- | -------------- | -------------------------------------------------------------- |
| gxy-management | Live (DO FRA1) | Windmill + Zot + **uploads svc (T34 deploy lean)**             |
| gxy-launchbase | Live (DO FRA1) | Woodpecker — **demoted from critical path post-D016**          |
| gxy-cassiopeia | Live (DO FRA1) | Caddy + R2 serve plane + reverse-proxy `uploads.freecode.camp` |
| gxy-static     | Live → retire  | Legacy static; DNS moves to cassiopeia post-MVP                |

## Top-level task chain

| ID  | Subject                                         | Status  | Notes                               |
| --- | ----------------------------------------------- | ------- | ----------------------------------- |
| T30 | D016 ADR draft + lock                           | done    | Cross-repo Universe; broken-owner   |
| T31 | Artemis svc (Go) — scaffold + endpoints + tests | done    | `artemis@861e4c4` (greenfield init) |
| T32 | universe-cli v0.4 rewrite                       | pending | Fresh `feat/proxy-pivot` off `main` |
| T33 | `platform.yaml` v2 schema + validator + doc     | done    | `universe-cli@5d7b6ef`              |
| T34 | Caddy reverse proxy + DNS prep + smoke retarget | pending | After T31                           |
| T22 | Cleanup cron Windmill flow                      | done    | `windmill@016a868`                  |

## Phases + gates

### Phase 1 — Proxy pillar build

Sub-deliverables:

1. **P1.1 — Deploy proxy service** (T30 ADR + T31 uploads svc) — Go microservice at `uploads.freecode.camp`. Holds sole R2 admin credential. Authenticates staff via GitHub identity (token / OIDC / device flow). Authorizes via server-side `sites.yaml` map → GitHub team membership probe. Streams uploads to `universe-static-apps-01/<site>/deploys/<ts>-<sha>/`. Atomic alias write on finalize.
2. **P1.2 — Caddy `r2_alias` on gxy-cassiopeia** — verified live 2026-04-18 + D35 dot-scheme rolled 2026-04-26. **No re-dispatch.** Carried forward from prior sprint.
3. **P1.3 — DNS wiring** — `uploads.freecode.camp` A → uploads svc galaxy public IP (T34 + operator clickops); `<site>.freecode.camp` + preview A → cassiopeia public IPs.
4. **P1.4 — Cleanup cron** (T22) — 7d retention; both aliases pin prefix (Q8). Independent of upload path.
5. **P1.5 — Firewall posture** — DO Cloud Firewall only (Q4). Uploads svc galaxy follows same posture.
6. **P1.6 — Smoke harness** (T34 retarget) — exercises proxy E2E (init → upload → finalize → curl preview → promote → curl prod). Replaces direct-S3 phase4 smoke.
7. **P1.7 — universe-cli v0.4 rewrite** (T32) — fresh branch off `main`; identity priority chain; commands target proxy `/api/*`.
8. **P1.8 — `platform.yaml` v2** (T33) — strip credential paths; build + deploy config only.

**Gate G1:** End-to-end deploy from CLI → proxy → R2 → live site → rollback → promote exercised against one reference site. Smoke harness green. **CARRIED FROM PRIOR SPRINT** — not re-stated.

### Phase 2 — Release (post-G1)

- universe-cli `0.4.0` published to npm (yanks 0.3.x default; 0.3.x stays in npm registry as legacy).
- CHANGELOG + README ported to proxy contract.
- uploads svc tagged `v1.0.0`, image published to GHCR.

**Gate G2:** `npm i -g @freecodecamp/universe-cli@0.4.0` works; `universe static deploy` + `rollback` + `promote` drive proxy against G1 reference site.

### Phase 3 — Cutover (post-G2)

- Flip DNS for existing `*.freecode.camp` users from gxy-static → gxy-cassiopeia.
- Teardown gxy-static (VMs + DNS + Caddy chart).

**Gate G3:** gxy-static destroyed; no 404s for pre-existing sandbox sites during 24h observation.

### Phase 4 — Close

- Move `docs/sprints/2026-04-26/` → `docs/sprints/archive/2026-04-26/`.
- Final field-notes journal entry (`Universe/spike/field-notes/infra.md`).

## Dispatch matrix

| T-id | Area               | Subject                                          | Dispatch                                                                             | Status      |
| ---- | ------------------ | ------------------------------------------------ | ------------------------------------------------------------------------------------ | ----------- |
| T30  | Universe (xrepo)   | D016 ADR — deploy proxy plane (broken ownership) | [`dispatches/T30-d016-deploy-proxy-adr.md`](dispatches/T30-d016-deploy-proxy-adr.md) | [x] done    |
| T31  | artemis (new repo) | Artemis svc Go — scaffold + endpoints + tests    | [`dispatches/T31-artemis-service.md`](dispatches/T31-artemis-service.md)             | [x] done    |
| T32  | universe-cli       | v0.4 rewrite — proxy client (`feat/proxy-pivot`) | [`dispatches/T32-cli-v04-rewrite.md`](dispatches/T32-cli-v04-rewrite.md)             | [ ] pending |
| T33  | universe-cli       | `platform.yaml` v2 schema + validator + doc      | [`dispatches/T33-platform-yaml-v2.md`](dispatches/T33-platform-yaml-v2.md)           | [x] done    |
| T34  | infra              | Caddy reverse proxy + DNS prep + smoke retarget  | [`dispatches/T34-caddy-dns-smoke.md`](dispatches/T34-caddy-dns-smoke.md)             | [ ] pending |
| T22  | windmill           | Cleanup cron flow                                | [`dispatches/T22-cleanup-cron.md`](dispatches/T22-cleanup-cron.md)                   | [x] done    |

## Wave dispatch graph

```
T30 (D016 ADR draft) ──→ T31 (uploads svc Go scaffold + endpoints + tests)
                                           │
                                           ▼
                          T32 (CLI v0.4 fresh proxy-client) ─┐
                          T33 (platform.yaml v2 schema)  ───┤
                                                            ▼
                                            T34 (Caddy + DNS + smoke retarget — operator deploys)
                                                            │
                                                            ▼
                                                       T22 (cleanup cron — post-T31 live)
                                                            │
                                                            ▼
                                                       Sprint G1 close
```

Notes:

- T30 → T31 serial (ADR locks shape before Go code).
- T32 + T33 parallel within universe-cli on `feat/proxy-pivot`.
- T34 blocks on T31 image tag.
- T22 independent of upload path; can land anytime, blocks on T31 only for live verification (admin token shared via Resource).
- v0.3 R2-token CLI keeps current published until v0.4 ships.

## Worker ↔ repo map

**Pivot 2026-04-26 (post-T30):** governing session shifted from
single-session-interleaved to **multi-session true-parallel**. This
session (in `~/DEV/fCC/infra`) is now governor-only — owns sprint-doc
consolidation + closure reconciliation. Per-T workers fire from
separate Claude Code sessions / terminals.

- `~/DEV/fCC/infra` (`feat/k3s-universe`) — **governor (this session)** + T34 worker (post-T31). Holds sprint-doc edits (STATUS / PLAN / HANDOFF / DECISIONS) + dispatch Status reconciliation.
- `~/DEV/fCC-U/Universe` (`main`) — T30 (D016 ADR + amendments). **Done** at `Universe@310c7e1`.
- `~/DEV/fCC-U/artemis` (`main`, NEW) — T31 worker. Greenfield Go scaffold.
- `~/DEV/fCC-U/universe-cli` (`feat/proxy-pivot`, NEW off `main`) — T32 + T33 workers. Two parallel sessions OK (same branch; coordinate file-by-file or two sub-branches merged at close).
- `~/DEV/fCC-U/windmill` (`main`) — T22 worker + boneyard headers on T11 source.

**Stagger discipline (multi-session):**

- T30 → T31 serial — **complete** (T30 closed; T31 unblocked).
- T31 + T33 + (optional) T22 fire **concurrent** in three terminals.
- T32 sequences after T31 API contract solid (or fires partial-parallel for scaffold + identity chain).
- T34 blocks on T31 image tag (artemis CI publishes first GHCR image).
- One commit per task close. Worker flips dispatch-doc Status header in own commit; governor reconciles PLAN matrix + HANDOFF in separate infra commit at task close.

**File-write discipline (multi-session):**

- Workers ONLY edit: own dispatch file (`dispatches/T<N>-*.md`) Status header + own repo files. Never touch `STATUS.md`, `PLAN.md`, `HANDOFF.md`, `DECISIONS.md`.
- Governor (this session) ONLY edits sprint-doc cluster — never touches T-worker repo files.
- Conflict on dispatch file: worker wins; governor consolidates next.

## Dispatch instructions

- Worker flips dispatch-doc Status header `pending → in-progress` on start, `→ done` on closure. Same commit updates the matrix row above.
- Commit policy: TDD (RED → GREEN → REFACTOR). One commit per sub-task close. Title-only per `cmd-git-rules`. Operator pushes at sprint close.
- Close-out: when all matrix rows show `[x] done` + smoke green → G1 ticks → Phase 2 unblocks.

## Success criteria (proxy pillar done)

1. `universe login` opens GitHub device flow OR auto-detects identity from env/OIDC/`gh`.
2. `universe static deploy` reads `platform.yaml`, builds (or uploads pre-built), POSTs proxy `/api/deploy/*`, returns preview URL.
3. Proxy validates GitHub team membership against `sites.yaml` map.
4. Proxy streams upload to R2 single bucket prefix-scoped.
5. Proxy verifies upload (ListObjectsV2) then atomic alias write on finalize.
6. `<site>.preview.freecode.camp` request: CF → cassiopeia Caddy → `r2_alias` → R2 → served.
7. `universe static promote` swaps production alias to current preview atomically.
8. `universe static rollback --to <id>` writes production alias to past deploy.
9. R2 admin credential never leaves cluster — staff devs hold only `platform.yaml` + GitHub identity.
10. Cleanup cron deletes unreferenced prefixes; aliased prefixes pinned (7d retention; D39 holds).

## Cross-references

| Doc                                                  | Role                                           |
| ---------------------------------------------------- | ---------------------------------------------- |
| `STATUS.md`                                          | Live cursor                                    |
| `DECISIONS.md`                                       | D43 + Q9–Q15 cross-ref                         |
| `HANDOFF.md`                                         | Append-only history                            |
| `dispatches/`                                        | Per-task briefs                                |
| `../archive/2026-04-21/`                             | Predecessor sprint (Wave A.1 + A.2 + boneyard) |
| `~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md` | Universe ADR (cross-repo, broken ownership)    |
| `~/DEV/fCC-U/Universe/spike/spike-plan.md`           | Master delivery plan (upstream)                |
| `~/DEV/fCC-U/Universe/spike/field-notes/infra.md`    | Append-only infra journal (cross-repo)         |
| `../../architecture/rfc-gxy-cassiopeia.md`           | RFC w/ D33–D43 amendments                      |
| `../../architecture/task-gxy-cassiopeia.md`          | Task acceptance source of truth (carryover)    |
| `../../flight-manuals/gxy-management.md`             | Doomsday rebuild (inc. Windmill + uploads)     |
| `../../flight-manuals/gxy-cassiopeia.md`             | Doomsday rebuild (R2 + Caddy)                  |
| `../../TODO-park.md`                                 | Deferred work                                  |

## Non-obvious invariants (carried forward)

- k3s clusters hand-rolled, not DOKS. Per-cluster kubeconfig at `k3s/<cluster>/.kubeconfig.yaml` (direnv `expand_path`).
- Three-form galaxy naming: repo-dir (`gxy-management`), ansible group underscore (`gxy_management_k3s`), DO droplet tag dash (`gxy-management-k3s`).
- `.envrc` hierarchy: root loads global tokens; cluster dir loads team-specific DO token.
- `just play <name> <group>` expands to `play-<name>.yml` against `<group>`; `*args` forwarded verbatim.
- Helm chart repos at `k3s/<cluster>/apps/<app>/charts/<chart>/repo`; absence → local chart dir.
- PSS admission exempt: `windmill` + `tailscale` namespaces.
- Caddy Gateway listener ports must match Traefik entrypoint ports (80/443 hostNetwork).
- `rtk` mandatory for verbose Bash; context-mode sandbox for >20 line outputs.
- Operator pushes. Session never `git push` / `gh pr create`.
- Bun PATH NOT in shell — workers run `bunx wmill ...` from windmill repo cwd (devDep `windmill-cli@1.684.1`).
- `wmill sync push` destructive; never dismiss deletion warnings.
- sops stateful: `sops decrypt --in-place` → yq → `sops encrypt --in-place`.
- **NEW:** R2 admin credential lives only at `infra-secrets/windmill/.env.enc` + propagated to uploads svc via k8s Secret (T34 chart). Never on operator host, never in CI, never in client.

## Close criteria

Sprint closed when: G1 ✅, G2 ✅, G3 ✅, dir moved to `archive/2026-04-26/`, field-notes journal entry landed.
