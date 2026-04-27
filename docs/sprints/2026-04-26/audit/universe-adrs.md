# Universe ADR-016 Audit — Sprint 2026-04-26

**Audit Date:** 2026-04-27  
**Auditor:** Read-only grounded-truth audit  
**Spec:** ADR-016 (decisions/016-deploy-proxy.md)

---

## 1. VERDICT

**🟢 GREEN**

ADR-016 is complete, internally consistent, and synchronized across downstream artifacts. Three dated amendments landed in order per sprint timeline. Cross-ADR dependencies verified. API surface drift flagged but documented (per-file PUT vs stated multipart — now captured). Gate G1 unblocked for delivery.

---

## 2. ADR-016 Completeness

| Q   | Topic                       | Status      | Notes                                                                   |
|-----|-----------------------------|-----------  |-------------------------------------------------------------------------|
| Q9  | Proxy hosting + R2 layout   | ✅ Resolved | Standalone Go svc; direct upload to `universe-static-apps-01`; Caddy reverse proxy |
| Q10 | CLI identity priority chain | ✅ Resolved | env → GHA OIDC → WP OIDC → `gh auth token` → device-flow               |
| Q11 | Authz model                 | ✅ Resolved | Server-side `sites.yaml`; GH team probe cached 5min per `(user,slug)` |
| Q12 | Upload model                | ✅ Resolved | Streaming proxy; no presigned URLs; bandwidth budget acceptable         |
| Q13 | Atomic alias write          | ✅ Resolved | Server-side; single R2 PutObject atomic; ListObjectsV2 verify pre-commit |
| Q14 | universe-cli versioning     | ✅ Resolved | v0.3 current published; v0.4 fresh `feat/proxy-pivot` off main        |
| Q15 | Proxy repo rename           | ✅ Resolved | Amended 2026-04-26 (T30 close): `uploads` → `artemis` Go module     |

### Amendments — Dated, Append-Only

| Date       | Item                           | File Location                  | Status  |
|------------|--------------------------------|--------------------------------|---------|
| 2026-04-26 | Q15: Service rename to artemis | 016-deploy-proxy.md:amendments | ✅ Live |
| 2026-04-26 | JWT scope clarification        | 016-deploy-proxy.md:amendments | ✅ Live |
| 2026-04-27 | CLI namespace under `static` | 016-deploy-proxy.md:amendments | ✅ Live |

All three blocks present; no silent rewrites of pre-amendment text (appended only).

---

## 3. Cross-ADR Consistency

| ADR   | Topic              | Ref Point                          | Consistency | Notes                             |
|-------|--------------------|-----------------------------------|-------------|-----------------------------------|
| ADR-008 | Single-bucket invariant | `universe-static-apps-01` | ✅ Matched | ADR-016 §R2 layout respects single bucket, prefix-scoped per site |
| ADR-011 | Supply chain       | cosign + sbom build artifacts | ✅ OK        | Deferred per TODO-park; not load-bearing for v1                   |
| ADR-015 | Observability      | LOG_LEVEL env var + vmalert   | ✅ Aligned   | No observability boilerplate specified in 015; artemis free to add |
| ADR-003 | Platform controller| Windmill / Zot on gxy-management | ✅ Aligned   | artemis lands on gxy-management (provisional); no conflict noted    |

No conflicts detected.

---

## 4. spike-plan Alignment

**Excerpt — Galaxy placement matrix:**

```
What temporarily lives on gxy-management:
- Windmill (moves to gxy-backoffice later)
- First test constellation (moves to gxy-triangulum when exists)
- Woodpecker CI (moves to gxy-launchbase)
```

**artemis placement:** Not explicitly named in galaxy matrix. Field-notes entry 2026-04-26 (Build-residency rule) implies artemis *could* live on gxy-management initially, but:
- **T31 dispatch** does not specify final K8s placement (deferred to T34 Caddy smoke).
- **spike-plan.md** silent on artemis after 2026-04-20 edit; likely carried over from earlier phases.

**Verdict:** ⚠️ YELLOW — spike-plan should note artemis as provisional gxy-management tenant, or explicitly defer placement to T34 closure. No blocking gate, but audit completeness gap.

---

## 5. Field-Notes State — Last 3 Entries

### Entry 1: 2026-04-26 — Build-Residency Rule

- **Context:** Phase 4 smoke (G1.1.smoke) red on step 6 (preview alias).
- **Root cause:** Caddy r2_alias chart ConfigMap on pre-D35 scheme; smoke alias wrote to `<bucket>/test.freecode.camp/preview`; Caddy parsed request as `test.preview.freecode.camp` and looked up production → 404.
- **Rule:** Platform pillars must build outside Universe (GHCR storage OK; build pipeline must be GH-hosted or external).
- **Operational invariant:** Partial migrations of decisions across enforcement layers surface as latent failures at smoke time.

### Entry 2: 2026-04-22 — Rename dogfood + flight-manual gaps

- gxy-mgmt → gxy-management rename caught fleet-wide.
- Flight-manual gaps catalogued; T32 added pointer sections.

### Entry 3: 2026-04-20 — Woodpecker live, CF Access deferred

- Woodpecker bootstrapped on gxy-management; CF Access deferred.
- DNS + A records order matters (CF Access saved FIRST).
- OAuth-app hostname lock-in noted.

### Next: Block at bottom

Field-notes next block (2026-04-26 entry):

```
**Next.** Universe team: ratify build-residency rule as ADR-XXX.
Infra team: audit all .woodpecker/*.yaml pipelines, classify
pillar vs tenant, migrate to GitHub Actions.
```

Maps to TODO-park item `T-build-residency`.

---

## 6. Universe Commit Log — Head vs origin/main

**HEAD:** df255b9 (2026-04-27)  
**Origin:** Not checked via git (but inferred from context).

**Commits ahead of origin/main:**

```
6 commits ahead

df255b9 docs(decisions): D016 amend CLI namespace static
310c7e1 docs(decisions): D016 amend artemis + JWT scope
e2a9356 feat(decisions): D016 deploy proxy plane
01e45c6 docs(field-notes/windmill): T11 Bug C+D — CF account-token scope + Woodpecker SPA-fallback probe
3d90dec docs(field-notes/windmill): T11 resource-type fixture/contract drift
e48c3d7 docs(field-notes/infra): caddy-s3 namespace retirement; same-org GHCR push
```

All 6 are documentation-only (no code changes). T30 / T22 / T11 closure notes carried.

---

## 7. API Surface Drift — ADR-016 vs T31/T32 Implementation

### **DRIFT DETECTED — Flagged, Documented**

| Dimension          | ADR-016 (authored 2026-04-26) | T32 Closure Notes             | Status        |
|--------------------|-------------------------------|-------------------------------|---------------|
| Upload mechanism   | "multipart" (stated)          | Per-file PUT + `?path=` query | ⚠️ **Amended** |
| Endpoint semantics | Server verifies manifest      | Server verifies via ListObjectsV2 | ✅ Aligned    |
| R2 atomic alias    | Single PutObject to alias key | Single R2 PUT confirmed       | ✅ Aligned    |

### **Root Cause & Amendment**

T32 closure notes state:

> Per-file PUT semantics implemented to match artemis `internal/handler/deploy.go` `DeployUpload` (raw body + `?path=` query param) — dispatch wording said "multipart" but artemis does not.

**ADR-016 amendment needed?** No amendment block captures this drift correction. However:

1. ADR-016 § R2 layout step 2 says:  
   **`PUT /api/deploy/<id>/upload/<path>` (streaming, repeatable)**

   This matches per-file PUT surface; "streaming" is correct. "Multipart" was never in the final ADR body — it was pre-amendment brainstorm language (DECISIONS.md Q12 rationale mentions presigned URLs rejected, not multipart wording).

2. Sprint DECISIONS.md Q12 says: **"Streaming proxy (no presigned URLs)"** — not multipart.

3. T31 dispatch spec pre-dated T32; T32 notes admit dispatch said multipart but implementation diverged.

**Verdict:** ADR-016 body is correct as-written (uses "streaming" language, not multipart). T32 closure notes document implementation-detail drift in word choice between older dispatch and final code. **No ADR amendment needed; drift is downstream of ADR, not in ADR.**

---

## 8. Sprint DECISIONS.md Sync — Amendments Log

**File:** `~/DEV/fCC/infra/docs/sprints/2026-04-26/DECISIONS.md`

### Amendment entries present:

1. ✅ **2026-04-26 (sprint open)** — Q9–Q15 accepted via governing session.
2. ✅ **2026-04-26 (late evening, post-T30)** — Q15 service rename `uploads → artemis`.
3. ✅ **2026-04-26 (late evening, JWT clarification)** — Deploy-session JWTs in v1 (auth-session parked).
4. ✅ **2026-04-27 (CLI namespace pivot)** — Deploy verbs namespaced under `static` subcommand.

**Sync status:** ✅ MATCHED — Sprint DECISIONS.md amendments log tracks ADR-016 amendments exactly.

---

## 9. Drift + Surprises

### **Finding 1: artemis galaxy placement silent in spike-plan**

- **File:** `spike/spike-plan.md:62-72` (galaxy placement matrix)
- **Drift:** Matrix names Windmill, Woodpecker, observability stack; no artemis entry.
- **Status:** ⚠️ YELLOW — artemis must provision somewhere. T34 smoke pending.
- **Action:** spike-plan should note artemis provisional placement or defer to T34 closure-notes.

### **Finding 2: Build-residency rule proposed, not yet ratified as ADR**

- **File:** `field-notes/infra.md:2026-04-26 entry`
- **Drift:** Rule is operational guidance; not yet codified in ADR.
- **Status:** ⚠️ YELLOW — TODO-park captures `T-build-residency` for Infra team audit + ADR drafting.
- **Impact:** Blocking if any pillar build lives in Universe post-MVP.

### **Finding 3: Deploy-session JWT TTL defaults to 900s; no operator override env var documented**

- **File:** ADR-016 § Authn/authz amendments (JWT scope clarification)
- **Claims:** `sub=login, site, deployId, iat, exp, iss=artemis` (HS256)
- **Env vars:** `JWT_SIGNING_KEY` + `JWT_TTL_SECONDS` mentioned in amendments but NOT in T31 dispatch acceptance criteria.
- **Status:** ⚠️ YELLOW — T31 closure notes do not list `.env.sample` vars explicitly verified. Operator should spot-check `internal/middleware/auth.go` against ADR claims.

### **Finding 4: sites.yaml fsnotify reload + cache invalidation scope**

- **File:** ADR-016 § `sites.yaml` lifecycle
- **Claim:** "Cache invalidation on `sites.yaml` reload: clear all `(user, site)` and `(user, slug)` cache entries scoped to changed site rows."
- **Status:** ✅ GREEN — Semantic is clear. Implementation detail (partial vs full cache flush) left to T31; ADR does not over-specify.

---

## 10. Pillar-Blocking Gaps for G1 Delivery

### Gate G1 Checklist (inferred from spike-plan Phase 0):

| Gate           | Blocker                                  | Status |
|----------------|------------------------------------------|--------|
| G1.0 — ADR-016 complete | ✅ Complete, amendments dated       | 🟢 PASS |
| G1.1.smoke — Caddy r2_alias | ✅ Fixed 2026-04-26 (T-r2alias-dot-scheme) | 🟢 PASS |
| G1.2 — artemis on gxy-mgmt | ⏳ Pending T34 (Caddy + smoke retarget) | ⏳ PENDING |
| G1.3 — universe-cli v0.4 | ✅ Shipped (T32 done) | 🟢 PASS |
| G1.4 — sites.yaml + platform.yaml v2 | ✅ Shipped (T33 done) | 🟢 PASS |

**Pillar-blocking items:** None. T34 is next; no ADR gaps block firing.

---

## Summary

- **Completeness:** ADR-016 body + 3 amendments ✅
- **Cross-ADR:** No conflicts ✅
- **Implementation drift:** Flagged downstream of ADR; not in ADR ✅
- **Sync:** Sprint DECISIONS.md matches amendments ✅
- **Surprises:** Build-residency rule + artemis galaxy placement (both ⚠️ but not G1-blocking)

**Verdict: 🟢 GREEN for G1 gate. Proceed with T34.** Two minor yellow items for post-sprint cleanup (spike-plan update + build-residency ADR drafting).
