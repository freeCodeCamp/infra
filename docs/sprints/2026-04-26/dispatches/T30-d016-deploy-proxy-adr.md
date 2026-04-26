# T30 — D016 ADR draft (deploy proxy architecture)

**Status:** pending
**Worker:** w-infra (governing session — broken ownership 2026-04-26)
**Repo:** `~/DEV/fCC-U/Universe` (branch: `main`) — **CROSS-REPO under broken-ownership authorization**
**Output:** `~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md`
**Sprint cross-ref:** D43 row in `DECISIONS.md`
**Authority:** operator command 2026-04-26 — "BREAK OWNERSHIP MODEL, Use this session as the governing session. We have to ship this tonight."
**Started:** —
**Closed:** —
**Closing commit(s):** —

---

## Why this dispatch exists

Wave A.3 (T11) was solving the wrong problem. Per-site R2 tokens
minted by Windmill + pushed to Woodpecker repo-scoped secrets shifts
token-sharing risk from staff hands to CI hands but does not
**eliminate** it. The actual platform tenet — staff devs ship sites
with **only `platform.yaml`** + GitHub identity, no R2 tokens
anywhere outside cluster — needs a different middle plane.

D016 codifies the proxy plane that replaces per-site R2 tokens.

## Decisions baked in (Q9–Q15 from session 2026-04-26)

| Q   | Locked answer                                                                                                                                                                                                                                                                                                                    |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q9  | Standalone Go microservice. Hostname `uploads.freecode.camp`. Caddy reverse-proxies to k3s service. Direct upload to existing `universe-static-apps-01/<site>/deploys/<ts>-<sha>/` — no staging bucket, no folder move. Atomic alias flip on finalize.                                                                           |
| Q10 | CLI identity priority: (1) `$GITHUB_TOKEN`/`$GH_TOKEN` env → (2) GHA OIDC `$ACTIONS_ID_TOKEN_REQUEST_TOKEN` → (3) Woodpecker OIDC (when supported) → (4) `gh auth token` shell-out → (5) device-flow stored token. Server validates via `GET /user`, caches login→user 5 min.                                                    |
| Q11 | Static `site → [team-slugs]` map in proxy config (`sites.yaml`, hot-reload). Membership checked via `GET /orgs/{org}/teams/{slug}/memberships/{user}` per request, cached 5 min. Apollo GH module reusable.                                                                                                                      |
| Q12 | Streaming proxy. CLI multipart-uploads to proxy; proxy streams parts to R2. Bandwidth thru proxy fine for static-app sizes (<100 MB typical). No presigned URLs — keeps trust boundary at proxy + simpler CLI.                                                                                                                   |
| Q13 | Server-side atomic alias write. Only proxy holds R2 admin token. CLI never writes alias keys. Atomicity = single S3 PUT (R2 PutObject is atomic per-key). After finalize, proxy verifies all uploads landed under expected prefix (ListObjectsV2), then PUT alias. Verify fail → 422; alias untouched; old deploy still serving. |
| Q14 | Yank current `0.4.0-beta.1` Woodpecker-pivot work. Branch `feat/woodpecker-pivot` becomes archaeology. Cut fresh `0.4.0` on `feat/proxy-pivot` from `main`.                                                                                                                                                                      |
| Q15 | New repo `freeCodeCamp/uploads` at `~/DEV/fCC-U/uploads/`. Go module `github.com/freeCodeCamp/uploads`.                                                                                                                                                                                                                          |

## What dies / pivots in prior sprint state

| Prior dispatch                           | Verdict                    | Reason                                               |
| ---------------------------------------- | -------------------------- | ---------------------------------------------------- |
| T11 (windmill flow per-site R2 mint)     | SUPERSEDED — boneyard      | Eliminated by proxy holding only R2 admin token      |
| T16 (universe-cli Woodpecker client)     | DEAD                       | CLI does not talk to Woodpecker anymore              |
| T18 (universe-cli `deploy` rewrite)      | REWRITE                    | Targets proxy `/api/deploy/*` not Woodpecker         |
| T19 (`promote`/`rollback`)               | REWRITE                    | Targets proxy `/api/site/*`                          |
| T20 (legacy strip + 0.4.0-beta.1 cut)    | DEFER PUBLISH              | Cannot ship 0.4 with wrong upload model              |
| T21 (`.woodpecker/deploy.yaml` template) | DEMOTE — reference example | Not critical path; build environment is staff choice |
| G1.0b (Woodpecker admin Resource)        | RETIRE                     | Proxy does not push secrets to Woodpecker            |
| G1.0a (CF R2 admin token Resource)       | KEEP                       | Proxy reuses (or migrates ownership later)           |

## What survives

- Caddy `r2_alias` on cassiopeia (D35 dot-scheme). Serve plane unchanged.
- R2 bucket `universe-static-apps-01` + prefix-per-site layout.
- Atomic alias-file write **semantics** (proxy writes them now, not Woodpecker step).
- D33-D42 amendments (admin token home in `windmill/.env.enc`, single bucket, etc.).
- T22 cleanup cron — independent of upload path. Continues per D39 (7d retention).
- T15 smoke harness — retargeted at proxy (T34).

## ADR body — sections to write

1. Context — token-sharing footgun motivating pivot
2. Decision — proxy plane summary (Q9–Q15 inline)
3. Architecture — data-flow diagram (laptop/CI → CLI → proxy → R2 → Caddy → user)
4. Authn/authz — identity priority + team-membership probe + JWT expiry
5. R2 layout — direct upload to final prefix, atomic alias flip semantics
6. Operational surface — proxy hosting (gxy-management), Caddy reverse proxy, sites.yaml hot-reload
7. Migration — v0.3 R2-token CLI keeps serving until v0.4 proxy CLI ships; sunset path
8. Consequences — bandwidth thru proxy, single point of failure (mitigated by k3s replicas), GH API quota dependency
9. Cross-refs — D33, D40, D41, D42 (admin token + bucket layout retained); supersedes T11 design
10. Amendments — empty initially

## Acceptance criteria

- File at `decisions/016-deploy-proxy.md` follows ADR-001..015 conventions
- All 9 sections present
- All Q9–Q15 verbatim leans recorded
- Single Universe commit `feat(decisions): D016 deploy proxy plane (supersedes T11 token-mint design)`

## Closure checklist

- [ ] `016-deploy-proxy.md` lands
- [ ] Sprint `DECISIONS.md` D43 row points to `016-deploy-proxy.md`
- [ ] `T30` dispatch Status flipped `done`
- [ ] PLAN matrix row checked
- [ ] HANDOFF entry appended
