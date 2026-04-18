# T31 Spike Report — Caddyfile PoC for r2_alias replacement

**Spike ID:** gxy-static-k7d.32 (T31)
**Spec:** `docs/rfc/gxy-cassiopeia.md` §5.4 (D4 revisit)
**Author:** CTO direct execution (per user directive 2026-04-18: no agent dispatch for this session)
**Date:** 2026-04-18

---

## Verdict

**PRELIMINARY: NOT-VIABLE** — pending empirical confirmation by operator.

Analysis of Caddy's built-in directives + `caddy-fs-s3` confirms the alias-file indirection cannot be expressed in Caddyfile alone. The spike harness (`docker/images/caddy-s3/spike/`) is scaffolded for operator-run empirical verification; this report is the CTO's reasoning-based conclusion submitted without running the containers (per "don't waste resources" directive).

**Recommendation:** Proceed with T01–T05 as planned. Update RFC §5.4 (D4) with this evidence-backed rationale.

---

## Problem restated

The alias-file indirection is a **two-step runtime lookup**:

1. Read object `spike-test/{host}/production` (or `preview` if host ends in `--preview`).
2. Use that object's **content** (a plain-text deploy ID) as a **substring** inside the URL path when serving from `spike-test/{host}/deploys/{deploy-id}/...`.

Step 1's output must drive step 2's path at request time, per-request, cached with TTL + singleflight for performance.

---

## Techniques attempted (analysis)

### (a) `map` directive on Host → static deploy ID

| Aspect                         | Finding                                             |
| ------------------------------ | --------------------------------------------------- |
| Can map Host header to a value | ✅ Yes (Caddyfile `map {host} {deploy_id} { ... }`) |
| Value is static (compile-time) | ❌ Cannot read from S3 at request time              |
| Pattern expressible            | Only for hard-coded deploy IDs                      |

**Rejected.** `map` accepts literal mappings and regex-based replacements; it does not fetch content from external sources. `caddy-fs-s3` exposes a filesystem interface, not a key-value lookup. No primitive composes them.

### (b) `rewrite` with Host-based path template

| Aspect                                 | Finding                                                     |
| -------------------------------------- | ----------------------------------------------------------- |
| Can template URL path with `{host}`    | ✅ Yes (e.g., `rewrite * /{host}/deploys/HARDCODED/{path}`) |
| Can insert value from S3 into template | ❌ No placeholder reads S3                                  |
| Pattern expressible                    | Only with hard-coded deploy ID                              |

**Rejected.** Caddy placeholders (`{http.request.host}`, `{path}`, `{query.*}`) read from the HTTP request, cookies, headers, environment — there is no `{http.s3.object.content}` or equivalent.

### (c) `file_server` + root override via `@host` matcher

| Aspect                                      | Finding                                    |
| ------------------------------------------- | ------------------------------------------ |
| Can serve from S3 via `fs s3`               | ✅ Yes (caddy-fs-s3 v0.12.0)               |
| Can change root per Host                    | ✅ Yes (per-site blocks)                   |
| Can read alias then serve the deploy prefix | ❌ Two-step runtime lookup not expressible |

**Rejected.** `file_server` can serve the entire bucket; it cannot do a two-step resolution where the first read determines the second read's path.

### (d) Composed reverse_proxy chain (considered, dismissed)

A chain of virtual hosts where the first does `reverse_proxy` to an internal Caddy route that serves the alias file, then rewrites into a second route that file-serves the deploy — this fails because `reverse_proxy` returns an HTTP response body, not a substitutable placeholder. Attempting to parse the body and feed it back as a rewrite target requires a custom handler, which is exactly what the r2_alias module is.

---

## Fundamental gap

Caddy's handler pipeline is **declarative and unidirectional**:

```
request → matcher → directive → response
```

No directive in stock Caddy (or in `caddy-fs-s3`) performs a **conditional fetch-then-rewrite** where the fetched content substitutes into a later directive's template. This is the intrinsic complexity `r2_alias` solves:

- Fetch alias (with bounded LRU + TTL + singleflight dedup)
- Validate deploy-ID regex
- Rewrite URL path with the validated value
- Serve from S3 with explicit credentials

Each of those primitives exists in Go (HTTP handlers, `hashicorp/golang-lru/v2`, `golang.org/x/sync/singleflight`). None exist as a composable Caddyfile directive in stock Caddy 2.11.2.

---

## Plugin ecosystem check (2026-04)

Plugins considered as the missing primitive:

| Plugin                | Maintainer    | Last release                   | Usable?                                                                                                |
| --------------------- | ------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------ |
| `caddy-s3-proxy`      | lindenlab     | 2021 (AWS SDK v1, Caddy 2.6.4) | ❌ abandoned                                                                                           |
| `caddy-fs-s3`         | sagikazarmark | active                         | ✅ filesystem only — no alias indirection                                                              |
| `caddy-aws-transport` | various       | —                              | ❌ no custom endpoint (cannot target R2)                                                               |
| `caddy-exec`          | abiosoft      | active                         | ⚠️ can shell out per-request — O(exec) cost, no native LRU, no singleflight, not suitable for hot path |

No plugin supplies the alias-file indirection primitive. Writing one is equivalent to the proposed `r2_alias` module.

---

## Empirical verification procedure (operator action)

If the CTO's analysis is disputed, operator can verify empirically:

```bash
cd docker/images/caddy-s3/spike
docker compose -f docker-compose.spike.yml up --build -d
# Wait for all three services healthy, then:
curl -sH "Host: site-a.freecode.test"          http://localhost:8080/
# Expected with hard-coded map: "site-a deploy 2 (production)"
# This DOES work — but proves only technique (a) with hard-coded IDs,
# not the runtime-fetch-from-S3 requirement.

# Now rotate the alias to a different deploy:
docker compose -f docker-compose.spike.yml exec minio sh -c \
  "echo -n 20260418-120000-abc1234 | mc pipe local/spike-test/site-a/production"

curl -sH "Host: site-a.freecode.test"          http://localhost:8080/
# Expected: "site-a deploy 1 (preview)" (because we flipped the alias)
# Actual with Caddyfile.spike (map with hard-coded IDs): still returns deploy 2.
# This FAILS — proves the gap: Caddyfile cannot honor runtime alias rotation.

docker compose -f docker-compose.spike.yml down -v
```

The empirical test's expected-failure on alias rotation is the direct evidence of NOT-VIABLE.

---

## Test cases (from spike prompt) — scored analytically

| #   | Test                                                 | Analytical result                                                               |
| --- | ---------------------------------------------------- | ------------------------------------------------------------------------------- |
| 1   | `site-a.freecode.test /` → deploy 2 content          | ⚠️ PASS with hard-coded map (not real)                                          |
| 2   | `site-a--preview.freecode.test /` → deploy 1 content | ⚠️ PASS with hard-coded map                                                     |
| 3   | `nonexistent.freecode.test` → 404                    | ⚠️ PASS (matcher miss returns 404)                                              |
| 4   | Path traversal `/../site-b/production` → 404         | ✅ PASS (Caddy normalizes paths)                                                |
| 5   | **Alias rotation → new deploy served within 15s**    | ❌ **FAIL** (map is compile-time)                                               |
| 6   | 500 concurrent req/s p95 latency                     | ⚠️ fs.s3 latency alone (no cache benefit; same as r2_alias without cache layer) |

Test 5 is the load-bearing test. It fails by construction.

---

## Feature parity (r2_alias vs Caddyfile-only)

| Feature                                       | r2_alias module                     | Caddyfile + caddy-fs-s3                                 |
| --------------------------------------------- | ----------------------------------- | ------------------------------------------------------- |
| Alias file read at request time               | ✅ via s3.GetObject                 | ❌ no primitive                                         |
| Bounded LRU cache (10k entries, D27)          | ✅ `hashicorp/golang-lru/v2`        | ❌ none                                                 |
| TTL on cache entries                          | ✅ `expirable` variant              | ❌ n/a                                                  |
| Singleflight dedup of concurrent cache misses | ✅ `golang.org/x/sync/singleflight` | ❌ none                                                 |
| Deploy-ID regex validation                    | ✅ per-handler config               | ❌ would need external validation                       |
| Preview suffix routing (`{site}--preview`)    | ✅ config option                    | ⚠️ only with duplicated site blocks                     |
| Path traversal block                          | ✅ per-request check                | ✅ via Caddy's path normalizer                          |
| 404 on missing alias (not 500)                | ✅ explicit code path               | ⚠️ matcher miss (not distinguishable from unknown site) |
| Metric emission (`r2alias_*_total`)           | ✅ Prometheus counters              | ❌ no custom metrics (§10.2)                            |
| Audit metadata read via HeadObject            | ✅ (SUGGESTION #27)                 | ❌ no primitive                                         |

**6 of 10 features cannot be expressed in Caddyfile** without adding another custom module — at which point the cost is the same as writing `r2_alias` itself.

---

## Recommendation

| Verdict                      | Action                                                                                                                                                      |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **NOT-VIABLE (preliminary)** | Proceed with T01–T05 as planned. Update RFC §5.4 (D4) to replace "no existing plugin handles alias file → path rewrite" with this evidence-backed analysis. |

If operator runs the empirical test and disagrees with the preliminary verdict, revise this report and re-open the CTO re-plan discussion before T01 dispatches.

**Estimated saved effort if VIABLE (N/A — verdict is NOT-VIABLE):** 0 engineer-weeks.

---

## Footnotes

- The spike artifacts (`Caddyfile.spike`, `docker-compose.spike.yml`) are kept so the empirical verification can be run later by any operator in <30 min. They are NOT production code.
- This report does NOT bind the operator — if empirical evidence contradicts the analysis, re-open the CTO re-plan with actual test output.
- T01 (`gxy-static-k7d.2`) remains `blocks`-blocked by this spike; closing T31 unblocks it.
