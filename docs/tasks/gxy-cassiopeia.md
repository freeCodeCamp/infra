# Implementation Task Breakdown — gxy-cassiopeia

**Source Spec:** `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md`
**Spec Type:** RFC
**Generated:** 2026-04-17
**Total Tasks:** 30 (T06 deferred to T30; T30 is post-M5, not dispatched in the main run)
**Dispatch Summary:** 24 subagent, 3 operator-gated, 2 iterative, 1 deferred (T30)

## Repo Map (for multi-session, multi-developer execution)

Tasks span four repositories. Each agent prompt specifies a `## Repo and CWD` section when the repo is not infra. When the prompt does not specify, the agent works in the **infra repo**.

| Repo             | Absolute path                           | Tasks that work here                                                                                                                               |
| ---------------- | --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **infra**        | `/Users/mrugesh/DEV/fCC/infra`          | T01–T05, T07–T10, T12, T13, T15, T21, T23, T24, T25, T26, plus the infra-side parts of T14 and T11's justfile recipe; T06 deferred → T30 (post-M5) |
| **windmill**     | `/Users/mrugesh/DEV/fCC-U/windmill`       | T11, T14 (flow portion), T22                                                                                                                       |
| **universe-cli** | `/Users/mrugesh/DEV/fCC-U/universe-cli` | T16, T17, T18, T19, T20                                                                                                                            |
| **Universe**     | `/Users/mrugesh/DEV/fCC-U/Universe`     | T25 (post-cutover field notes only), T27, T28, T29 (field notes only)                                                                              |

**Rule:** infra-team owns ONLY `spike/field-notes/infra.md` in the Universe repo. ADRs and spike-plan.md are Universe-team-owned and MUST NOT be modified by any task in this breakdown.

**When an agent is dispatched to a task, it MUST:**

1. Read the `## Repo and CWD` section of its prompt (if present) and `cd` there before starting.
2. If absent, default to the infra repo path above.
3. Read the RFC at `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md` for architectural context when the prompt references a section by number (e.g., "§4.3.4").

## Protection Boundaries

Every task must respect these boundaries (from RFC §7):

**Stable interfaces (do NOT change without a follow-up RFC):**

- R2 key layout: `{site}/deploys/{deploy-id}/*`, `{site}/production`, `{site}/preview`, `_deploy-meta.json`
- Alias file format: plain text, single-line UTF-8 deploy ID, no trailing newline
- Deploy ID regex: module accepts `^[A-Za-z0-9._-]{1,64}$`; CLI produces `^\d{8}-\d{6}-([a-f0-9]{7}|dirty-[a-f0-9]{8})$`
- Caddy module directive syntax: `r2_alias { bucket… endpoint… }` — adding options is additive, renaming is breaking
- Woodpecker pipeline variable names: `OP`, `DEPLOY_TARGET`, `ROLLBACK_TO`
- Pipeline file path: `.woodpecker/deploy.yaml` in each constellation repo
- universe-cli config schema: `woodpecker.endpoint` and `woodpecker.repo_id` fields

**Invariants (must hold before and after any change):**

- No R2 credentials on developer machines — any reintroduction of direct R2 access in universe-cli is a violation
- Alias writes are atomic (S3 PutObject guarantee on R2)
- Immutable deploys — `{site}/deploys/{id}/*` never overwritten; promote/rollback repoints aliases only
- Deploy prefix verification before alias write (via `verify-deploy` pipeline step)
- No shared state between sites — Site A's deploys never touch Site B's keys
- 404 on missing alias, not 500 — dead sites are "not found"

**Migration constraints:**

- `universe-cli ≥ 0.4.0` required for gxy-cassiopeia; older versions will fail
- Constellations on gxy-static must re-deploy to gxy-cassiopeia-1 before DNS cutover (enforced by preflight script)
- gxy-static is NOT deleted by this work; decommission is the user's decision post-30-day-soak

**Scope boundaries (files tasks must NOT modify):**

- Do NOT modify `k3s/gxy-static/` — it's the sandbox galaxy, untouched per user directive (D20)
- Do NOT modify `k3s/gxy-management/apps/windmill/` except to add the new cleanup flow (T25) and per-site secret provisioning flow (T14)
- Do NOT modify `/Users/mrugesh/DEV/fCC-U/Universe/decisions/*.md` or `spike/spike-plan.md` — Universe team owns those
- Do NOT run git write commands (commit, push, checkout, branch) — user controls git

---

## Critical Path (must be sequential)

### Task 01 [M]: Caddy `r2_alias` module — scaffold and Caddyfile parsing

**Traceability:** Implements R4, R13 | Constrained by D4, D18, D23
**Files:**

- Create: `docker/images/caddy-s3/modules/r2alias/r2alias.go`
- Create: `docker/images/caddy-s3/modules/r2alias/caddyfile.go`
- Create: `docker/images/caddy-s3/modules/r2alias/go.mod`
- Create: `docker/images/caddy-s3/modules/r2alias/go.sum` (generated by `go mod tidy`)

#### Context

Create the Go module skeleton for a Caddy HTTP handler that resolves alias files in R2 and rewrites the request path to the target deploy prefix. The module registers itself as `http.handlers.r2_alias` via `caddy.RegisterModule`. The full interface contract and struct shape is defined in RFC §4.3.4 — implementers must follow that exactly.

This task covers scaffolding only: module registration, `CaddyModule()`, `UnmarshalCaddyfile` to parse the Caddyfile directive tokens, and `Validate()` to enforce config invariants. Cache logic (Task 02) and `ServeHTTP` (Task 03) are separate tasks. The scaffold must compile and pass a `caddy list-modules | grep r2_alias` check when built via xcaddy.

Package path: `github.com/freeCodeCamp-Universe/infra/docker/images/caddy-s3/modules/r2alias`.

#### Acceptance Criteria

- GIVEN the module scaffold WHEN `go build ./...` runs in the module directory THEN it compiles with exit 0
- GIVEN a Caddyfile with `r2_alias { bucket foo endpoint https://x region auto access_key_id k secret_access_key s cache_ttl 15s cache_max_entries 10000 preview_suffix "--preview" root_domain "freecode.camp" deploy_id_regex "^[A-Za-z0-9._-]{1,64}$" }` WHEN `caddy adapt` parses it THEN no errors
- GIVEN `Validate()` runs with bucket="" or endpoint="" THEN an explanatory error is returned
- GIVEN `Validate()` runs with `CacheTTL <= 0` or `CacheMaxEntries <= 0` THEN Validate returns an error
- GIVEN the module is compiled into xcaddy THEN `caddy list-modules | grep r2_alias` returns `http.handlers.r2_alias`

#### Verification

```bash
cd docker/images/caddy-s3/modules/r2alias && go build ./... && go vet ./...
```

**Expected output:** exit 0, no output from `go vet`.

#### Constraints

- Do NOT implement ServeHTTP logic — it is Task 03's scope
- Do NOT implement cache logic — it is Task 02's scope
- Interface guards `_ caddy.Provisioner = (*R2Alias)(nil)`, `_ caddy.Validator`, `_ caddyfile.Unmarshaler`, `_ caddyhttp.MiddlewareHandler` MUST be declared
- Follow the struct shape from RFC §4.3.4 exactly (field names and JSON tags)
- Do NOT touch `k3s/gxy-static/` or anything under `docker/images/landing/`

#### Agent Prompt

```
You are implementing Task 01: Caddy r2_alias module — scaffold and Caddyfile parsing.

## Your Task

Create the Go module skeleton at `docker/images/caddy-s3/modules/r2alias/` for a Caddy HTTP handler that will resolve alias files in R2. This task scaffolds only — cache (Task 02) and ServeHTTP (Task 03) are separate tasks.

### Step 1: Create go.mod
- Package path `github.com/freeCodeCamp-Universe/infra/docker/images/caddy-s3/modules/r2alias`
- Go directive: `go 1.22` (or matching `caddy:2.8-builder` — check `docker pull caddy:2.8-builder` and inspect `GOROOT` if in doubt)
- Required imports (to be used by later tasks, but declared so `go mod tidy` resolves them):
  - `github.com/caddyserver/caddy/v2 v2.8.4`
  - `github.com/caddyserver/caddy/v2/caddyconfig/caddyfile` (transitive)
  - `github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile` (transitive)
  - `github.com/caddyserver/caddy/v2/modules/caddyhttp` (transitive)
  - `github.com/aws/aws-sdk-go-v2 v1.41.2`
  - `github.com/aws/aws-sdk-go-v2/config`
  - `github.com/aws/aws-sdk-go-v2/service/s3`
  - `github.com/hashicorp/golang-lru/v2 v2.x`
  - `golang.org/x/sync`
  - `go.uber.org/zap`

### Step 2: Create `r2alias.go`
- Define `type R2Alias struct` exactly as specified in RFC §4.3.4 (read the spec at `docs/rfc/gxy-cassiopeia.md` lines 387-464 and match field names + JSON tags + types)
- Include `aliasEntry` struct with fields `DeployID string; Present bool`
- Implement `CaddyModule()` returning `caddy.ModuleInfo{ID: "http.handlers.r2_alias", New: func() caddy.Module { return new(R2Alias) }}`
- Implement `Validate()`:
  - Required fields: `Bucket`, `Endpoint` — non-empty strings
  - Default values if zero: `CacheTTL = 15*time.Second`, `CacheMaxEntries = 10000`, `PreviewSuffix = "--preview"`, `RootDomain = "freecode.camp"`, `DeployIDRegex = "^[A-Za-z0-9._-]{1,64}$"`, `Region = "auto"`
  - Validate `DeployIDRegex` compiles
  - Validate `CacheTTL > 0`, `CacheMaxEntries > 0`
- Implement a stub `Provision(ctx caddy.Context) error` that returns nil for now (Task 02 replaces this)
- Implement a stub `ServeHTTP(w, req, next) error` that just calls `next.ServeHTTP(w, req)` — Task 03 replaces this
- Register via `init()` calling `caddy.RegisterModule(R2Alias{})` and `httpcaddyfile.RegisterHandlerDirective("r2_alias", parseCaddyfile)`
- Declare the 4 interface guards as shown in RFC §4.3.4

### Step 3: Create `caddyfile.go`
- Implement `parseCaddyfile(h httpcaddyfile.Helper) (caddyhttp.MiddlewareHandler, error)` that allocates a new R2Alias, calls `UnmarshalCaddyfile(h.Dispenser)`, returns it
- Implement `(r *R2Alias) UnmarshalCaddyfile(d *caddyfile.Dispenser) error`:
  - Parse tokens: `bucket <str>`, `endpoint <str>`, `region <str>`, `access_key_id <str>`, `secret_access_key <str>`, `cache_ttl <duration>`, `cache_max_entries <int>`, `preview_suffix <str>`, `root_domain <str>`, `deploy_id_regex <str>`
  - Unknown tokens return `d.Errf("unrecognized option: %s", d.Val())`

### Step 4: Run `go mod tidy`
- From inside the module directory: `go mod tidy`
- This generates `go.sum` and resolves transitive deps

### Step 5: Verify compile + vet
- `go build ./...` (exit 0)
- `go vet ./...` (no output)

## Files

- Create: `docker/images/caddy-s3/modules/r2alias/r2alias.go`
- Create: `docker/images/caddy-s3/modules/r2alias/caddyfile.go`
- Create: `docker/images/caddy-s3/modules/r2alias/go.mod`
- Create: `docker/images/caddy-s3/modules/r2alias/go.sum` (via `go mod tidy`)

## Acceptance Criteria

- `cd docker/images/caddy-s3/modules/r2alias && go build ./...` — exit 0
- `cd docker/images/caddy-s3/modules/r2alias && go vet ./...` — no output
- `Validate()` rejects empty bucket with a clear error
- `Validate()` rejects empty endpoint with a clear error
- `Validate()` rejects CacheTTL <= 0 with a clear error
- Struct fields match RFC §4.3.4 exactly (names, JSON tags, types)

## Context

This Caddy module is the heart of gxy-cassiopeia serving. It reads alias files from R2 and rewrites request paths to the target deploy prefix, enabling "thin Netlify/Vercel" deploys where a promote is just a text-file flip in R2. This task provides only the skeleton; Tasks 02 and 03 add the cache and ServeHTTP logic.

## When Stuck

If `go mod tidy` fails to resolve dependencies, check that the package path in `go.mod` matches the directory structure under a repo that would be fetched by `go get`. You may need to use Go workspaces or `replace` directives locally. If blocked, report the exact error and what you tried.

## Constraints

- TDD discipline: scaffold-level tests are optional here since logic is in Tasks 02/03; no behavioral tests required for stubs
- Verify before claiming done: run the exact verification commands above and show output
- Do NOT implement cache logic (Task 02)
- Do NOT implement ServeHTTP path rewrite or S3 calls (Task 03)
- Do NOT touch `k3s/gxy-static/` or `docker/images/landing/`
- Do NOT run git write commands
```

**Depends on:** None

---

### Task 01b [M]: Caddy `r2_alias` module — `caddy.fs.r2` filesystem (added 2026-04-18, D32)

**Traceability:** Implements R4 + D32 (§5.30) | Resolves `caddy-fs-s3` upstream-abandonment risk in 2026-04-18 audit.

**Files:**

- Create: `docker/images/caddy-s3/modules/r2alias/filesystem.go`
- Create: `docker/images/caddy-s3/modules/r2alias/filesystem_test.go`
- Modify: `docker/images/caddy-s3/modules/r2alias/caddyfile.go` (register filesystem Caddyfile directive parser)

#### Context

Per D32 (§5.30), the S3 filesystem layer moves in-tree instead of depending on `sagikazarmark/caddy-fs-s3@v0.12.0` (14 months stale at time of audit). This task adds a **sibling Caddy module** in the same Go package as `R2Alias`, registered at `caddy.fs.r2`, implementing `fs.FS` + `fs.StatFS`. Consumed by `file_server { fs <name> }` after `r2_alias` rewrites the path.

Split out from the original T04 scope so the module can be tested (T04) and built (T05) with the FS layer already in place. No changes to the middleware handler (T01–T03) — those ship untouched.

#### Acceptance Criteria

- GIVEN a valid R2FS WHEN `Open("site-a/deploys/v1/index.html")` is called THEN returns `fs.File` whose `Stat()` reports the S3 ContentLength + LastModified.
- GIVEN the object does not exist WHEN `Open` or `Stat` is called THEN returns an error that satisfies `errors.Is(err, fs.ErrNotExist)`.
- GIVEN R2 returns 5xx WHEN `Open` is called THEN returns an error distinguishable from `fs.ErrNotExist` (tests use `errors.Is(err, fs.ErrNotExist)` returning false + non-nil error).
- GIVEN the object body WHEN read in full THEN matches byte-for-byte what was PUT.
- GIVEN a request for Range bytes 0-99 WHEN `file_server` calls `ReadAt` OR `Seek`+`Read` THEN the first 100 bytes match. (Implementation MAY buffer full body; Seeker interface MUST be satisfied.)
- GIVEN Caddyfile `filesystem r2 r2 { bucket x endpoint y ... }` THEN `UnmarshalCaddyfile` populates R2FS struct fields.
- GIVEN `caddy list-modules` run against the xcaddy-built image (T05) THEN output contains `caddy.fs.r2`.
- GIVEN `go test -race -v` THEN passes including the new `TestR2FS_*` suite.

#### Verification

```bash
cd docker/images/caddy-s3/modules/r2alias && go test -race -v -run TestR2FS
```

#### Constraints

- Module ID: `caddy.fs.r2` (not `caddy.fs.r2_s3` — concise, distinct from upstream `caddy.fs.s3`).
- Reuse AWS SDK v2 imports already in `r2alias.go`. Do NOT add new third-party Go deps.
- Do NOT share the `R2Alias.client` field directly — R2FS has its own S3 client so each Caddyfile block can wire independent credentials if needed.
- Body buffer limit: 100 MB per object (configurable via `max_file_size`). Larger returns an error.
- No directory-listing support (file_server static serving doesn't need ReadDirFS).

#### Agent Prompt

```
You are implementing Task 01b: r2_alias filesystem sibling module.

## Your Task

Add `caddy.fs.r2` to the same Go package as `R2Alias`. Implement fs.FS + fs.StatFS backed by S3 GetObject/HeadObject. Register as a Caddy module with Caddyfile grammar `filesystem r2 r2 { bucket ... endpoint ... access_key_id ... secret_access_key ... use_path_style }`.

### Step 1: RED tests in filesystem_test.go
- TestR2FS_Open_Success — stub fetcher returns body bytes; verify file content + Stat.Size matches.
- TestR2FS_Open_NotFound — stub returns NoSuchKey; errors.Is(err, fs.ErrNotExist) is true.
- TestR2FS_Open_5xx — stub returns 5xx; non-nil error, NOT fs.ErrNotExist.
- TestR2FS_Stat_Success — HeadObject path returns correct size + modtime.
- TestR2FS_Seeker — opened file implements io.ReadSeeker; Seek(50, 0) then read matches bytes [50:].
- TestR2FS_UnmarshalCaddyfile — full block parses into struct.

### Step 2: GREEN filesystem.go
- R2FS struct with config fields
- Open(name) returns *r2File{bytes.Reader + fileInfo}
- Stat(name) uses HeadObject
- Provision loads AWS SDK config, creates S3 client, sets UsePathStyle
- UnmarshalCaddyfile parses directive tokens
- Interface guards at end: fs.StatFS, caddy.Provisioner, caddyfile.Unmarshaler

### Step 3: Register module in init()
- caddy.RegisterModule(R2FS{}) in a new init() (or append to existing)

### Step 4: go test -race -v — all pass

## Files
- Create: docker/images/caddy-s3/modules/r2alias/filesystem.go
- Create: docker/images/caddy-s3/modules/r2alias/filesystem_test.go
- Modify: docker/images/caddy-s3/modules/r2alias/caddyfile.go (if Caddyfile registration helper is shared)

## Constraints
- No new third-party deps
- Same package as R2Alias; SEPARATE struct, SEPARATE module ID
- TDD: RED first, verify fail, GREEN, verify pass
- Do NOT run git write commands
```

**Depends on:** Task 01

---

### Task 02 [M]: Caddy `r2_alias` module — alias cache (bounded LRU + singleflight)

**Traceability:** Implements R4 | Constrained by D27 (bounded LRU + singleflight)
**Files:**

- Create: `docker/images/caddy-s3/modules/r2alias/cache.go`
- Create: `docker/images/caddy-s3/modules/r2alias/cache_test.go`
- Modify: `docker/images/caddy-s3/modules/r2alias/r2alias.go` (wire the cache into `Provision`)

#### Context

Implement the alias cache per RFC §4.3.5. Bounded LRU + TTL from `hashicorp/golang-lru/v2/expirable` + `singleflight` stampede control. Missing-alias sentinel entries (`Present: false`) cache with full TTL.

The cache must expose a `Resolve(ctx, site, aliasName string) (aliasEntry, error)` method. Internally it keys on `bucket/site/aliasName`, uses singleflight to deduplicate concurrent misses, and calls an injected `fetchFn func(ctx, key) (aliasEntry, error)` on cache miss. The S3 call is passed in so the cache can be tested with a stub fetcher.

#### Acceptance Criteria

- GIVEN the cache is empty WHEN `Resolve("sites/hello.freecode.camp", "production")` is called THEN fetchFn is invoked once and result is cached
- GIVEN the cache has an entry within TTL WHEN resolved THEN fetchFn is NOT called (cache hit)
- GIVEN the cache has an expired entry WHEN resolved THEN fetchFn is invoked once
- GIVEN the cache is at max capacity WHEN a new entry is added THEN LRU evicts the oldest
- GIVEN fetchFn returns "missing" (Present=false) WHEN resolved THEN cached as sentinel with full TTL
- GIVEN 1000 concurrent `Resolve` calls for the same uncached key WHEN fetchFn takes 200ms THEN exactly 1 fetchFn invocation occurs (singleflight)
- GIVEN fetchFn returns an error THEN the cache does NOT store the entry; the next call retries

#### Verification

```bash
cd docker/images/caddy-s3/modules/r2alias && go test -race -v -run TestCache
```

**Expected output:** All `TestCache*` tests pass with `-race`, exit 0.

#### Constraints

- Do NOT call AWS SDK directly — the cache takes a fetchFn parameter
- Do NOT implement HTTP handling — ServeHTTP is Task 03's scope
- Use `hashicorp/golang-lru/v2/expirable` exactly (not plain LRU or custom TTL)
- Use `golang.org/x/sync/singleflight` for stampede protection
- Memory bound MUST be enforced — do not use unbounded maps

#### Agent Prompt

```
You are implementing Task 02: Caddy r2_alias module — alias cache (bounded LRU + singleflight).

## Your Task

Implement `cache.go` in the r2_alias module with bounded LRU TTL cache + singleflight stampede protection per RFC §4.3.5 lines 465-477.

### Step 1: Write failing tests first (TDD)
Create `cache_test.go` with these table-driven tests:
- `TestCache_HitAfterMiss` — first call invokes fetchFn, second call (within TTL) does not
- `TestCache_TTLExpiry` — after TTL, fetchFn invoked again
- `TestCache_LRUEvictionAtCapacity` — capacity=3, insert 4 distinct keys, oldest evicted
- `TestCache_MissingSentinelCached` — fetchFn returns Present=false, second call returns same sentinel without re-fetch
- `TestCache_Singleflight` — 1000 concurrent calls with slow fetchFn (200ms sleep), assert exactly 1 invocation using atomic counter
- `TestCache_ErrorNotCached` — fetchFn returns error; next call retries (no sticky error state)

Run `go test` — tests should FAIL (no cache yet).

### Step 2: Implement cache.go
- Define `aliasCache` type wrapping `*expirable.LRU[string, aliasEntry]` and `singleflight.Group`
- `newAliasCache(size int, ttl time.Duration) *aliasCache` constructor
- `(c *aliasCache) Resolve(ctx context.Context, bucket, site, aliasName string, fetchFn func(context.Context, string) (aliasEntry, error)) (aliasEntry, error)`:
  - Cache key: `bucket + "/" + site + "/" + aliasName`
  - Check cache — return hit
  - Use `singleflight.Do(key, func() (interface{}, error) { ... })` to wrap fetchFn
  - On fetchFn success: `cache.Add(key, entry)` then return
  - On fetchFn error: do NOT cache; propagate error
- Both Present=true and Present=false entries cache with full TTL (no half-TTL for missing)

### Step 3: Wire into Provision
- Modify `r2alias.go` `Provision(ctx)`:
  - Initialize `r.cache = newAliasCache(r.CacheMaxEntries, r.CacheTTL)`

### Step 4: Verify tests pass
- `cd docker/images/caddy-s3/modules/r2alias && go test -race -v -run TestCache`
- All pass; no race detector errors

### Step 5: Verify `go vet`
- `go vet ./...` — no output

## Files

- Create: `docker/images/caddy-s3/modules/r2alias/cache.go`
- Create: `docker/images/caddy-s3/modules/r2alias/cache_test.go`
- Modify: `docker/images/caddy-s3/modules/r2alias/r2alias.go` (Provision wires cache)

## Acceptance Criteria

Every acceptance criterion in the TASKS file must pass as a test. Run `go test -race -v -run TestCache` and show all tests pass.

## Context

This cache sits in front of every alias lookup. Bounded LRU prevents memory inflation under Host-header scan attacks (§4.3.5 — the attacker supplies arbitrary subdomains, each triggers a lookup; unbounded cache would OOM). Singleflight prevents thundering-herd R2 calls when many concurrent requests hit an uncached site.

## When Stuck

If `expirable.LRU` API surface has changed from v2.x, read the current godoc via the Go documentation site. The test cases are the source of truth — they define expected behavior.

## Constraints

- TDD discipline: RED-GREEN-REFACTOR. Write tests first, verify they fail, implement, verify they pass.
- Verify before claiming done: run tests with `-race`, show output
- Do NOT call AWS SDK directly — pass fetchFn as parameter
- Do NOT implement HTTP handling
- Do NOT touch `k3s/gxy-static/` or other repos
- Do NOT run git write commands
```

**Depends on:** Task 01

---

### Task 03 [L]: Caddy `r2_alias` module — ServeHTTP handler + S3 integration

**Traceability:** Implements R4 | Constrained by D4 (custom module), D5 (preview routing), D29 (host parsing)
**Files:**

- Modify: `docker/images/caddy-s3/modules/r2alias/r2alias.go` (replace ServeHTTP stub, fill Provision)
- Create: `docker/images/caddy-s3/modules/r2alias/host.go` (host parsing helpers)
- Create: `docker/images/caddy-s3/modules/r2alias/host_test.go`

#### Context

Implement the full ServeHTTP per RFC §4.3.2 and §4.3.6-4.3.7.

Responsibilities in order:

1. Parse Host header → `{site}` + `{alias_name}` (§4.3.7): if suffix `--preview`, strip from leftmost label → site=`<stripped>.freecode.camp`, alias=`preview`; else site=`<Host verbatim>`, alias=`production`. Reject Hosts not matching `root_domain`.
2. Call `cache.Resolve(ctx, bucket, site, aliasName, r.fetchAlias)` with `fetchAlias` as the S3 GetObject path.
3. On `aliasEntry.Present=false`: respond 404 "Not Found".
4. On `aliasEntry.Present=true`: validate `DeployID` against the configured regex + reject `..` + reject empty. If invalid, 404.
5. Rewrite `req.URL.Path = "/" + site + "/deploys/" + deployID + originalPath`.
6. Call `next.ServeHTTP(w, req)` so `file_server { fs r2 }` serves from the rewritten path.
7. On S3 5xx during alias fetch: respond 503 with `Retry-After: 30`.

`Provision` also initializes the AWS SDK v2 S3 client with the configured endpoint + credentials (path-style addressing for R2).

#### Acceptance Criteria

- GIVEN Host `hello-world.freecode.camp`, alias `production` → `20260501-120000-a1b2c3d` WHEN GET `/assets/x.js` THEN `req.URL.Path` becomes `/hello-world.freecode.camp/deploys/20260501-120000-a1b2c3d/assets/x.js` before `next.ServeHTTP`
- GIVEN Host `hello-world--preview.freecode.camp`, alias `preview` → deploy ID THEN path is `/hello-world.freecode.camp/deploys/<id>/...` (site key uses the production subdomain, not preview)
- GIVEN Host `notaroot.example.com` (no `root_domain` match) THEN 404
- GIVEN alias value with `..` segments THEN 404 (path traversal blocked)
- GIVEN alias value > 64 chars THEN 404
- GIVEN alias value with trailing whitespace THEN trimmed, proceeds normally
- GIVEN S3 returns 404 on alias GetObject THEN 404 to client; cache records `Present=false`
- GIVEN S3 returns 500 on alias GetObject THEN 503 to client with `Retry-After: 30`; no cache entry
- GIVEN panic in handler THEN recovered (no process crash); 500 logged with structured fields

#### Verification

```bash
cd docker/images/caddy-s3/modules/r2alias && go test -race -v
```

**Expected output:** all tests pass (including TestCache* from Task 02 and new TestHost*/TestServeHTTP\* tests), no races.

#### Constraints

- Do NOT serve the deploy files yourself — `file_server { fs r2 }` does that (the module rewrites the path only)
- AWS SDK v2 must use `aws.EndpointResolverWithOptionsFunc` pointing at the configured endpoint, `UsePathStyle: true`
- Panic recovery required: wrap body of ServeHTTP in `defer func() { if r := recover() ... }()`
- Structured logging via `r.logger.Error` / `r.logger.Warn` — fields: `site`, `alias_name`, `upstream_status`, `deploy_id`

#### Agent Prompt

````
You are implementing Task 03: Caddy r2_alias module — ServeHTTP handler + S3 integration.

## Your Task

Implement ServeHTTP and fill in Provision per RFC §4.3.2, §4.3.6-4.3.7.

### Step 1: Write failing tests
Create `host_test.go` table-driven for:
- parseSiteAndAlias("hello-world.freecode.camp") → ("hello-world.freecode.camp", "production")
- parseSiteAndAlias("hello-world--preview.freecode.camp") → ("hello-world.freecode.camp", "preview")
- parseSiteAndAlias("foo.bar.freecode.camp") → ("foo.bar.freecode.camp", "production")
- parseSiteAndAlias("other.com") → error (no root_domain match)
- parseSiteAndAlias("freecode.camp") → error (no subdomain — apex is handled separately in Caddyfile)
- parseSiteAndAlias("--preview.freecode.camp") → error (empty site label)

Create `TestServeHTTP_Rewrite` using `httptest.NewRecorder` and a mock next-handler. Use the cache's fetchFn injection to return canned alias entries. Verify `req.URL.Path` mutation before next.ServeHTTP.

Run tests — they should FAIL.

### Step 2: Implement host.go
- `parseSiteAndAlias(host, rootDomain, previewSuffix string) (site, alias string, err error)`:
  - host must end with `.` + rootDomain (else error "host not under root domain")
  - Strip rootDomain + leading `.` to get prefix
  - If prefix has `--preview` suffix on first label: strip it, alias="preview"
  - Else alias="production"
  - Re-construct site = prefix + "." + rootDomain
  - Empty prefix or apex → error

### Step 3: Implement ServeHTTP in r2alias.go
- Wrap body in defer-recover — on panic, log + write 500
- Parse Host → (site, aliasName) — on error: return 404 via `caddyhttp.Error(http.StatusNotFound, err)`
- Call `r.cache.Resolve(ctx, r.Bucket, site, aliasName, r.fetchAlias)`
- On error from S3 (wrapped, identifiable via errors.As/errors.Is):
  - 5xx → 503 with Retry-After, logger.Error
  - Other → 500
- If entry.Present == false → 404
- Validate DeployID against r.DeployIDRegex (compiled in Provision and stored as *regexp.Regexp on struct)
- Reject if value contains `..` (extra safety)
- Rewrite: `req.URL.Path = "/" + site + "/deploys/" + entry.DeployID + req.URL.Path`
  - Handle edge case: if original path is empty or "/" → path becomes "/site/deploys/id/" (file_server handles index.html lookup)
- Return `next.ServeHTTP(w, req)`

### Step 4: Implement fetchAlias (method on *R2Alias)
- Key: `fmt.Sprintf("%s/%s", site, aliasName)` — bucket is implicit in client config
- Call `r.client.GetObject(ctx, &s3.GetObjectInput{Bucket: &r.Bucket, Key: &key})`
- Read body (io.LimitReader with 1024 bytes max — alias files are tiny)
- Trim whitespace
- Return `aliasEntry{DeployID: trimmed, Present: true}` if non-empty
- On NoSuchKey error → return `aliasEntry{Present: false}, nil` (missing is not an error)
- On other S3 error → wrap with fmt.Errorf and return

### Step 5: Fill Provision
- Load AWS config:
  ```go
  cfg, err := config.LoadDefaultConfig(ctx,
      config.WithRegion(r.Region),
      config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(r.AccessKeyID, r.SecretAccessKey, "")),
  )
  ```
- Create S3 client with endpoint resolver:
  ```go
  r.client = s3.NewFromConfig(cfg, func(o *s3.Options) {
      o.BaseEndpoint = &r.Endpoint
      o.UsePathStyle = true
  })
  ```
- Compile deploy-ID regex: `r.deployIDPattern = regexp.MustCompile(r.DeployIDRegex)`
- Initialize cache: `r.cache = newAliasCache(r.CacheMaxEntries, r.CacheTTL)`
- Initialize logger: `r.logger = ctx.Logger()`

### Step 6: Run tests
- `go test -race -v` — all pass

## Files

- Modify: `docker/images/caddy-s3/modules/r2alias/r2alias.go`
- Create: `docker/images/caddy-s3/modules/r2alias/host.go`
- Create: `docker/images/caddy-s3/modules/r2alias/host_test.go`
- (r2alias.go will get TestServeHTTP_* added too — OK to colocate in r2alias_test.go)

## Acceptance Criteria

All TestHost_* and TestServeHTTP_* tests pass with -race. All Task 02 TestCache_* still pass.

## Context

This is the core serving logic. The module rewrites paths based on alias files in R2; `file_server { fs r2 }` downstream serves the files. Panic recovery is critical because a bug here affects every site on the galaxy.

## When Stuck

AWS SDK v2 S3 client with custom endpoint is sometimes tricky — R2 requires `UsePathStyle: true`. If `NoSuchKey` is not distinguishable via errors.As/errors.Is, check the exact error type via `var nsk *types.NoSuchKey; errors.As(err, &nsk)`.

## Constraints

- TDD: write tests first, show them failing, then implement
- Do NOT do file serving in this module — rewrite path only
- Must handle panics (no Caddy crash on bug)
- Do NOT touch `k3s/gxy-static/` or other repos
- Do NOT run git write commands
````

**Depends on:** Task 02

---

### Task 04 [M]: Caddy `r2_alias` + `caddy.fs.r2` — integration tests with Adobe S3Mock

**Traceability:** Implements R4 test strategy RFC §11.2 (revised 2026-04-18 for MinIO archival + D32).
**Files:**

- Create: `docker/images/caddy-s3/modules/r2alias/integration_test.go`
- Create: `docker/images/caddy-s3/modules/r2alias/testdata/site-a/deploys/v1/index.html` (fixture)
- Create: `docker/images/caddy-s3/modules/r2alias/testdata/site-a/deploys/v2/index.html` (fixture)

#### Context

Integration test the full module stack in-process against an **Adobe S3Mock** container (`adobe/s3mock`). Uses testcontainers-go's generic container API — no dedicated module required. Boot S3Mock, populate deploy fixtures + alias files via AWS SDK v2 PutObject, run a full Caddy config in-process using `caddytest.Tester`, curl requests with various Host headers, assert responses.

**Dep substitution rationale.** The original draft used MinIO, which archived its community edition on 2026-02-12 (no more Docker images). Adobe S3Mock is Apache 2.0, actively maintained, purpose-built for S3 test harnesses, and runs cleanly under testcontainers-go. See infra field notes §"Dependency audit" (2026-04-18).

This task now also exercises the sibling `caddy.fs.r2` module (T01b) — the file body in the response comes from it, not a third-party plugin.

#### Acceptance Criteria

- GIVEN S3Mock running with `site-a/deploys/v1/index.html` + alias `site-a/production=v1` WHEN GET `http://localhost:port/` with `Host: site-a.test.camp` THEN response body contains `V1` (the fixture content).
- GIVEN alias flipped to `v2` WHEN next request after cache TTL (500ms in test config) THEN response body contains `V2`.
- GIVEN preview alias `site-a/preview=v2` WHEN GET with `Host: site-a--preview.test.camp` THEN response body contains `V2` — and the internally-rewritten path uses `site-a.test.camp` as the site key (production subdomain), not `site-a--preview.test.camp`.
- GIVEN no alias for `dead.test.camp` WHEN GET with that Host THEN 404.

#### Verification

```bash
cd docker/images/caddy-s3/modules/r2alias && go test -race -v -tags=integration -run TestIntegration -timeout 180s
```

**Expected output:** all integration tests pass. First run pulls `adobe/s3mock` image (~30 s, ~120 MB).

#### Constraints

- Build tag `//go:build integration` (opt-in).
- Use `test.camp` as root domain in tests (NOT `freecode.camp`).
- Cache TTL in test config: 500ms (allows in-test alias flips).
- Pin S3Mock image by digest or explicit version tag — never `:latest`.
- Clean up testcontainer on test exit (`t.Cleanup(...)` / `defer container.Terminate`).

#### Agent Prompt

```
You are implementing Task 04: r2_alias + caddy.fs.r2 integration tests with Adobe S3Mock.

## Preconditions
- T01b (gxy-static-k7d.3X) is CLOSED — caddy.fs.r2 module exists and unit-tests pass.
- Docker daemon reachable (OrbStack / Docker Desktop).

## Your Task

### Step 1: go.mod deps
- go get github.com/testcontainers/testcontainers-go@latest
- (caddytest is already a transitive dep of caddy/v2; no separate add needed)

### Step 2: testdata fixtures
- testdata/site-a/deploys/v1/index.html with body `<html>V1</html>`
- testdata/site-a/deploys/v2/index.html with body `<html>V2</html>`

### Step 3: integration_test.go with build tag
- `//go:build integration`
- package r2alias_test (external test package — r2alias registers via init())
- Helper: startS3Mock(t) *s3Mock — returns struct with endpoint + bucket name + S3 client; uses testcontainers generic container API against `adobe/s3mock:<PIN>`; env `initialBuckets=gxy-cassiopeia-test`; wait on port 9090 listening.
- Helper: uploadDeployFixtures(t, client, site, version) — uploads testdata files under site/deploys/{version}/.
- Helper: putAlias(t, client, site, aliasName, deployID) — PutObject of the alias file content.
- Helper: startCaddy(t, s3mockEndpoint, cacheTTL string) *caddytest.Tester — caddytest.NewTester + InitServer with a Caddyfile that:
  * order r2_alias before file_server
  * filesystem r2 r2 { ... pointing at s3mockEndpoint ... }
  * r2_alias { ... cache_ttl <cacheTTL> ... root_domain test.camp ... }
  * file_server { fs r2 }
- Helper: doGet(t, tester, host, path) (int, string) — HTTP request with custom Host header; returns status + body.

### Step 4: Test cases (all serial; no t.Parallel at top-level — shared Caddy/S3Mock restart is expensive)
- TestIntegration_ResolveProduction
- TestIntegration_AliasFlip (exercises cache TTL)
- TestIntegration_PreviewRouting (site key = production)
- TestIntegration_MissingSite404

### Step 5: Verify
- `go test -race -v -tags=integration -run TestIntegration -timeout 180s`

## Files
- docker/images/caddy-s3/modules/r2alias/integration_test.go
- docker/images/caddy-s3/modules/r2alias/testdata/site-a/deploys/v{1,2}/index.html
- Modify: go.mod + go.sum

## Constraints
- Adobe S3Mock image pinned (by version tag) — NEVER `:latest`.
- r2_alias and caddy.fs.r2 share no code at the struct level; they DO share AWS SDK client construction patterns — fine.
- Do NOT put real R2 credentials anywhere.
- Do NOT run git write commands.
```

**Depends on:** Task 03 + Task 01b

---

### Task 05 [M]: Dockerfile update + build pipeline

**Traceability:** Implements R4 build, §4.3.8 | Constrained by D30 (version pinning)
**Files:**

- Modify: `docker/images/caddy-s3/Dockerfile`
- Create: `.woodpecker/caddy-s3-build.yaml` (pipeline for the infra repo itself — builds image on change)
- Modify: `justfile` (add `caddy-s3-build` recipe)

#### Context

Update the Dockerfile to pin Caddy 2.11.2 (D30) and build with ONLY the in-tree r2alias module via xcaddy (D32 — no third-party Caddy plugins). Also add a Woodpecker pipeline to the infra repo that rebuilds + pushes to GHCR on changes to `docker/images/caddy-s3/**`.

#### Acceptance Criteria

- GIVEN the Dockerfile WHEN `docker buildx build docker/images/caddy-s3/` runs THEN image builds successfully.
- GIVEN the built image WHEN `docker run --rm ghcr.io/freecodecamp-universe/caddy-s3:<tag> caddy list-modules` runs THEN output contains both `http.handlers.r2_alias` (T01–T03) AND `caddy.fs.r2` (T01b). It does NOT contain `caddy.fs.s3` — the third-party `caddy-fs-s3` dep is removed per D32.
- GIVEN a change to `docker/images/caddy-s3/modules/r2alias/*.go` merged to main WHEN Woodpecker triggers THEN image builds, tests run, image pushed to `ghcr.io/freecodecamp-universe/caddy-s3:{YYYYMMDD}-{sha7}`.
- GIVEN `just caddy-s3-build` locally THEN builds + tags the image with `dev-<sha>`.
- GIVEN `hadolint docker/images/caddy-s3/Dockerfile` THEN no errors (warnings OK).

#### Verification

```bash
docker buildx build -t caddy-s3-test:local docker/images/caddy-s3/ \
  && docker run --rm caddy-s3-test:local caddy list-modules | grep -E 'r2_alias|caddy\.fs\.r2'
```

**Expected output:** both modules listed. `caddy.fs.s3` MUST NOT appear.

#### Constraints

- Pin `caddy:2.11-builder` and `caddy:2.11-alpine` exactly — no `:2`, `:latest`, or sub-2.11 tags.
- Pin `xcaddy build v2.11.2`. Do NOT include `--with github.com/sagikazarmark/caddy-fs-s3` per D32.
- Use multi-stage build (already in use).
- Pipeline uses Woodpecker, not GHA (D1 — all-in on Woodpecker).
- hadolint must pass with no errors.

#### Agent Prompt

````
You are implementing Task 05: Dockerfile update + build pipeline for caddy-s3 image.

## Your Task

Update Dockerfile per RFC §4.3.8 (D30) and add a Woodpecker pipeline that rebuilds on changes.

### Step 1: Update Dockerfile
Replace `docker/images/caddy-s3/Dockerfile` with:

```dockerfile
FROM caddy:2.11-builder AS builder

ENV GOTOOLCHAIN=auto

COPY modules/r2alias /src/modules/r2alias

# D32 (§5.30): no third-party Caddy plugins. The in-tree r2alias package
# registers both http.handlers.r2_alias and caddy.fs.r2.
RUN xcaddy build v2.11.2 \
    --with github.com/freeCodeCamp-Universe/infra/docker/images/caddy-s3/modules/r2alias=/src/modules/r2alias

FROM caddy:2.11-alpine

LABEL org.opencontainers.image.source=https://github.com/freeCodeCamp-Universe/infra
LABEL org.opencontainers.image.description="Caddy with in-tree r2alias module (alias resolver + R2 filesystem) for Universe static constellations"
LABEL org.opencontainers.image.licenses=Apache-2.0

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
```

### Step 2: Create .woodpecker/caddy-s3-build.yaml in the infra repo
(This is a pipeline for the infra repo itself, not for constellations.)

```yaml
when:
  - event: push
    branch: main
    path:
      - docker/images/caddy-s3/**
  - event: manual

steps:
  test:
    image: golang:1.22-alpine
    commands:
      - apk add --no-cache git make
      - cd docker/images/caddy-s3/modules/r2alias
      - go mod download
      - go test -race ./...

  build-push:
    image: docker:24
    environment:
      GHCR_USER:
        from_secret: ghcr_user
      GHCR_TOKEN:
        from_secret: ghcr_token
    commands:
      - export TAG=$(date -u +%Y%m%d)-$(echo ${CI_COMMIT_SHA} | cut -c1-7)
      - echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin
      - docker buildx build --platform linux/amd64 --push -t ghcr.io/freecodecamp-universe/caddy-s3:${TAG} docker/images/caddy-s3/
      - docker buildx build --platform linux/amd64 --push -t ghcr.io/freecodecamp-universe/caddy-s3:latest-main docker/images/caddy-s3/
```

### Step 3: Add justfile recipe
Append to justfile under `[group('docker')]`:

```just
[group('docker')]
caddy-s3-build:
    #!/usr/bin/env bash
    set -euo pipefail
    TAG="dev-$(git rev-parse --short HEAD)"
    docker buildx build -t "ghcr.io/freecodecamp-universe/caddy-s3:${TAG}" docker/images/caddy-s3/
    echo "Built: ghcr.io/freecodecamp-universe/caddy-s3:${TAG}"
```

### Step 4: Verify local build
```
just caddy-s3-build
docker run --rm ghcr.io/freecodecamp-universe/caddy-s3:dev-$(git rev-parse --short HEAD) caddy list-modules | grep -E 'r2_alias|caddy\.fs\.r2'
# Also verify the third-party plugin is NOT present:
docker run --rm ghcr.io/freecodecamp-universe/caddy-s3:dev-$(git rev-parse --short HEAD) caddy list-modules | grep -q 'caddy.fs.s3' && echo "FAIL: caddy.fs.s3 present (D32 violated)" || echo "OK: no third-party fs modules"
```

## Files

- Modify: `docker/images/caddy-s3/Dockerfile`
- Create: `.woodpecker/caddy-s3-build.yaml`
- Modify: `justfile`

## Acceptance Criteria

- `just caddy-s3-build` completes with exit 0
- `docker run ... caddy list-modules` lists both `http.handlers.r2_alias` and `caddy.fs.r2`; does NOT list `caddy.fs.s3` (per D32)
- Woodpecker pipeline YAML validates (syntactic check via `woodpecker-cli lint` if available, else manual review)
- `hadolint Dockerfile` passes without errors

## Context

This is the build gate before deploy. The pipeline triggers on changes under `docker/images/caddy-s3/**` so module updates automatically rebuild the image.

## When Stuck

If xcaddy fails with "module not found" for the local r2alias module, check that the COPY path matches the `--with` replacement path exactly. GOTOOLCHAIN=auto allows xcaddy to pull the Go version required by go.mod.

## Constraints

- Pin versions explicitly — no floating tags
- Use Woodpecker, not GitHub Actions (D1 — all-in on Woodpecker)
- Do NOT touch other images under `docker/images/` (landing/)
- Do NOT run git write commands
````

**Depends on:** Task 04

---

### Task 06 [M]: ~~Hetzner Ansible inventory + cloud-init parity dry-run~~ (DEFERRED to post-M5)

**Status:** Deferred. Hetzner account is not yet provisioned. gxy-launchbase moves to DO FRA1 for M0–M5 (see Task 07). The Hetzner migration — `ansible/inventory/hetzner.yml`, `hetzner.hcloud` collection in `ansible/requirements.yml`, single-node cloud-init parity dry-run, and the docs/runbooks/hetzner-cloud-init-dryrun.md runbook — is tracked as **Task 30 (post-M5 Hetzner migration)**.

Do NOT implement this task. The corresponding beads issue has been closed with reason: `deferred-to-t30`.

**Depends on:** None

---

### Task 07 [M]: gxy_launchbase_k3s group_vars + bootstrap (DO FRA1)

**Traceability:** Implements R1 | Constrained by §4.1.1, D13 (DO initial; Hetzner post-M5)
**Files:**

- Create: `ansible/inventory/group_vars/gxy_launchbase_k3s.yml`

#### Context

Add the per-galaxy configuration file for gxy-launchbase. The existing `play-k3s--bootstrap.yml` playbook reads `galaxy_name`, `cilium_cluster_id`, and `server_config_yaml` from group_vars and applies them. No playbook changes needed.

gxy-launchbase initial provider is **DigitalOcean FRA1** (3× s-4vcpu-8gb-amd, tag `_gxy-launchbase-k3s`). Hetzner migration is deferred to post-M5 (Task 30). The existing `ansible/inventory/digitalocean.yml` dynamic inventory already maps tag `_gxy-launchbase-k3s` → Ansible group `gxy_launchbase_k3s`; no new inventory file is needed.

Actual cluster bootstrap (provisioning 3 droplets + running the playbook) is an **operator action** documented in the FLIGHT-MANUAL.

#### Acceptance Criteria

- GIVEN the group_vars file WHEN parsed as YAML THEN no syntax errors
- GIVEN the file WHEN diffed against `gxy_static_k3s.yml` THEN only `galaxy_name`, `cilium_cluster_id`, `cluster-cidr`, `service-cidr`, and `etcd-s3-folder` differ
- GIVEN `galaxy_name: gxy-launchbase` AND `cilium_cluster_id: 3` AND CIDRs `10.6.0.0/16` + `10.16.0.0/16` THEN match the RFC (§4.1.1)
- GIVEN a droplet tagged `_gxy-launchbase-k3s` exists WHEN `ansible-inventory -i ansible/inventory/digitalocean.yml --list` runs THEN the droplet appears under group `gxy_launchbase_k3s` (operator-verified post-provisioning, not part of this automated task)

#### Verification

```bash
yamllint -d "{extends: default, rules: {line-length: disable}}" ansible/inventory/group_vars/gxy_launchbase_k3s.yml && \
  diff <(yq 'keys' ansible/inventory/group_vars/gxy_launchbase_k3s.yml) <(yq 'keys' ansible/inventory/group_vars/gxy_static_k3s.yml)
```

**Expected output:** yamllint passes with no errors; diff shows identical top-level keys.

#### Constraints

- CIDRs MUST NOT collide with existing galaxies (mgmt 10.0/10.10, static 10.5/10.15)
- `cilium_cluster_id` MUST be unique across the fleet
- Do NOT modify `gxy_static_k3s.yml` or `gxy_mgmt_k3s.yml`

#### Agent Prompt

````
You are implementing Task 07: gxy_launchbase_k3s group_vars.

## Your Task

Create the per-galaxy config file per RFC §4.1.1.

### Step 1: Create the file
Write `ansible/inventory/group_vars/gxy_launchbase_k3s.yml` with exactly the content from RFC §4.1.1 (the fenced YAML block labelled `gxy-launchbase galaxy configuration`).

### Step 2: Validate YAML
```
yamllint -d "{extends: default, rules: {line-length: disable}}" ansible/inventory/group_vars/gxy_launchbase_k3s.yml
```

### Step 3: Diff against gxy_static as a sanity check
Only the following keys should differ:
- galaxy_name: gxy-launchbase
- cilium_cluster_id: 3
- cluster-cidr: 10.6.0.0/16
- service-cidr: 10.16.0.0/16
- etcd-s3-folder: etcd/gxy-launchbase

All other structure identical.

## Files

- Create: `ansible/inventory/group_vars/gxy_launchbase_k3s.yml`

## Acceptance Criteria

- File parses as valid YAML
- CIDRs 10.6.0.0/16 + 10.16.0.0/16 (no collision with mgmt or static)
- cilium_cluster_id=3 (unique)

## Context

This file is the only per-galaxy configuration needed for bootstrap — the existing `play-k3s--bootstrap.yml` playbook reads it. Actual node provisioning + bootstrap is an operator action outside this task.

## When Stuck

Copy `gxy_static_k3s.yml` as a starting point and change only the 5 keys listed. Do NOT invent new config options.

## Constraints

- Do NOT modify other group_vars files
- Do NOT touch playbooks
- Do NOT add Hetzner inventory or the `hetzner.hcloud` collection — that is Task 30 (post-M5)
- Do NOT run git write commands
````

**Depends on:** None (was Task 06; collapsed — DO dynamic inventory already exists)

---

### Task 08 [M]: gxy_cassiopeia_k3s group_vars

**Traceability:** Implements R2 | Constrained by §4.1.2, D12 (sizing)
**Files:**

- Create: `ansible/inventory/group_vars/gxy_cassiopeia_k3s.yml`

#### Context

Same shape as Task 07 but for gxy-cassiopeia. Different provider (DO FRA1), different CIDRs (10.7/10.17), different cilium_cluster_id=4.

#### Acceptance Criteria

- GIVEN the file WHEN parsed THEN no YAML errors
- GIVEN CIDRs WHEN inspected THEN `10.7.0.0/16` + `10.17.0.0/16` (no collision)
- GIVEN `cilium_cluster_id` THEN 4 (distinct from mgmt=1, static=2, launchbase=3)

#### Verification

```bash
yamllint -d "{extends: default, rules: {line-length: disable}}" ansible/inventory/group_vars/gxy_cassiopeia_k3s.yml
```

**Expected output:** no lint errors.

#### Constraints

- Same as Task 07

#### Agent Prompt

```
You are implementing Task 08: gxy_cassiopeia_k3s group_vars.

## Your Task

Create `ansible/inventory/group_vars/gxy_cassiopeia_k3s.yml` with content from RFC §4.1.2 lines 183-218.

### Step 1: Create the file
Copy the block from the RFC verbatim. Verify:
- galaxy_name: gxy-cassiopeia
- cilium_cluster_id: 4
- cluster-cidr: 10.7.0.0/16
- service-cidr: 10.17.0.0/16
- etcd-s3-folder: etcd/gxy-cassiopeia

### Step 2: yamllint

## Files

- Create: `ansible/inventory/group_vars/gxy_cassiopeia_k3s.yml`

## Acceptance Criteria

- Valid YAML
- CIDRs do not collide with existing galaxies
- cilium_cluster_id=4

## Context

Parallel to Task 07 but for the serving galaxy on DO FRA1.

## Constraints

- Do NOT modify other group_vars
- Do NOT run git write commands
```

**Depends on:** None (parallel to Task 07)

---

### Task 09 [M]: CNPG operator + Cluster CR for Woodpecker postgres

**Traceability:** Implements R3 (Woodpecker CI), D21 (CNPG at bootstrap) | Constrained by §4.2.2
**Files:**

- Create: `k3s/gxy-launchbase/apps/cnpg-operator/charts/cnpg-operator/repo` (Helm chart repo URL)
- Create: `k3s/gxy-launchbase/apps/cnpg-operator/values.yaml`
- Create: `k3s/gxy-launchbase/apps/woodpecker/manifests/postgres-cluster.yaml` (CNPG Cluster CR)
- Create: `k3s/gxy-launchbase/apps/woodpecker/secrets/postgres.secrets.env.enc` (REFERENCE — actual encrypted file lives in infra-secrets)

#### Context

Install CNPG operator cluster-wide (namespace `cnpg-system`) and create a `Cluster` CR in the `woodpecker` namespace for Woodpecker's PostgreSQL backend. 2 instances (primary + replica), synchronous_commit=remote_write, WAL archiving to DO Spaces.

#### Acceptance Criteria

- GIVEN the Helm values YAML WHEN `helm template` runs THEN no errors
- GIVEN the Cluster CR YAML WHEN `kubectl --dry-run=server apply -f` (against a running CNPG-operator cluster) THEN validates
- GIVEN the CR THEN: 2 instances; PostgreSQL 16; synchronous_commit=remote_write; WAL archive to S3 bucket net-freecodecamp-universe-backups/cnpg/gxy-launchbase/woodpecker; retention 14 days

#### Verification

```bash
helm template cnpg-operator cnpg/cloudnative-pg -f k3s/gxy-launchbase/apps/cnpg-operator/values.yaml --dry-run > /tmp/cnpg.yaml && \
  kubectl apply --dry-run=client -f /tmp/cnpg.yaml >/dev/null && \
  kubectl apply --dry-run=client -f k3s/gxy-launchbase/apps/woodpecker/manifests/postgres-cluster.yaml >/dev/null
```

**Expected output:** no errors on any of the three commands.

#### Constraints

- Pin CNPG operator chart version
- Cluster CR API version must match installed operator
- No WAL archive credentials hardcoded — reference a Secret (populated from sops overlay in infra-secrets)
- Do NOT apply to a real cluster in this task — dry-run only

#### Agent Prompt

````
You are implementing Task 09: CNPG operator + Cluster CR for Woodpecker postgres.

## Your Task

Per RFC §4.2.2 (D21), install CNPG operator and define the postgres Cluster CR for Woodpecker. Dry-run validation only — no real apply.

### Step 1: Create chart reference
Write `k3s/gxy-launchbase/apps/cnpg-operator/charts/cnpg-operator/repo` as a single-line file:
```
https://cloudnative-pg.github.io/charts
```
(Convention for this repo's Helm layout.)

### Step 2: Create values.yaml
Pin a recent stable version (look up latest via Artifact Hub, e.g., 0.22.x). Minimal values:
```yaml
replicaCount: 1
resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 50m
    memory: 128Mi
monitoring:
  podMonitorEnabled: false  # enable when gxy-backoffice exists
```

### Step 3: Create postgres-cluster.yaml
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: woodpecker-postgres
  namespace: woodpecker
spec:
  instances: 2
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  storage:
    storageClass: local-path
    size: 10Gi
  postgresql:
    parameters:
      synchronous_commit: "remote_write"
  minSyncReplicas: 1
  maxSyncReplicas: 1
  bootstrap:
    initdb:
      database: woodpecker
      owner: woodpecker
      secret:
        name: woodpecker-postgres-app
  backup:
    barmanObjectStore:
      destinationPath: s3://net-freecodecamp-universe-backups/cnpg/gxy-launchbase/woodpecker
      endpointURL: https://fra1.digitaloceanspaces.com
      s3Credentials:
        accessKeyId:
          name: woodpecker-postgres-backup-s3
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: woodpecker-postgres-backup-s3
          key: SECRET_ACCESS_KEY
      wal:
        retention: "14d"
      data:
        retention: "14d"
        immediateCheckpoint: true
    retentionPolicy: "14d"
```

### Step 4: Document secret reference
Create `k3s/gxy-launchbase/apps/woodpecker/secrets/README.md` noting:
- `woodpecker-postgres-backup-s3` Secret must be created from infra-secrets/gxy-launchbase/woodpecker-postgres-backup-s3.env.enc
- Required keys: ACCESS_KEY_ID, SECRET_ACCESS_KEY (DO Spaces)

### Step 5: Dry-run validation
```
helm template cnpg-operator cnpg/cloudnative-pg -f k3s/gxy-launchbase/apps/cnpg-operator/values.yaml --dry-run > /tmp/cnpg.yaml
kubectl apply --dry-run=client -f /tmp/cnpg.yaml >/dev/null
kubectl apply --dry-run=client -f k3s/gxy-launchbase/apps/woodpecker/manifests/postgres-cluster.yaml >/dev/null
```

## Files

- Create: `k3s/gxy-launchbase/apps/cnpg-operator/charts/cnpg-operator/repo`
- Create: `k3s/gxy-launchbase/apps/cnpg-operator/values.yaml`
- Create: `k3s/gxy-launchbase/apps/woodpecker/manifests/postgres-cluster.yaml`
- Create: `k3s/gxy-launchbase/apps/woodpecker/secrets/README.md`

## Acceptance Criteria

Three dry-run commands above all exit 0.

## Context

Woodpecker requires a PostgreSQL backend. D21 (this RFC) replaces the originally-planned SQLite-on-PVC with CNPG for HA and restore-from-backup guarantees.

## When Stuck

CNPG docs (https://cloudnative-pg.io/documentation) have concrete Cluster CR examples. If `local-path` storage class is unavailable in the target cluster, check `kubectl get storageclass` — but the dry-run validation here uses `--dry-run=client`, which does not check storage class existence.

## Constraints

- Do NOT apply to any real cluster
- No plaintext credentials — reference sops-managed Secret
- Do NOT touch other apps directories
- Do NOT run git write commands
````

**Depends on:** Task 07

---

### Task 10 [L]: Woodpecker Helm chart + values + DNS + CF Access

**Traceability:** Implements R3 | Constrained by §4.2.1-4.2.6
**Files:**

- Create: `k3s/gxy-launchbase/apps/woodpecker/charts/woodpecker/repo`
- Create: `k3s/gxy-launchbase/apps/woodpecker/values.yaml`
- Create: `k3s/gxy-launchbase/apps/woodpecker/manifests/httproute.yaml`
- Create: `k3s/gxy-launchbase/apps/woodpecker/manifests/cilium-netpol.yaml`
- Create: `docs/runbooks/woodpecker-oauth-app.md` (ClickOps runbook for GitHub OAuth app creation)
- Create: `docs/runbooks/woodpecker-cf-access.md` (ClickOps runbook for Cloudflare Access setup)

#### Context

Deploy Woodpecker v3.13.0 Helm chart. Kubernetes backend, DaemonSet agents, `WOODPECKER_MAX_WORKFLOWS=2`, GitHub OAuth forge. DNS at `woodpecker.freecodecamp.net`. Cloudflare Access with email OTP restricted to platform-team group is a **Phase 2 exit criterion** per RFC §4.2.3 CRITICAL #1 resolution.

The GitHub OAuth app creation and CF Access setup are ClickOps (operator tasks); this task creates the runbooks for those actions and the Helm/manifest scaffolding that consumes their outputs.

#### Acceptance Criteria

- GIVEN values.yaml WHEN `helm template woodpecker woodpeckerci/woodpecker -f values.yaml --dry-run` runs THEN no errors
- GIVEN the chart config THEN WOODPECKER_MAX_WORKFLOWS=2, WOODPECKER_BACKEND=kubernetes, forge=github
- GIVEN the HTTPRoute YAML THEN `kubectl apply --dry-run=client -f ...` validates
- GIVEN the CiliumNetworkPolicy THEN egress limited to api.github.com:443, \*.r2.cloudflarestorage.com:443, api.cloudflare.com:443, DNS
- GIVEN oauth-app runbook THEN documents all fields needed (Homepage URL, Callback URL, permission scopes)
- GIVEN cf-access runbook THEN includes steps for platform-team group restriction + email OTP

#### Verification

```bash
helm template woodpecker woodpeckerci/woodpecker -f k3s/gxy-launchbase/apps/woodpecker/values.yaml --dry-run > /tmp/wp.yaml && \
  kubectl apply --dry-run=client -f /tmp/wp.yaml >/dev/null && \
  kubectl apply --dry-run=client -f k3s/gxy-launchbase/apps/woodpecker/manifests/httproute.yaml >/dev/null && \
  kubectl apply --dry-run=client -f k3s/gxy-launchbase/apps/woodpecker/manifests/cilium-netpol.yaml >/dev/null
```

**Expected output:** all four commands exit 0.

#### Constraints

- Pin Woodpecker chart version (v3.13.x)
- Do NOT commit OAuth app secrets; reference sops overlay
- Do NOT apply to a real cluster in this task
- CF Access setup is ClickOps — runbook only

#### Agent Prompt

````
You are implementing Task 10: Woodpecker Helm chart + values + DNS + CF Access.

## Repo and CWD

Work in the infra repo: `/Users/mrugesh/DEV/fCC/infra`. All paths below are relative to that.

## Your Task

Per RFC §4.2.1-4.2.6, deploy Woodpecker v3.13.0 with Kubernetes backend, DaemonSet agents, GitHub OAuth forge. DNS at `woodpecker.freecodecamp.net`. Cloudflare Access email-OTP on the platform-team group is a Phase 2 exit criterion (promoted from deferred per CRITICAL #1 resolution).

Read the RFC from `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md` §4.2 before writing to understand the full context.

The chart layout mirrors `k3s/gxy-management/apps/argocd/` — read that as a reference for the conventions this repo uses (Chart.yaml, values.yaml, a `charts/<chart-name>/repo` one-line file with the Helm repo URL, optional `manifests/` dir for supplementary YAML).

### Step 1: Chart repo file
Create `k3s/gxy-launchbase/apps/woodpecker/charts/woodpecker/repo`:
```
https://woodpecker-ci.github.io/helm
```

### Step 2: values.yaml
Create `k3s/gxy-launchbase/apps/woodpecker/values.yaml` using the official Woodpecker chart schema (pin to `3.13.x`; look up latest patch via https://github.com/woodpecker-ci/helm/releases). Key values:

```yaml
# Pin to v3.13 stable per RFC §4.2.1
server:
  image:
    tag: v3.13.0
  replicaCount: 2
  env:
    WOODPECKER_BACKEND: kubernetes
    WOODPECKER_HOST: https://woodpecker.freecodecamp.net
    WOODPECKER_FORGE: github
    WOODPECKER_GITHUB: "true"
    WOODPECKER_ADMIN: "<comma-separated platform-team GH usernames>"
    WOODPECKER_OPEN: "false"  # org-gated via GitHub OAuth
    WOODPECKER_DATABASE_DRIVER: postgres
    WOODPECKER_DATABASE_DATASOURCE_FROM_SECRET:
      secretKeyRef:
        name: woodpecker-postgres-app
        key: uri
  envFrom:
    - secretRef:
        name: woodpecker-github-oauth
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

agent:
  enabled: true
  kind: DaemonSet
  env:
    WOODPECKER_MAX_WORKFLOWS: "2"
    WOODPECKER_BACKEND: kubernetes
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 2000m
      memory: 4Gi

service:
  type: ClusterIP
  port: 80
```

### Step 3: Create httproute.yaml
`k3s/gxy-launchbase/apps/woodpecker/manifests/httproute.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: woodpecker
  namespace: woodpecker
spec:
  parentRefs:
    - name: traefik
      namespace: kube-system
  hostnames:
    - woodpecker.freecodecamp.net
  rules:
    - backendRefs:
        - name: woodpecker-server
          port: 80
```

### Step 4: Create cilium-netpol.yaml
`k3s/gxy-launchbase/apps/woodpecker/manifests/cilium-netpol.yaml`:

Two policies. One for server egress (GitHub + CF + DNS + postgres internal), one for agents (broader — per-step container pulls).

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: woodpecker-server-egress
  namespace: woodpecker
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: woodpecker
      app.kubernetes.io/component: server
  egress:
    - toFQDNs:
        - matchPattern: "api.github.com"
        - matchPattern: "*.r2.cloudflarestorage.com"
        - matchPattern: "api.cloudflare.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
    # Postgres reachable in same namespace
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: woodpecker
            cnpg.io/cluster: woodpecker-postgres
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: woodpecker-agent-egress
  namespace: woodpecker
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: woodpecker
      app.kubernetes.io/component: agent
  egress:
    # Agents need to pull container images and reach the woodpecker server's grpc endpoint
    - toFQDNs:
        - matchPattern: "*"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

(Agent wildcard egress is intentional — pipelines pull arbitrary images. Tightening is a later hardening step.)

### Step 5: Create docs/runbooks/woodpecker-oauth-app.md
Content:

```markdown
# Woodpecker GitHub OAuth App Creation

Creates the OAuth app used by Woodpecker for GitHub login and webhook integration.

## Prerequisites
- GitHub org admin on `freeCodeCamp-Universe`
- Platform team email accessible

## Steps
1. Navigate to https://github.com/organizations/freeCodeCamp-Universe/settings/applications
2. Click "New OAuth App"
3. Fill fields:
   - Application name: `Woodpecker CI (gxy-launchbase)`
   - Homepage URL: `https://woodpecker.freecodecamp.net`
   - Authorization callback URL: `https://woodpecker.freecodecamp.net/authorize`
4. Generate a client secret
5. Store both as sops-encrypted file at `~/DEV/fCC/infra-secrets/gxy-launchbase/woodpecker-github-oauth.env.enc`:
   ```
   WOODPECKER_GITHUB_CLIENT=<client id>
   WOODPECKER_GITHUB_SECRET=<client secret>
   ```
6. Decrypt and apply as Secret `woodpecker-github-oauth` in the `woodpecker` namespace:
   ```bash
   sops -d ~/DEV/fCC/infra-secrets/gxy-launchbase/woodpecker-github-oauth.env.enc | \
     kubectl create secret generic woodpecker-github-oauth --from-env-file=/dev/stdin -n woodpecker
   ```

## Blast radius
The OAuth app's `repo` scope grants r/w on every repo in the `freeCodeCamp-Universe` org to users authenticated through Woodpecker. This is the rationale for CF Access on woodpecker.freecodecamp.net (see `woodpecker-cf-access.md`) and the eventual migration to a GitHub App (RFC D28).
```

### Step 6: Create docs/runbooks/woodpecker-cf-access.md
Content:

```markdown
# Cloudflare Access on woodpecker.freecodecamp.net

Restrict the Woodpecker UI to the platform-team group via CF Access email OTP.

## Prerequisites
- Cloudflare Zero Trust enabled on the account
- Platform-team Access group configured with the correct email addresses

## Steps
1. CF Zero Trust → Access → Applications → Add self-hosted application
2. Application domain: `woodpecker.freecodecamp.net`
3. Session duration: 24h
4. Authentication: Email OTP (one-time PIN)
5. Policy: Allow — Include — Emails in group "platform-team"
6. Save

## Exit criterion (Phase 2)
Test by visiting https://woodpecker.freecodecamp.net in an incognito browser — expect Access email OTP prompt, not immediate Woodpecker UI.
```

### Step 7: Dry-run validation
```bash
cd /Users/mrugesh/DEV/fCC/infra
helm template woodpecker woodpeckerci/woodpecker -f k3s/gxy-launchbase/apps/woodpecker/values.yaml > /tmp/wp.yaml
kubectl apply --dry-run=client -f /tmp/wp.yaml >/dev/null
kubectl apply --dry-run=client -f k3s/gxy-launchbase/apps/woodpecker/manifests/httproute.yaml >/dev/null
kubectl apply --dry-run=client -f k3s/gxy-launchbase/apps/woodpecker/manifests/cilium-netpol.yaml >/dev/null
```
All four commands must exit 0.

## Files

- Create: `k3s/gxy-launchbase/apps/woodpecker/charts/woodpecker/repo`
- Create: `k3s/gxy-launchbase/apps/woodpecker/values.yaml`
- Create: `k3s/gxy-launchbase/apps/woodpecker/manifests/httproute.yaml`
- Create: `k3s/gxy-launchbase/apps/woodpecker/manifests/cilium-netpol.yaml`
- Create: `docs/runbooks/woodpecker-oauth-app.md`
- Create: `docs/runbooks/woodpecker-cf-access.md`

## Acceptance Criteria

Four dry-run commands in Step 7 exit 0. Runbooks document OAuth app + CF Access setup with concrete steps.

## Context

This is the CI brain for the whole static-deploy pipeline. Its OAuth scope is known-broad (`repo` org-wide — RFC §4.2.3 CRITICAL #1), which is why CF Access gating is mandatory at Phase 2 exit, not deferred.

## When Stuck

If the Woodpecker chart's env schema has changed, check https://github.com/woodpecker-ci/helm/blob/main/charts/woodpecker/values.yaml for the current shape. If the `WOODPECKER_DATABASE_DATASOURCE_FROM_SECRET` key is not supported, fall back to constructing the URI in a kustomization-style ConfigMap — but verify before deviating.

## Constraints

- TDD discipline is not strictly applicable here (YAML manifests, not code) — but dry-run validation is the equivalent check
- Pin Woodpecker chart to 3.13.x; never use `~` or `>=`
- Do NOT commit OAuth secrets to git
- Do NOT apply to any real cluster in this task
- Do NOT modify `k3s/gxy-management/apps/*` or other galaxies
- Do NOT run git write commands
````

**Depends on:** Task 09

---

### Task 11 [M]: Per-site R2 secret provisioning Windmill flow

**Traceability:** Implements R3, D22 (per-repo R2 secrets) | Constrained by §4.2.4
**Files:**

- Create: `f/static/provision_site_r2_credentials.ts` (in windmill repo `~/DEV/fCC-U/windmill`)
- Create: `f/static/provision_site_r2_credentials.yaml` (flow metadata)
- Create: `f/static/provision_site_r2_credentials.test.ts`
- Modify: `~/DEV/fCC/infra/justfile` (add `constellation-register <site>` recipe)

#### Context

A Windmill flow that mints a new R2 Access Token with path condition `gxy-cassiopeia-1/{site}/*`, stores it in sops-encrypted form, and adds it as a Woodpecker **repo-scoped** (not org-scoped) secret per D22 / RFC §4.2.4.

This closes the CRITICAL #2 supply-chain finding. The flow is the canonical path for registering a new constellation — ensures every site has its own bounded-blast-radius credential.

#### Acceptance Criteria

- GIVEN the flow input `{site: "hello-world"}` WHEN the flow executes against a mock CF API THEN a new R2 token is created with path condition `gxy-cassiopeia-1/hello-world.freecode.camp/*`
- GIVEN the flow THEN the credentials are passed to a sops encryption step (actual file write is out of scope for the flow itself; flow returns encrypted blob)
- GIVEN the flow THEN Woodpecker repo secrets `r2_access_key_id` + `r2_secret_access_key` are added to `freeCodeCamp-Universe/<site>` via Woodpecker API
- GIVEN tests run THEN all assertions pass (mock CF API and Woodpecker API)

#### Verification

```bash
cd /Users/mrugesh/DEV/fCC-U/windmill && deno test f/static/provision_site_r2_credentials.test.ts
```

**Expected output:** tests pass.

#### Constraints

- Flow language: TypeScript (Deno, matches existing windmill repo convention)
- Must use Woodpecker API for repo secret write (not org secret)
- Do NOT hardcode CF account ID — read from Windmill variable
- Do NOT touch existing `f/app/`, `f/google_chat/`, `f/github/`, `f/repo_mgmt/`, `f/ops/`

#### Agent Prompt

````
You are implementing Task 11: Per-site R2 secret provisioning Windmill flow.

## Repo and CWD

Work in the Windmill repo: `/Users/mrugesh/DEV/fCC-U/windmill`. NOT the infra repo. All paths below are relative to the windmill repo root.

## Your Task

Per RFC §4.2.4 (D22), implement a TypeScript Windmill flow that mints a new R2 Access Token with a path condition restricting writes to `gxy-cassiopeia-1/{site}/*`, then registers the credentials as a **repo-scoped** Woodpecker secret (NOT org-scoped — this is the entire point: bound blast radius of a compromised build dep).

Read the RFC at `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md` §4.2.4 and §5.20 (D22 rejection rationale for org-scope) before starting.

### Step 1: Read existing Windmill conventions
- Read `f/github/create_repo.ts` to understand: Windmill Resource pattern, error handling, logging.
- Read `__mocks__/windmill-client.ts` to understand test patterns.
- Read `deno.lock` for the Windmill client version in use.

### Step 2: Write failing tests (TDD)
Create `f/static/provision_site_r2_credentials.test.ts`:

```typescript
import { assertEquals, assertRejects } from "https://deno.land/std/assert/mod.ts";
import { provisionSiteR2Credentials } from "./provision_site_r2_credentials.ts";

// Mock CF API + Woodpecker API via dependency injection
Deno.test("mints R2 token with correct path condition", async () => {
  const calls: Array<{url: string; body: unknown}> = [];
  const fetchMock = async (url: string, init: RequestInit) => {
    calls.push({url, body: JSON.parse(init.body as string)});
    if (url.includes("cloudflare.com")) {
      return new Response(JSON.stringify({result: {id: "t1", value: "secret1"}}), {status: 200});
    }
    return new Response(JSON.stringify({ok: true}), {status: 200});
  };
  await provisionSiteR2Credentials({site: "hello-world", cf_account_id: "acct1", bucket: "gxy-cassiopeia-1", fetchFn: fetchMock});
  const cfCall = calls.find(c => c.url.includes("cloudflare.com"));
  assertEquals((cfCall!.body as any).permissions[0].allowed_paths[0], "gxy-cassiopeia-1/hello-world.freecode.camp/*");
});

Deno.test("adds secrets to Woodpecker as repo-scope, not org-scope", async () => {
  // Assert the Woodpecker API endpoint called ends with /repos/.../secrets not /orgs/.../secrets
});

Deno.test("rejects sites with -- in name", async () => {
  await assertRejects(
    () => provisionSiteR2Credentials({site: "hello--world", /*...*/}),
    Error,
    "site name must not contain",
  );
});

Deno.test("rotates existing tokens (idempotent)", async () => {
  // If a token with the same name already exists, revoke and re-create
});
```

Run `deno test f/static/provision_site_r2_credentials.test.ts` — tests should FAIL (flow not written yet).

### Step 3: Implement the flow
`f/static/provision_site_r2_credentials.ts`:

```typescript
// Windmill flow: mint R2 token with path condition, store in sops, register as Woodpecker repo secret.
// Ref: RFC gxy-cassiopeia §4.2.4 (D22)

import * as wmill from "https://deno.land/x/windmill@v1.xxx/mod.ts";

export interface ProvisionInput {
  site: string;              // bare name, e.g. "hello-world"
  cf_account_id: string;     // Cloudflare account ID
  bucket: string;            // R2 bucket name, e.g. "gxy-cassiopeia-1"
  woodpecker_repo: string;   // e.g. "freeCodeCamp-Universe/hello-world"
  fetchFn?: typeof fetch;    // for testing
}

const SITE_REGEX = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/;

export async function provisionSiteR2Credentials(input: ProvisionInput): Promise<void> {
  const {site, cf_account_id, bucket, woodpecker_repo, fetchFn = fetch} = input;

  // Validate site name
  if (!SITE_REGEX.test(site) || site.includes("--")) {
    throw new Error(`site name must not contain '--' and must match ${SITE_REGEX}: ${site}`);
  }

  const siteHost = `${site}.freecode.camp`;
  const tokenName = `r2-${site}-deploy`;

  // Get CF API token from Windmill variable (set up once globally)
  const cfApiToken = await wmill.getVariable("u/admin/cf_api_token");

  // Mint R2 Access Token with path condition — CF API
  const cfUrl = `https://api.cloudflare.com/client/v4/accounts/${cf_account_id}/tokens`;
  const tokenResp = await fetchFn(cfUrl, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${cfApiToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      name: tokenName,
      policies: [{
        effect: "allow",
        resources: {[`com.cloudflare.edge.r2.bucket.${cf_account_id}_default_${bucket}`]: "*"},
        permission_groups: [
          {id: "<R2 Object Read & Write permission group ID>"},
        ],
      }],
      allowed_paths: [`${bucket}/${siteHost}/*`],
    }),
  });
  if (!tokenResp.ok) {
    throw new Error(`CF token mint failed: ${tokenResp.status} ${await tokenResp.text()}`);
  }
  const tokenData = await tokenResp.json() as {result: {id: string; value: string}};

  // Register as Woodpecker REPO-SCOPED secret (not org-scoped)
  const wpBase = await wmill.getVariable("u/admin/woodpecker_endpoint");
  const wpAdminToken = await wmill.getVariable("u/admin/woodpecker_admin_token");
  const [owner, name] = woodpecker_repo.split("/");

  // Look up repo_id
  const repoResp = await fetchFn(`${wpBase}/api/repos/lookup/${owner}/${name}`, {
    headers: {"Authorization": `Bearer ${wpAdminToken}`},
  });
  if (!repoResp.ok) {
    throw new Error(`Woodpecker repo lookup failed: ${repoResp.status}`);
  }
  const {id: repoId} = await repoResp.json() as {id: number};

  // Add/update both secrets (idempotent via delete-then-create)
  for (const [secretName, secretValue] of [
    ["r2_access_key_id", tokenData.result.id],
    ["r2_secret_access_key", tokenData.result.value],
  ]) {
    // Try delete first (ignore 404)
    await fetchFn(`${wpBase}/api/repos/${repoId}/secrets/${secretName}`, {
      method: "DELETE",
      headers: {"Authorization": `Bearer ${wpAdminToken}`},
    });
    // Create
    const createResp = await fetchFn(`${wpBase}/api/repos/${repoId}/secrets`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${wpAdminToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        name: secretName,
        value: secretValue,
        events: ["push", "manual", "deployment"],
        // NOT available for pull_request
      }),
    });
    if (!createResp.ok) {
      throw new Error(`Woodpecker secret add failed: ${createResp.status}`);
    }
  }
}
```

Note: the CF permission group ID for "R2 Object Read & Write" is a stable UUID — look it up via the CF API docs (`https://api.cloudflare.com/client/v4/user/tokens/permission_groups`) and hardcode with a comment explaining the source.

### Step 4: Flow metadata YAML
Create `f/static/provision_site_r2_credentials.yaml`:

```yaml
summary: Provision per-site R2 credentials (repo-scoped Woodpecker secret)
description: |
  Mints a Cloudflare R2 Access Token with path condition limiting writes to
  {bucket}/{site}.freecode.camp/*, then registers the credentials as
  repo-scoped Woodpecker secrets on the target constellation repo.
  Ref: RFC gxy-cassiopeia §4.2.4 (D22).
schema:
  type: object
  required: [site, cf_account_id, bucket, woodpecker_repo]
  properties:
    site: {type: string}
    cf_account_id: {type: string}
    bucket: {type: string}
    woodpecker_repo: {type: string}
```

### Step 5: Add justfile recipe in infra repo
Run this step from the **infra** repo (NOT windmill):

`/Users/mrugesh/DEV/fCC/infra/justfile` — append under a new `[group('static')]`:

```just
[group('static')]
constellation-register site:
    #!/usr/bin/env bash
    set -euo pipefail
    wmill job run -f f/static/provision_site_r2_credentials \
        -- \
        site={{site}} \
        cf_account_id=$CF_ACCOUNT_ID \
        bucket=gxy-cassiopeia-1 \
        woodpecker_repo=freeCodeCamp-Universe/{{site}}
```

### Step 6: Run tests
```bash
cd /Users/mrugesh/DEV/fCC-U/windmill
deno test f/static/provision_site_r2_credentials.test.ts
```
All tests pass.

## Files

- Create (windmill repo): `f/static/provision_site_r2_credentials.ts`
- Create (windmill repo): `f/static/provision_site_r2_credentials.yaml`
- Create (windmill repo): `f/static/provision_site_r2_credentials.test.ts`
- Modify (infra repo): `justfile` (add `constellation-register <site>` recipe)

## Acceptance Criteria

- Tests pass: `deno test f/static/provision_site_r2_credentials.test.ts`
- Flow rejects invalid site names with `--`
- Woodpecker API call path is `/api/repos/{id}/secrets` (repo-scope), NOT `/api/orgs/.../secrets`
- CF R2 token body includes `allowed_paths: ["gxy-cassiopeia-1/<site>.freecode.camp/*"]`
- Idempotent: re-running for the same site replaces the credentials cleanly

## Context

Closes CRITICAL #2 (supply-chain via org-scope secrets) by ensuring each constellation gets its own bounded-blast-radius R2 credential. A compromised build dep in constellation A cannot overwrite constellation B.

## When Stuck

If the CF Access Token API schema differs from the code above, check CF docs at https://developers.cloudflare.com/api/operations/account-api-tokens-create-token — the permission group IDs are the part most likely to vary over time. If `woodpecker-cli` has a better UX for secret management than raw API calls, you can substitute — but the idempotent repo-scoped semantic must be preserved.

## Constraints

- TDD: tests first, verify fail, implement, verify pass
- Must follow Windmill TypeScript conventions in `f/github/create_repo.ts`
- Repo-scoped secrets ONLY — org-scope is forbidden
- Do NOT touch existing `f/app/`, `f/google_chat/`, `f/github/`, `f/repo_mgmt/`, `f/ops/` files
- Do NOT commit any CF API token or Woodpecker admin token to git
- Do NOT run git write commands
````

**Depends on:** Task 10

---

### Task 12 [M]: R2 bucket gxy-cassiopeia-1 — ClickOps runbook + preflight

**Traceability:** Implements R5 | Constrained by §4.4.1 (versioning enabled)
**Files:**

- Create: `docs/runbooks/r2-bucket-provision.md`
- Create: `scripts/r2-bucket-verify.sh`
- Modify: `justfile` (add `r2-bucket-verify` recipe)

#### Context

Provisioning the R2 bucket is ClickOps (CF dashboard for now; OpenTofu import later per ADR-002). This task creates the runbook + a verification script that checks the bucket's state (versioning enabled, access keys exist, path conditions correct).

#### Acceptance Criteria

- GIVEN the runbook THEN covers: bucket creation, versioning toggle, rw+ro access key creation, sops-encrypting credentials into infra-secrets
- GIVEN the verify script WHEN run with CF creds THEN confirms bucket exists, versioning enabled, returns exit 0 on success
- GIVEN `just r2-bucket-verify` WHEN run THEN calls the verify script with config from env

#### Verification

```bash
shellcheck scripts/r2-bucket-verify.sh && just --unstable --fmt --check
```

**Expected output:** shellcheck passes; justfile is well-formed.

#### Constraints

- No CF API tokens in scripts — read from env populated by direnv
- Script is idempotent (running twice produces the same result)
- Do NOT actually provision a bucket in this task — runbook only

#### Agent Prompt

````
You are implementing Task 12: R2 bucket gxy-cassiopeia-1 — runbook + verification script.

## Repo and CWD

Work in the infra repo: `/Users/mrugesh/DEV/fCC/infra`.

## Your Task

Document the ClickOps bucket provisioning steps + a verification script. Actual bucket creation is an operator action; this task creates the tooling.

### Step 1: docs/runbooks/r2-bucket-provision.md

```markdown
# R2 Bucket Provision: gxy-cassiopeia-1

Phase 4 prerequisite per RFC §4.4.1. ClickOps for v1; OpenTofu import later.

## Prerequisites
- Cloudflare account admin on the freeCodeCamp-Universe account
- `infra-secrets` repo cloned at `~/DEV/fCC/infra-secrets`; sops key loaded

## Steps

1. **Create the bucket**
   - Cloudflare Dashboard → R2 Object Storage → Create bucket
   - Name: `gxy-cassiopeia-1`
   - Location: Europe (or Automatic)
   - Storage class: Standard

2. **Enable object versioning**
   - Click into the bucket → Settings
   - Object versioning: Enable
   - Retention: 30 days (R2 default)

3. **Create ro access key (Caddy)**
   - Account Home → R2 → Manage R2 API Tokens
   - Create Token
   - Name: `gxy-cassiopeia-caddy-ro`
   - Permissions: R2 Object Read
   - Specify bucket: gxy-cassiopeia-1
   - TTL: none (no expiration; rotated every 90 days via runbook)
   - Copy the Access Key ID and Secret Access Key

4. **Store ro credentials**

   Create `~/DEV/fCC/infra-secrets/gxy-cassiopeia/caddy-r2.env.enc`:
   ```
   AWS_ACCESS_KEY_ID=<access key from step 3>
   AWS_SECRET_ACCESS_KEY=<secret from step 3>
   R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
   R2_BUCKET=gxy-cassiopeia-1
   ```

   Encrypt with sops:
   ```bash
   sops -e -i ~/DEV/fCC/infra-secrets/gxy-cassiopeia/caddy-r2.env.enc
   ```

5. **Create rw admin key (operational use)**
   - Same as step 3 but: name `gxy-cassiopeia-ops-rw`, permissions R2 Object Read & Write, no TTL
   - Store at `~/DEV/fCC/infra-secrets/gxy-cassiopeia/ops-rw.env.enc` (sops-encrypted)
   - This key is used by infra team for ad-hoc operations (phase4-smoke, cutover-preflight). Do NOT use for per-site deploys — those get their own path-restricted tokens via `just constellation-register` (Task 11).

6. **Verify**
   ```bash
   cd ~/DEV/fCC/infra/k3s/gxy-cassiopeia
   direnv allow
   just r2-bucket-verify
   ```

## Rotation (every 90 days)

- Generate a new token in CF R2 UI with the same permissions
- Update the sops-encrypted file
- Apply to Caddy: `just helm-upgrade caddy` (pod restart picks up new Secret)
- Apply to Woodpecker per-site secrets: regenerate via `just constellation-register <site>` for each constellation
- Revoke the old token in CF UI after confirming zero usage
```

### Step 2: scripts/r2-bucket-verify.sh

```bash
#!/usr/bin/env bash
# Verify gxy-cassiopeia-1 bucket is provisioned and accessible.
# Reads credentials from env (populated by direnv from infra-secrets).
set -euo pipefail

: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID not set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY not set}"
: "${R2_ENDPOINT:?R2_ENDPOINT not set}"
: "${R2_BUCKET:=gxy-cassiopeia-1}"

# Configure rclone in memory
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export RCLONE_CONFIG="$TMP_DIR/rclone.conf"
rclone config create r2 s3 \
  provider=Cloudflare \
  endpoint="$R2_ENDPOINT" \
  access_key_id="$AWS_ACCESS_KEY_ID" \
  secret_access_key="$AWS_SECRET_ACCESS_KEY" >/dev/null

echo "[1/3] List bucket"
rclone lsd "r2:${R2_BUCKET}" >/dev/null
echo "  OK"

echo "[2/3] Write test object"
TEST_KEY="_verify/$(date -u +%Y%m%d-%H%M%S).txt"
echo "verify" | rclone rcat "r2:${R2_BUCKET}/${TEST_KEY}"
echo "  OK: wrote ${TEST_KEY}"

echo "[3/3] Read back and clean up"
CONTENT=$(rclone cat "r2:${R2_BUCKET}/${TEST_KEY}")
[ "$CONTENT" = "verify" ] || { echo "FAIL: read mismatch"; exit 2; }
rclone delete "r2:${R2_BUCKET}/${TEST_KEY}"
echo "  OK"

echo ""
echo "bucket ${R2_BUCKET} OK"
```

### Step 3: justfile
Append:

```just
[group('cassiopeia')]
r2-bucket-verify:
    bash scripts/r2-bucket-verify.sh
```

### Step 4: Lint
```bash
shellcheck scripts/r2-bucket-verify.sh
markdownlint docs/runbooks/r2-bucket-provision.md 2>&1 || echo "markdownlint not installed; manual review"
just --unstable --fmt --check
```

## Files

- Create: `docs/runbooks/r2-bucket-provision.md`
- Create: `scripts/r2-bucket-verify.sh`
- Modify: `justfile`

## Acceptance Criteria

- shellcheck clean
- Script is idempotent (test object is written with a unique timestamp path each run)
- Runbook covers create, versioning, ro key, rw key, rotation
- `just r2-bucket-verify` wires up cleanly

## Context

The bucket is the primary state store for gxy-cassiopeia. Versioning enables undo of a bad cleanup cron or a malicious overwrite. The rw key is operator-only; per-site rw tokens (Task 11) are used by pipelines.

## When Stuck

If CF R2's UI layout changes, the concept (bucket → token → permission + path → encrypted storage) stays stable. Adjust step wording but keep the flow.

## Constraints

- No API tokens in committed files
- Script MUST be idempotent
- Do NOT actually create a bucket in this task
- Do NOT run git write commands
````

**Depends on:** None

---

### Task 13 [L]: Caddy Helm chart — templates (deployment, configmap, secret, service, httproute, networkpolicy)

**Traceability:** Implements R6, R8, R9 | Constrained by §4.5.3-4.5.8, D23 (admin binding), D29 (origin IP allow-list)
**Files:**

- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/Chart.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/values.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/deployment.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/configmap.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/secret.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/service.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/httproute.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/networkpolicy.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/values.production.yaml`

#### Context

Full Caddy Helm chart per RFC §4.5. This is the complete serving deployment for gxy-cassiopeia. Uses the xcaddy image built in Task 05. Caddyfile includes the `r2_alias` directive (Tasks 01-04). Admin API binds to `127.0.0.1:2019` (D23, CRITICAL #3 resolution). NetworkPolicy does not allow :2019 ingress.

#### Acceptance Criteria

- GIVEN the chart WHEN `helm lint` runs THEN no errors
- GIVEN values.production.yaml THEN `helm template` renders all templates without errors
- GIVEN the rendered Deployment THEN NO container port 2019; admin only on 127.0.0.1:2019 (from Caddyfile)
- GIVEN the rendered Caddyfile THEN `admin 127.0.0.1:2019` AND `r2_alias { ... cache_max_entries 10000 ... }` present
- GIVEN the NetworkPolicy THEN egress only to \*.r2.cloudflarestorage.com:443 + DNS; ingress only port 80
- GIVEN HTTPRoute THEN hostnames `*.freecode.camp` bound to Traefik parent

#### Verification

```bash
cd k3s/gxy-cassiopeia/apps/caddy && \
  helm lint charts/caddy -f values.production.yaml && \
  helm template caddy charts/caddy -f values.production.yaml | kubectl apply --dry-run=client -f -
```

**Expected output:** both commands exit 0.

#### Constraints

- Caddy image tag value is a placeholder (`dev-<sha>` initially); updated by image-tag bump PRs after Task 05 builds
- Do NOT include rclone sidecars, init containers, or site-data volume (R2-direct, no local disk — D3)
- admin port 2019 MUST bind to 127.0.0.1, NOT :2019
- NetworkPolicy ingress MUST NOT allow port 2019
- Do NOT touch `k3s/gxy-static/apps/caddy/` (that stays as-is per D20)

#### Agent Prompt

````
You are implementing Task 13: Caddy Helm chart for gxy-cassiopeia.

## Repo and CWD

Work in the infra repo: `/Users/mrugesh/DEV/fCC/infra`.

## Your Task

Full Caddy Helm chart per RFC §4.5. This is the serving deployment. Uses the xcaddy image produced by Task 05 (`ghcr.io/freecodecamp-universe/caddy-s3:<tag>`). Caddyfile wires the `r2_alias` directive (Tasks 01-04). Admin API binds to `127.0.0.1:2019` (D23 — CRITICAL #3 fix). NetworkPolicy does NOT allow :2019 ingress.

Read `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md` §4.5.1-4.5.8 (lines 611-900) before writing — the template content is specified verbatim there.

### Step 1: Chart skeleton
Create `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/Chart.yaml`:

```yaml
apiVersion: v2
name: caddy
version: 0.1.0
appVersion: "2.8.4"
description: Caddy with r2_alias module for Universe static constellations
type: application
```

### Step 2: values.yaml
Create `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/values.yaml` with chart defaults (the production overlay will override the image tag). Fields: `replicaCount`, `image`, `resources`, `r2` (bucket, endpoint — access key values are in the production overlay sops file).

### Step 3: templates/
Create each of the following template files, using the YAML content from the RFC line ranges specified:
- `templates/deployment.yaml` — RFC §4.5.3 lines 636-712. **Important:** the updated version has NO `admin` container port (D23); confirm by reading the RFC section directly.
- `templates/configmap.yaml` — RFC §4.5.4 lines 717-785. **Important:** Caddyfile line `admin 127.0.0.1:2019` (not `:2019`); confirm against RFC.
- `templates/secret.yaml` — RFC §4.5.5 lines 786-802.
- `templates/service.yaml` — RFC §4.5.6 lines 803-837.
- `templates/httproute.yaml` — RFC §4.5.6 lines 824-837 (the second half of §4.5.6).
- `templates/networkpolicy.yaml` — RFC §4.5.8 lines 862-890. **Important:** ingress MUST NOT include port 2019 allow; confirm against RFC. Include the D29 origin-restriction paragraph awareness (the stricter IP allow-list is in Task 14's manifest, but this NetworkPolicy still applies).

### Step 4: Production overlay
Create `k3s/gxy-cassiopeia/apps/caddy/values.production.yaml` — RFC §4.5.7 lines 838-861:

```yaml
replicaCount: 3

image:
  repository: ghcr.io/freecodecamp-universe/caddy-s3
  tag: "REPLACE_WITH_ACTUAL_TAG"  # bumped by an image-tag PR after Task 05 builds
  pullPolicy: IfNotPresent

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 1000m
    memory: 512Mi

r2:
  bucket: gxy-cassiopeia-1
  endpoint: "https://<cf-account>.r2.cloudflarestorage.com"
  # accessKeyId and secretAccessKey injected from sops overlay
```

Note the placeholder tag — the first working tag comes from the Woodpecker infra-repo pipeline in Task 05. After that runs, update this value in a follow-up PR.

### Step 5: Dry-run validation
```bash
cd k3s/gxy-cassiopeia/apps/caddy
helm lint charts/caddy -f values.production.yaml
helm template caddy charts/caddy -f values.production.yaml | kubectl apply --dry-run=client -f -
```
Both exit 0.

### Step 6: Anti-checks — confirm CRITICAL fixes landed
```bash
helm template caddy charts/caddy -f values.production.yaml | grep -E 'containerPort: 2019' && echo "FAIL: admin port exposed" && exit 1 || echo "admin port correctly hidden"
helm template caddy charts/caddy -f values.production.yaml | grep -E '127\.0\.0\.1:2019' && echo "admin binds to loopback" || echo "FAIL: admin not bound to loopback" && exit 1
helm template caddy charts/caddy -f values.production.yaml | grep -E 'port: "2019"' && echo "FAIL: NetworkPolicy allows 2019" && exit 1 || echo "NetworkPolicy correctly blocks 2019"
helm template caddy charts/caddy -f values.production.yaml | grep -E 'cache_max_entries 10000' && echo "cache bound present" || echo "FAIL: no cache_max_entries" && exit 1
```
All four must pass the checks shown.

## Files

- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/Chart.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/values.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/deployment.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/configmap.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/secret.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/service.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/httproute.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/networkpolicy.yaml`
- Create: `k3s/gxy-cassiopeia/apps/caddy/values.production.yaml`

## Acceptance Criteria

- `helm lint` passes
- `helm template ... | kubectl apply --dry-run=client` exits 0
- Step 6 anti-checks all pass
- No init containers, no rclone sidecars, no site-data volume (R2-direct model per D3)

## Context

This is the complete serving layer. With the r2_alias module (Tasks 01-04) + caddy-fs-s3 + this chart, a single Caddy pod can read alias files from R2, rewrite request paths, and serve from R2 via the S3 filesystem module. No local disk.

## When Stuck

If `helm lint` complains about whitespace/indent, use `helm lint --strict` to see the exact line. If `kubectl apply --dry-run=client` fails on HTTPRoute, confirm the Gateway API CRDs are a known-installed version (Traefik bundles them). If values paths don't match template references, use `helm template --debug` to see the resolved tree.

## Constraints

- Do NOT reintroduce init containers, rclone sidecars, or the site-data emptyDir volume (R2-direct is the whole point)
- Do NOT add `containerPort: 2019` to the Deployment
- Do NOT add port 2019 to the NetworkPolicy ingress section
- Do NOT modify `k3s/gxy-static/apps/caddy/*` (that stays as sandbox per D20)
- Do NOT apply to any real cluster in this task
- Do NOT run git write commands
````

**Depends on:** Task 08

---

### Task 14 [M]: Origin IP allow-list + CF IP refresh cron

**Traceability:** Implements D29 (CRITICAL #3 partial, origin enumeration block) | Constrained by §4.5.8 origin restriction paragraph
**Files:**

- Create: `k3s/gxy-cassiopeia/apps/caddy/manifests/origin-allowlist-netpol.yaml`
- Create: `f/ops/refresh_cf_ips.ts` (in windmill repo)
- Create: `f/ops/refresh_cf_ips.yaml` (flow metadata — weekly cron)
- Create: `f/ops/refresh_cf_ips.test.ts`

#### Context

RFC §4.5.8 "Origin access restriction" (D29): Cilium ingress allow-lists Cloudflare's published IPv4/IPv6 ranges only. A Windmill cron (weekly) refreshes the allow-list by pulling from `https://www.cloudflare.com/ips-v4/` and `/ips-v6/` and patching the CiliumNetworkPolicy.

Plus an initial static allow-list baked into the NetworkPolicy manifest (the flow replaces it on first run).

#### Acceptance Criteria

- GIVEN the NetworkPolicy manifest WHEN applied THEN ingress to Caddy allowed only from CF CIDRs + node-internal + platform-team SSH bastion
- GIVEN the Windmill flow WHEN run against a cluster THEN fetches CF IPs, patches the CiliumNetworkPolicy, reports the diff
- GIVEN the flow schedule THEN every Monday 03:00 UTC
- GIVEN tests THEN mock HTTP fetch + kubectl patch, assert the expected patch payload

#### Verification

```bash
cd /Users/mrugesh/DEV/fCC-U/windmill && deno test f/ops/refresh_cf_ips.test.ts && \
  kubectl apply --dry-run=client -f /Users/mrugesh/DEV/fCC/infra/k3s/gxy-cassiopeia/apps/caddy/manifests/origin-allowlist-netpol.yaml
```

**Expected output:** tests pass; apply validates.

#### Constraints

- Flow must be idempotent (re-patching with same IPs is a no-op)
- Do NOT hardcode CF IPs — always fetch
- Add a safety gate: if fetched list is empty or < 10 prefixes, abort (likely a CF outage on their /ips endpoint)

#### Agent Prompt

````
You are implementing Task 14: Origin IP allow-list + CF IP refresh cron.

## Repos and CWDs

- Manifest in infra repo: `/Users/mrugesh/DEV/fCC/infra`
- Windmill flow in windmill repo: `/Users/mrugesh/DEV/fCC-U/windmill`

## Your Task

Per RFC §4.5.8 "Origin access restriction" (D29), allow-list Cloudflare published IP ranges at Cilium ingress on gxy-cassiopeia. Refresh weekly via a Windmill cron.

### Step 1: Static initial CiliumNetworkPolicy (infra repo)
Create `k3s/gxy-cassiopeia/apps/caddy/manifests/origin-allowlist-netpol.yaml`:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: caddy-origin-allowlist
  namespace: caddy
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: caddy
  ingress:
    # Cloudflare IPv4 ranges as of 2026-04-17. Refreshed weekly by
    # f/ops/refresh_cf_ips in windmill. Bake in the current list as a safe
    # default so the first deploy works before the cron runs.
    - fromCIDR:
        # Fetched from https://www.cloudflare.com/ips-v4/
        - 173.245.48.0/20
        - 103.21.244.0/22
        - 103.22.200.0/22
        - 103.31.4.0/22
        - 141.101.64.0/18
        - 108.162.192.0/18
        - 190.93.240.0/20
        - 188.114.96.0/20
        - 197.234.240.0/22
        - 198.41.128.0/17
        - 162.158.0.0/15
        - 104.16.0.0/13
        - 104.24.0.0/14
        - 172.64.0.0/13
        - 131.0.72.0/22
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
    # Node-internal health checks (cluster CIDR from gxy_cassiopeia_k3s.yml)
    - fromCIDR:
        - 10.7.0.0/16
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
```

Validate: `kubectl apply --dry-run=client -f k3s/gxy-cassiopeia/apps/caddy/manifests/origin-allowlist-netpol.yaml`

### Step 2: Windmill flow (windmill repo)
Create `f/ops/refresh_cf_ips.ts`:

```typescript
// Fetches Cloudflare's published IP ranges and patches the
// caddy-origin-allowlist CiliumNetworkPolicy on gxy-cassiopeia.
// Refs: RFC gxy-cassiopeia §4.5.8 (D29).

export interface RefreshResult {
  ipv4Count: number;
  ipv6Count: number;
  patched: boolean;
  reason?: string;
}

export async function refreshCfIps(opts: {
  kubeApi: string;            // https://<gxy-cassiopeia-api-server>:6443
  kubeToken: string;          // ServiceAccount token bound to cnp patch perms
  fetchFn?: typeof fetch;
} = {} as any): Promise<RefreshResult> {
  const fetchFn = opts.fetchFn ?? fetch;

  const v4Text = await (await fetchFn("https://www.cloudflare.com/ips-v4/")).text();
  const v6Text = await (await fetchFn("https://www.cloudflare.com/ips-v6/")).text();
  const ipv4 = v4Text.trim().split("\n").map(s => s.trim()).filter(Boolean);
  const ipv6 = v6Text.trim().split("\n").map(s => s.trim()).filter(Boolean);

  // Safety gate: CF has historically had >15 IPv4 prefixes.
  if (ipv4.length < 10) {
    return {ipv4Count: ipv4.length, ipv6Count: ipv6.length, patched: false, reason: "IPv4 list below safety threshold; aborting"};
  }

  const cidrs = [...ipv4, ...ipv6, "10.7.0.0/16"];

  // JSON Patch to replace the ingress fromCIDR list
  const patch = [{
    op: "replace",
    path: "/spec/ingress/0/fromCIDR",
    value: cidrs,
  }];

  const resp = await fetchFn(
    `${opts.kubeApi}/apis/cilium.io/v2/namespaces/caddy/ciliumnetworkpolicies/caddy-origin-allowlist`,
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json-patch+json",
        "Authorization": `Bearer ${opts.kubeToken}`,
      },
      body: JSON.stringify(patch),
    },
  );
  if (!resp.ok) throw new Error(`kubectl patch failed: ${resp.status} ${await resp.text()}`);

  return {ipv4Count: ipv4.length, ipv6Count: ipv6.length, patched: true};
}
```

### Step 3: Flow metadata (weekly cron)
`f/ops/refresh_cf_ips.yaml`:

```yaml
summary: Refresh Cloudflare IP allow-list for gxy-cassiopeia Caddy
description: |
  Weekly: fetches CF's published IPv4/IPv6 ranges and patches the
  caddy-origin-allowlist CiliumNetworkPolicy. Includes a safety gate that
  aborts if the fetched list has < 10 IPv4 prefixes (likely a CF API issue).
  Ref: RFC gxy-cassiopeia §4.5.8 D29.
schedule:
  cron: "0 3 * * 1"  # Monday 03:00 UTC
```

### Step 4: Tests
`f/ops/refresh_cf_ips.test.ts`:

```typescript
import {assertEquals, assertRejects} from "https://deno.land/std/assert/mod.ts";
import {refreshCfIps} from "./refresh_cf_ips.ts";

Deno.test("aborts when IPv4 list is suspiciously small", async () => {
  const fetchFn = async (url: string) => {
    if (url.includes("ips-v4")) return new Response("1.1.1.1/32\n");
    if (url.includes("ips-v6")) return new Response("2001:db8::/32\n");
    return new Response("ok");
  };
  const r = await refreshCfIps({kubeApi: "", kubeToken: "", fetchFn});
  assertEquals(r.patched, false);
  assertEquals(r.reason?.includes("safety threshold"), true);
});

Deno.test("patches CiliumNetworkPolicy with fetched CIDRs", async () => {
  const calls: any[] = [];
  const fetchFn = async (url: string, init?: RequestInit) => {
    calls.push({url, init});
    if (url.includes("ips-v4")) return new Response(Array.from({length: 15}, (_, i) => `10.${i}.0.0/24`).join("\n"));
    if (url.includes("ips-v6")) return new Response("2001:db8::/32\n");
    return new Response("ok", {status: 200});
  };
  const r = await refreshCfIps({kubeApi: "https://api", kubeToken: "t", fetchFn});
  assertEquals(r.patched, true);
  const patchCall = calls.find((c: any) => c.init?.method === "PATCH");
  const body = JSON.parse(patchCall.init.body);
  assertEquals(body[0].op, "replace");
  assertEquals(body[0].path, "/spec/ingress/0/fromCIDR");
});
```

Run: `cd /Users/mrugesh/DEV/fCC-U/windmill && deno test f/ops/refresh_cf_ips.test.ts`

## Files

- Create (infra repo): `k3s/gxy-cassiopeia/apps/caddy/manifests/origin-allowlist-netpol.yaml`
- Create (windmill repo): `f/ops/refresh_cf_ips.ts`
- Create (windmill repo): `f/ops/refresh_cf_ips.yaml`
- Create (windmill repo): `f/ops/refresh_cf_ips.test.ts`

## Acceptance Criteria

- `kubectl apply --dry-run=client -f k3s/gxy-cassiopeia/apps/caddy/manifests/origin-allowlist-netpol.yaml` exits 0
- Tests pass
- Flow aborts when IPv4 count < 10
- Successful run patches with the correct JSON Patch shape

## Context

Closes the origin-enumeration attack path. With this in place, an attacker with a leaked origin IP cannot send `Host: <any-site>.freecode.camp` to the node — L3 drops the connection before Caddy sees it.

## When Stuck

If the CiliumNetworkPolicy API group has changed (v2 → v2alpha1 or similar), check with `kubectl api-resources | grep cilium`. If the JSON Patch path doesn't exist (spec.ingress[0].fromCIDR absent at apply time), the initial manifest in Step 1 guarantees the shape — the flow must run AFTER the initial apply.

## Constraints

- TDD: tests first
- Safety gate MUST be in place (< 10 IPv4 prefixes → abort)
- Do NOT skip the IPv6 fetch (dual-stack hygiene)
- Do NOT modify existing infra CiliumNetworkPolicies
- Do NOT run git write commands
````

**Depends on:** Task 13

---

### Task 15 [M]: Phase 4 test-site smoke validation runbook + script

**Traceability:** Implements §6.6 Phase 4 exit criterion
**Files:**

- Create: `docs/runbooks/phase4-test-site-smoke.md`
- Create: `scripts/phase4-test-site-smoke.sh`
- Modify: `justfile` (add `phase4-smoke` recipe)

#### Context

A scripted smoke test that (1) uploads a test deploy to `gxy-cassiopeia-1/test.freecode.camp/deploys/<id>/`, (2) writes the production alias, (3) adds temp DNS, (4) curls the test URL via `Host` header on a node IP, (5) verifies alias flip within TTL, (6) cleans up.

This is the Phase 4 exit gate per §6.6.

#### Acceptance Criteria

- GIVEN the script WHEN run against a provisioned gxy-cassiopeia + R2 bucket THEN all steps exit 0
- GIVEN the runbook THEN covers both success and failure paths (rollback instructions)
- GIVEN `just phase4-smoke` THEN invokes the script with environment pre-loaded

#### Verification

```bash
shellcheck scripts/phase4-test-site-smoke.sh
```

**Expected output:** shellcheck passes.

#### Constraints

- Uses rclone for R2 upload (one-off, not the universe-cli pattern — this is infra's own smoke test)
- Must include cleanup of test prefix, alias, DNS record
- Does NOT flip production traffic — uses `test.freecode.camp` only

#### Agent Prompt

````
You are implementing Task 15: Phase 4 test-site smoke validation.

## Repo and CWD

Work in the infra repo: `/Users/mrugesh/DEV/fCC/infra`.

## Your Task

Scripted smoke validation that proves the full R2 → Caddy → Cloudflare chain works before Phase 4 exits. This is infra's own tooling — it uses rclone directly (not universe-cli), because universe-cli depends on Woodpecker which depends on this validation.

### Step 1: scripts/phase4-test-site-smoke.sh

```bash
#!/usr/bin/env bash
# Phase 4 exit validation per RFC gxy-cassiopeia §6.6.
# Uploads a test deploy to gxy-cassiopeia-1, writes production+preview aliases,
# verifies end-to-end serving, cleans up.
#
# Required env (via direnv at k3s/gxy-cassiopeia/):
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY  (R2 rw)
#   R2_ENDPOINT
#   R2_BUCKET=gxy-cassiopeia-1
#   GXY_CASSIOPEIA_NODE_IP  (any node public IP for Host-header smoke)
#   CF_API_TOKEN, CF_ZONE_ID  (for temp DNS record)

set -euo pipefail

: "${R2_BUCKET:?R2_BUCKET not set}"
: "${GXY_CASSIOPEIA_NODE_IP:?GXY_CASSIOPEIA_NODE_IP not set}"
: "${CF_API_TOKEN:?CF_API_TOKEN not set}"
: "${CF_ZONE_ID:?CF_ZONE_ID not set}"

TEST_SITE="test.freecode.camp"
DEPLOY_ID="phase4-$(date -u +%Y%m%d-%H%M%S)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Configure rclone in memory
export RCLONE_CONFIG="$TMP_DIR/rclone.conf"
rclone config create r2 s3 \
  provider=Cloudflare \
  endpoint="$R2_ENDPOINT" \
  access_key_id="$AWS_ACCESS_KEY_ID" \
  secret_access_key="$AWS_SECRET_ACCESS_KEY" >/dev/null

echo "[1/8] Create test deploy payload"
mkdir -p "$TMP_DIR/dist"
cat > "$TMP_DIR/dist/index.html" <<EOF
<!doctype html><html><body><h1>phase4-smoke ${DEPLOY_ID}</h1></body></html>
EOF

echo "[2/8] Upload deploy prefix"
rclone copy "$TMP_DIR/dist/" "r2:${R2_BUCKET}/${TEST_SITE}/deploys/${DEPLOY_ID}/"

echo "[3/8] Write production alias"
echo -n "${DEPLOY_ID}" | rclone rcat "r2:${R2_BUCKET}/${TEST_SITE}/production"

echo "[4/8] Verify origin serves the test page via Host-header"
sleep 5  # give Caddy alias cache a beat
HTTP_BODY=$(curl -fsS -H "Host: ${TEST_SITE}" "http://${GXY_CASSIOPEIA_NODE_IP}/")
echo "${HTTP_BODY}" | grep -q "${DEPLOY_ID}" || { echo "FAIL: origin did not serve test page"; exit 4; }

echo "[5/8] Verify preview URL 404 (no preview alias yet)"
PREVIEW_STATUS=$(curl -o /dev/null -s -w "%{http_code}" -H "Host: test--preview.freecode.camp" "http://${GXY_CASSIOPEIA_NODE_IP}/")
[ "$PREVIEW_STATUS" = "404" ] || { echo "FAIL: preview returned $PREVIEW_STATUS, expected 404"; exit 4; }

echo "[6/8] Write preview alias, verify preview URL returns 200"
echo -n "${DEPLOY_ID}" | rclone rcat "r2:${R2_BUCKET}/${TEST_SITE}/preview"
sleep 20  # alias cache TTL
PREVIEW_BODY=$(curl -fsS -H "Host: test--preview.freecode.camp" "http://${GXY_CASSIOPEIA_NODE_IP}/")
echo "${PREVIEW_BODY}" | grep -q "${DEPLOY_ID}" || { echo "FAIL: preview did not serve after alias write"; exit 4; }

echo "[7/8] Cleanup R2"
rclone purge "r2:${R2_BUCKET}/${TEST_SITE}/"

echo "[8/8] Cleanup DNS (if operator added a temp A record, remove it here)"
# Operator-added DNS cleanup instructions in runbook; script only cleans R2 for safety.

echo "OK: phase 4 smoke passed — ${DEPLOY_ID}"
```

### Step 2: docs/runbooks/phase4-test-site-smoke.md

```markdown
# Phase 4 Test-Site Smoke Runbook

Exit criterion for RFC §6.6 Phase 4.

## Prerequisites
- gxy-cassiopeia cluster Ready (Phase 3 done)
- Caddy Helm chart deployed (Task 13 applied)
- R2 bucket gxy-cassiopeia-1 exists with rw access key (Task 12 done)
- Temp DNS record for `test.freecode.camp` and `test--preview.freecode.camp` → one gxy-cassiopeia node IP (Cloudflare UI, proxy ON)

## Steps
1. `cd /Users/mrugesh/DEV/fCC/infra/k3s/gxy-cassiopeia` to load direnv tokens
2. `export GXY_CASSIOPEIA_NODE_IP=<ip>` (look up via `doctl compute droplet list | grep gxy-cassiopeia`)
3. `just phase4-smoke` (or `bash scripts/phase4-test-site-smoke.sh`)
4. Expected: exit 0 with "OK: phase 4 smoke passed"
5. Remove the temp DNS records for `test.freecode.camp` and `test--preview.freecode.camp`

## If it fails
- Step 2 fail → rclone config or R2 key issue; check `rclone ls r2:gxy-cassiopeia-1/`
- Step 4 fail → Caddy not routing; `kubectl -n caddy logs -l app.kubernetes.io/name=caddy`
- Step 6 fail → cache TTL too aggressive, or r2_alias module bug; extend sleep to 60s and retry
```

### Step 3: justfile recipe
Append to `/Users/mrugesh/DEV/fCC/infra/justfile`:

```just
[group('cassiopeia')]
phase4-smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    bash scripts/phase4-test-site-smoke.sh
```

### Step 4: Lint
```
shellcheck scripts/phase4-test-site-smoke.sh
```

## Files

- Create: `scripts/phase4-test-site-smoke.sh` (executable)
- Create: `docs/runbooks/phase4-test-site-smoke.md`
- Modify: `justfile`

## Acceptance Criteria

- `shellcheck scripts/phase4-test-site-smoke.sh` no warnings
- `just --unstable --fmt --check` passes
- Script has `set -euo pipefail`
- Script cleans up R2 state on success AND on failure (trap)

## Context

This is infra's own test, not a user-facing feature. It uses rclone directly because universe-cli depends on Woodpecker which depends on this validation passing. Do NOT try to use universe-cli here.

## When Stuck

If Caddy serves stale content after alias write, the 15s cache TTL + replica count may be higher than expected — extend the sleep. If preview URL returns 200 before the preview alias is written, there's a caching issue at CF or Caddy — check `cf-cache-status` header.

## Constraints

- Do NOT use universe-cli (bootstrapping circular dep)
- Clean up R2 state on exit (trap)
- Do NOT modify production DNS (only temp test records)
- Do NOT run git write commands
````

**Depends on:** Task 13, Task 14

---

### Task 16 [M]: universe-cli — Woodpecker API client

**Traceability:** Implements R15 streaming | Constrained by §4.8.6
**Files:**

- Create: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/woodpecker/client.ts`
- Create: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/woodpecker/types.ts`
- Create: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/woodpecker/client.test.ts`

#### Context

A self-contained `WoodpeckerClient` class with `createPipeline`, `streamLogs` (SSE), `getPipeline`. Bearer token auth. Typed responses. Used by deploy/promote/rollback commands.

#### Acceptance Criteria

- GIVEN `createPipeline(repoId, {branch, variables})` WHEN the mock server returns 200 with a Pipeline JSON THEN returns parsed Pipeline
- GIVEN the server returns 4xx/5xx THEN throws WoodpeckerError with status + body
- GIVEN `streamLogs` WHEN SSE data events arrive THEN yields parsed LogLine objects
- GIVEN SSE stream closes cleanly THEN the async generator returns
- Test coverage ≥ 85% on the client module

#### Verification

```bash
cd /Users/mrugesh/DEV/fCC-U/universe-cli && pnpm test src/woodpecker
```

**Expected output:** all tests pass.

#### Constraints

- Match the existing universe-cli style (ESM, strict TS, tsup build)
- No dependencies beyond `fetch` (native) and existing project deps
- Do NOT import from `@aws-sdk` — that's being removed from runtime deps (see Task 20)

#### Agent Prompt

````
You are implementing Task 16: universe-cli — Woodpecker API client.

## Repo and CWD

Work in the universe-cli repo: `/Users/mrugesh/DEV/fCC-U/universe-cli`. NOT the infra repo.

## Your Task

Implement `WoodpeckerClient` per RFC §4.8.6 lines 1451-1543. Typed TS class with Bearer auth, SSE log streaming, pipeline create + get. Test-first.

Read `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md` §4.8.6 before starting — the full TS is specified there.

### Step 1: Familiarize with codebase conventions
- Read `src/cli.ts` and `src/commands/deploy.ts` (current version) for code style, error hierarchy, output patterns.
- Read `package.json` for the test framework (vitest), build tool (tsup), lint (typescript-eslint).
- Read `tsconfig.json` for TS strict settings.

### Step 2: Write failing tests
Create `src/woodpecker/client.test.ts`:

```typescript
import { describe, it, expect, vi } from "vitest";
import { WoodpeckerClient } from "./client.js";
import { WoodpeckerError } from "./errors.js";

describe("WoodpeckerClient.createPipeline", () => {
  it("POSTs to /api/repos/{id}/pipelines with Bearer auth", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({number: 42, status: "pending"}), {status: 200}));
    const client = new WoodpeckerClient("https://wp.example", "tok", fetchMock);
    const pipeline = await client.createPipeline(10, {branch: "main", variables: {OP: "deploy"}});
    expect(pipeline.number).toBe(42);
    expect(fetchMock).toHaveBeenCalledWith(
      "https://wp.example/api/repos/10/pipelines",
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({ "Authorization": "Bearer tok" }),
      }),
    );
    const body = JSON.parse((fetchMock.mock.calls[0][1] as RequestInit).body as string);
    expect(body).toEqual({branch: "main", variables: {OP: "deploy"}});
  });

  it("throws WoodpeckerError on non-2xx", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response("unauthorized", {status: 401}));
    const client = new WoodpeckerClient("https://wp.example", "bad", fetchMock);
    await expect(client.createPipeline(10, {branch: "main"})).rejects.toThrow(WoodpeckerError);
  });
});

describe("WoodpeckerClient.streamLogs (SSE)", () => {
  it("yields parsed LogLine for each data event", async () => {
    // Construct a readable stream that emits SSE-formatted events
    const encoder = new TextEncoder();
    const events = [
      'data: {"ts":1,"message":"hello"}\n\n',
      'data: {"ts":2,"message":"world"}\n\n',
    ];
    const stream = new ReadableStream({
      start(controller) {
        for (const e of events) controller.enqueue(encoder.encode(e));
        controller.close();
      },
    });
    const fetchMock = vi.fn().mockResolvedValue(new Response(stream, {status: 200}));
    const client = new WoodpeckerClient("https://wp.example", "tok", fetchMock);
    const lines: any[] = [];
    for await (const line of client.streamLogs(10, 42, 1)) lines.push(line);
    expect(lines).toEqual([{ts:1, message:"hello"}, {ts:2, message:"world"}]);
  });

  it("handles events split across chunks", async () => {
    // Partial event boundary across two chunks should not drop data
  });
});
```

Run: `pnpm test src/woodpecker` — tests FAIL (no client yet).

### Step 3: Implement client.ts
Create `src/woodpecker/client.ts` matching the RFC §4.8.6 code shape. Adapt the fetch signature to accept an injected `fetchFn` for testability:

```typescript
export class WoodpeckerClient {
  constructor(
    private readonly endpoint: string,
    private readonly token: string,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}
  // ... createPipeline, streamLogs (async generator), getPipeline
}
```

### Step 4: Define types
Create `src/woodpecker/types.ts`:

```typescript
export interface Pipeline {
  number: number;
  status: "pending" | "running" | "success" | "failure" | "killed" | "error" | "blocked" | "declined";
  created: number;
  started?: number;
  finished?: number;
  commit: string;
  branch: string;
  variables?: Record<string, string>;
}

export interface LogLine {
  ts: number;
  message: string;
  pos?: number;
  proc?: string;
}

export interface CreatePipelineOptions {
  branch: string;
  variables?: Record<string, string>;
}
```

### Step 5: Error class
Create `src/woodpecker/errors.ts`:

```typescript
export class WoodpeckerError extends Error {
  constructor(message: string, public readonly status?: number, public readonly body?: string) {
    super(message);
    this.name = "WoodpeckerError";
  }
}
```

### Step 6: Index
Create `src/woodpecker/index.ts`:

```typescript
export { WoodpeckerClient } from "./client.js";
export { WoodpeckerError } from "./errors.js";
export type { Pipeline, LogLine, CreatePipelineOptions } from "./types.js";
```

### Step 7: Verify
```bash
cd /Users/mrugesh/DEV/fCC-U/universe-cli
pnpm test src/woodpecker
pnpm typecheck
pnpm lint src/woodpecker
```

Expect: all tests pass, typecheck clean, no lint warnings.

## Files

- Create: `src/woodpecker/client.ts`
- Create: `src/woodpecker/client.test.ts`
- Create: `src/woodpecker/types.ts`
- Create: `src/woodpecker/errors.ts`
- Create: `src/woodpecker/index.ts`

## Acceptance Criteria

- All tests in Step 2 pass
- Type coverage: `Pipeline`, `LogLine`, `CreatePipelineOptions` exported and used
- SSE parser handles multi-event buffers AND events split across chunks
- `WoodpeckerError` carries `status` + `body` when available
- `pnpm typecheck` clean
- Test coverage ≥ 85% of `client.ts` lines

## Context

The CLI uses this client to trigger Woodpecker pipelines and stream logs. All subsequent CLI commands (deploy/promote/rollback in Tasks 18-19) depend on it. Injecting `fetchFn` is critical for testability — do not bypass.

## When Stuck

If Woodpecker's SSE format differs from the `data: ...\n\n` convention (e.g., uses different event names), check the API docs at https://woodpecker-ci.org/api. If `streamLogs` runs into a disconnect mid-stream, the async generator should end gracefully; do NOT throw on `ReadableStream` close.

## Constraints

- TDD discipline
- Do NOT import from AWS SDK (@aws-sdk/*) — universe-cli is removing R2 dependencies
- Do NOT import from `node:*` — use Web APIs (fetch, TextDecoder, ReadableStream) for runtime portability
- Do NOT run git write commands
````

**Depends on:** Task 10 (needs a Woodpecker endpoint to target)

---

### Task 17 [M]: universe-cli — Config schema + site name validation

**Traceability:** Implements R13, config changes | Constrained by §4.8.1, §4.8.5, D19 (regex)
**Files:**

- Modify: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/config/schema.ts`
- Modify: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/config/loader.ts`
- Create: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/validation/site-name.ts`
- Create: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/validation/site-name.test.ts`
- Modify: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/config/schema.test.ts`

#### Context

Add a `woodpecker: {endpoint, repo_id}` section to the config schema. Remove the old `static.rclone_remote` and `static.bucket` fields (they're unused now). Site-name validation enforces the no-`--` rule + RFC-1123 DNS label constraints (D19).

#### Acceptance Criteria

- GIVEN a .universe.yaml with `woodpecker: {endpoint: ..., repo_id: 42}` WHEN loaded THEN schema validates
- GIVEN a config missing `woodpecker` THEN loader throws a clear error
- GIVEN `validateSiteName("hello-world")` THEN no throw
- GIVEN `validateSiteName("hello--world")` THEN throws "must not contain --"
- GIVEN `validateSiteName("Hello")` THEN throws (uppercase rejected)
- GIVEN `validateSiteName("-hello")` or `"hello-"` THEN throws (leading/trailing hyphen)
- GIVEN a name ending with `-preview` or starting with `preview-` THEN warns (console.warn) but does not throw

#### Verification

```bash
cd /Users/mrugesh/DEV/fCC-U/universe-cli && pnpm test src/validation src/config
```

**Expected output:** all tests pass.

#### Constraints

- Preserve existing config fields other than static.rclone_remote, static.bucket
- Regex lives in a single exported constant for reuse
- Validation throws on hard rules, warns on soft rules

#### Agent Prompt

````
You are implementing Task 17: universe-cli — Config schema update + site name validation.

## Repo and CWD

Work in the universe-cli repo: `/Users/mrugesh/DEV/fCC-U/universe-cli`.

## Your Task

Two independent units:
1. Update config schema to add `woodpecker: {endpoint, repo_id}` and remove the legacy `static.rclone_remote` + `static.bucket` fields.
2. Add site-name validation (no `--`, RFC-1123 DNS label, no leading/trailing hyphen).

Both are pre-reqs for Tasks 18-19.

Read RFC §4.8.1 (config schema) and §4.8.5 (site name validation) at `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md`.

### Step 1: Read existing schema
- `src/config/schema.ts` — current Zod or TS shape
- `src/config/loader.ts` — how config is read/validated
- `src/config/schema.test.ts` — existing test style

### Step 2: Site name validation — write failing tests first
Create `src/validation/site-name.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { validateSiteName, SITE_NAME_REGEX } from "./site-name.js";

describe("validateSiteName", () => {
  it("accepts valid names", () => {
    for (const n of ["hello-world", "docs", "a", "foo123", "a-b-c"]) {
      expect(() => validateSiteName(n)).not.toThrow();
    }
  });
  it("rejects double-hyphen", () => {
    expect(() => validateSiteName("hello--world")).toThrow(/must not contain "--"/);
  });
  it("rejects uppercase", () => {
    expect(() => validateSiteName("Hello")).toThrow();
  });
  it("rejects leading/trailing hyphen", () => {
    expect(() => validateSiteName("-hello")).toThrow();
    expect(() => validateSiteName("hello-")).toThrow();
  });
  it("rejects empty", () => {
    expect(() => validateSiteName("")).toThrow();
  });
  it("rejects >50 chars", () => {
    expect(() => validateSiteName("a".repeat(51))).toThrow(/1-50 chars/);
  });
  it("warns on preview-* and *-preview but does not throw", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    validateSiteName("preview-foo");
    validateSiteName("foo-preview");
    expect(warn).toHaveBeenCalledTimes(2);
    warn.mockRestore();
  });
});
```

### Step 3: Implement src/validation/site-name.ts
Exact code per RFC §4.8.5 lines 1430-1464. Export `SITE_NAME_REGEX`, `SITE_NAME_MAX_LENGTH`, `validateSiteName`.

### Step 4: Schema — write failing tests first
Create new tests in `src/config/schema.test.ts`:

```typescript
describe("config schema with woodpecker section", () => {
  it("requires woodpecker.endpoint and woodpecker.repo_id", () => {
    const yaml = { name: "hello", static: { output_dir: "dist" } };
    expect(() => parseConfig(yaml)).toThrow(/woodpecker/);
  });
  it("accepts config with woodpecker section", () => {
    const yaml = {
      name: "hello",
      static: { output_dir: "dist" },
      woodpecker: { endpoint: "https://wp.example", repo_id: 42 },
    };
    const cfg = parseConfig(yaml);
    expect(cfg.woodpecker.repo_id).toBe(42);
  });
  it("rejects legacy static.rclone_remote and static.bucket fields", () => {
    const yaml = {
      name: "hello",
      static: { output_dir: "dist", rclone_remote: "r2", bucket: "foo" },
      woodpecker: { endpoint: "https://wp.example", repo_id: 42 },
    };
    expect(() => parseConfig(yaml)).toThrow(/rclone_remote|bucket/);
  });
});
```

### Step 5: Modify src/config/schema.ts
- Add `woodpecker: { endpoint: string; repo_id: number }` (required)
- Remove `rclone_remote` and `bucket` from the `static` sub-schema
- If using Zod: `.strict()` on the static schema so unknown fields are rejected

### Step 6: Update loader.ts
- Ensure `loadConfig` fails with a clear error when `woodpecker` section is missing: "woodpecker.endpoint required; see RFC gxy-cassiopeia §4.8.1 for the new config shape"

### Step 7: Wire validation into `universe create` and `universe register`
- Read `src/commands/create.ts` and `src/commands/register.ts` (if exists)
- Before creating/registering, call `validateSiteName(name)` — fail fast
- Add tests to those commands' test files to confirm the check fires

### Step 8: Verify
```bash
cd /Users/mrugesh/DEV/fCC-U/universe-cli
pnpm test src/validation src/config src/commands/create src/commands/register
pnpm typecheck
```

## Files

- Modify: `src/config/schema.ts`
- Modify: `src/config/loader.ts`
- Modify: `src/config/schema.test.ts`
- Create: `src/validation/site-name.ts`
- Create: `src/validation/site-name.test.ts`
- Modify: `src/commands/create.ts` (call validateSiteName)
- Modify: `src/commands/register.ts` (call validateSiteName) — if file exists
- Modify: corresponding `.test.ts` files

## Acceptance Criteria

- All tests pass (`pnpm test src/validation src/config`)
- `pnpm typecheck` clean
- Schema rejects config with `static.rclone_remote` or `static.bucket`
- Schema rejects config missing `woodpecker` section
- `validateSiteName("foo--bar")` throws
- `validateSiteName("preview-foo")` warns but does not throw

## Context

This is prep work for Tasks 18-19 (deploy/promote/rollback rewrites), which need the new config shape and validation in place. It also enforces the D19 naming rule at the earliest possible point (scaffold time), not at deploy time.

## When Stuck

If removing `rclone_remote` / `bucket` breaks existing commands (status, list, logs), those commands probably read R2 directly — flag as a blocker and check whether they should be stubbed to use Woodpecker API in later tasks.

## Constraints

- TDD: tests first
- Do NOT keep backward-compat shims for the removed fields — they must fail loudly so CI catches uses
- Do NOT touch `src/commands/deploy.ts`, `promote.ts`, `rollback.ts` (Tasks 18-19 own those)
- Do NOT run git write commands
````

**Depends on:** None

---

### Task 18 [M]: universe-cli — Rewrite `deploy` command

**Traceability:** Implements R10 | Constrained by §4.8.2, §7.2 (no R2 creds on dev machine)
**Files:**

- Modify: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/commands/deploy.ts`
- Modify: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/commands/deploy.test.ts`

#### Context

Replace the current direct-S3 upload implementation with Woodpecker API trigger per RFC §4.8.2. The new implementation: resolves Woodpecker token from env, enforces git clean, creates a pipeline with OP=deploy + DEPLOY_TARGET=preview, optionally streams logs via SSE.

#### Acceptance Criteria

- GIVEN `universe deploy` WHEN run in a clean-git repo THEN triggers Woodpecker pipeline and returns success with pipeline number
- GIVEN a dirty git tree THEN fails with "commit changes before deploying"
- GIVEN no WOODPECKER_TOKEN env THEN fails with a clear error message
- GIVEN `--follow=false` THEN returns immediately without streaming
- GIVEN `--follow=true` (default in TTY) THEN streams pipeline logs until completion
- Tests cover: happy path, dirty git, missing token, API error

#### Verification

```bash
cd /Users/mrugesh/DEV/fCC-U/universe-cli && pnpm test src/commands/deploy
```

**Expected output:** tests pass.

#### Constraints

- Do NOT import `@aws-sdk/client-s3`, rclone, or any S3 code
- Remove any call to `createS3Client`, `uploadDirectory`, `writeAlias` from this file
- Must handle network errors gracefully

#### Agent Prompt

````
You are implementing Task 18: universe-cli — Rewrite `universe deploy`.

## Repo and CWD

Work in the universe-cli repo: `/Users/mrugesh/DEV/fCC-U/universe-cli`.

## Your Task

Replace the current `src/commands/deploy.ts` implementation entirely. The new version triggers a Woodpecker pipeline via API (using `WoodpeckerClient` from Task 16), optionally streams logs, and **never touches R2**.

Read RFC §4.8.2 (lines 1322-1366) for the full target shape.

### Step 1: Read current implementation
- `src/commands/deploy.ts` — current (direct R2 upload)
- Note: it imports `createS3Client`, `uploadDirectory`, `writeAlias` from `src/storage/*` and `src/deploy/upload.ts`. Those modules will be deleted in Task 20.

### Step 2: Write failing tests for the new shape
Modify or replace `src/commands/deploy.test.ts`. Tests should exercise:

```typescript
describe("universe deploy (Woodpecker)", () => {
  it("triggers pipeline with OP=deploy + DEPLOY_TARGET=preview", async () => {
    // Mock WoodpeckerClient.createPipeline; assert it's called with the right args
  });
  it("fails if git working tree is dirty", async () => {
    // Mock getGitState to return dirty
    // Assert deploy throws with "commit changes before deploying"
  });
  it("fails with clear message when WOODPECKER_TOKEN missing", async () => {
    // Unset env, assert CredentialError
  });
  it("streams logs when --follow (TTY default)", async () => {
    // Mock streamLogs generator
  });
  it("returns immediately with --follow=false", async () => {});
  it("outputs JSON with pipelineNumber, site, previewUrl when --json", async () => {});
});
```

Tests FAIL (current deploy.ts does not use WoodpeckerClient).

### Step 3: Rewrite deploy.ts
```typescript
import { loadConfig } from "../config/loader.js";
import { getGitState } from "../deploy/git.js";
import { WoodpeckerClient } from "../woodpecker/index.js";
import { resolveWoodpeckerToken } from "../credentials/woodpecker.js";
import { type OutputContext, outputSuccess, outputError } from "../output/format.js";
import { EXIT_GIT, EXIT_CREDENTIALS, exitWithCode } from "../output/exit-codes.js";

export interface DeployOptions {
  json: boolean;
  branch?: string;
  follow?: boolean;
}

export async function deploy(options: DeployOptions): Promise<void> {
  const config = loadConfig();
  const ctx: OutputContext = { json: options.json, command: "deploy" };
  let token: string;
  try {
    token = resolveWoodpeckerToken();
  } catch (err) {
    outputError(ctx, EXIT_CREDENTIALS, (err as Error).message);
    exitWithCode(EXIT_CREDENTIALS, (err as Error).message);
    return;
  }
  const git = getGitState();
  if (git.hash === null) {
    outputError(ctx, EXIT_GIT, "Not a git repository or no commits yet");
    exitWithCode(EXIT_GIT, "Not a git repository or no commits yet");
    return;
  }
  if (git.dirty) {
    outputError(ctx, EXIT_GIT, "Git working tree is dirty — commit changes before deploying");
    exitWithCode(EXIT_GIT, "Git working tree is dirty — commit changes before deploying");
    return;
  }
  const client = new WoodpeckerClient(config.woodpecker.endpoint, token);
  const pipeline = await client.createPipeline(config.woodpecker.repo_id, {
    branch: options.branch ?? git.branch,
    variables: { OP: "deploy", DEPLOY_TARGET: "preview" },
  });
  const previewDomain = config.domain?.preview ?? `${config.name}--preview.freecode.camp`;
  outputSuccess(ctx, `Deploy pipeline #${pipeline.number} started\n  Preview: https://${previewDomain}`, {
    pipelineNumber: pipeline.number,
    site: config.name,
    previewUrl: `https://${previewDomain}`,
    branch: options.branch ?? git.branch,
  });
  const shouldFollow = options.follow ?? process.stdout.isTTY;
  if (shouldFollow) {
    // Iterate over Woodpecker steps and stream each; or poll pipeline state and stream live step
    // Minimal v1: stream the first step's logs until pipeline completes
    await streamAllStepLogs(client, config.woodpecker.repo_id, pipeline.number);
  }
}

async function streamAllStepLogs(client: WoodpeckerClient, repoId: number, pipelineNum: number) {
  // Poll getPipeline until a step is running; stream its logs; advance to next step.
  // Acceptable v1 implementation: poll every 2s, print log lines as they arrive.
}
```

### Step 4: Create src/credentials/woodpecker.ts
```typescript
import { CredentialError } from "../errors.js";

export function resolveWoodpeckerToken(): string {
  const token = process.env.WOODPECKER_TOKEN;
  if (!token) {
    throw new CredentialError(
      "WOODPECKER_TOKEN not set. Create a token at " +
      "https://woodpecker.freecodecamp.net/user/tokens and export via direnv or your shell profile.",
    );
  }
  return token;
}
```

### Step 5: Verify tests pass
```bash
pnpm test src/commands/deploy src/credentials
pnpm typecheck
```

## Files

- Modify: `src/commands/deploy.ts` (full rewrite)
- Modify: `src/commands/deploy.test.ts` (new tests)
- Create: `src/credentials/woodpecker.ts`
- Create: `src/credentials/woodpecker.test.ts`

## Acceptance Criteria

- All tests pass
- No imports from `@aws-sdk/*` in `deploy.ts`
- No references to `createS3Client`, `uploadDirectory`, `writeAlias` in `deploy.ts`
- Dirty git tree fails with exit code `EXIT_GIT`
- Missing WOODPECKER_TOKEN fails with exit code `EXIT_CREDENTIALS`
- `--json` output includes pipelineNumber + site + previewUrl

## Context

This is the CLI-side counterpart to Task 21 (the pipeline YAML). The CLI triggers the pipeline, the pipeline does the build+upload+alias on Woodpecker (with its repo-scoped credentials). Developer never handles R2.

## When Stuck

If streaming logs across multi-step pipelines is complex, minimal v1 is: tail the first step's logs, then on completion move to next step via `getPipeline` polling. Don't over-engineer.

## Constraints

- TDD
- Do NOT import S3 SDK
- Do NOT write to R2 directly; Woodpecker does that
- Do NOT break the existing `--json` output contract (consumers parse it)
- Do NOT run git write commands
````

**Depends on:** Task 16, Task 17

---

### Task 19 [M]: universe-cli — Rewrite `promote` + `rollback`

**Traceability:** Implements R11, R12 | Constrained by §4.8.3, §4.8.4
**Files:**

- Modify: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/commands/promote.ts`
- Modify: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/commands/rollback.ts`
- Modify: corresponding `.test.ts` files

#### Context

Parallel rewrites to `deploy` — both commands now trigger Woodpecker pipelines with appropriate `OP` variables. `rollback` requires `--to <deploy-id>`.

#### Acceptance Criteria

- GIVEN `universe promote` WHEN invoked THEN Woodpecker pipeline with OP=promote triggered
- GIVEN `universe rollback --to 20260501-120000-abc123` THEN pipeline with OP=rollback + ROLLBACK_TO triggered
- GIVEN `universe rollback` without `--to` THEN fails with clear error
- Tests cover: happy paths, missing --to, API errors

#### Verification

```bash
cd /Users/mrugesh/DEV/fCC-U/universe-cli && pnpm test src/commands/promote src/commands/rollback
```

**Expected output:** tests pass.

#### Constraints

- No direct R2 access
- Follow the same pattern as `deploy.ts` (Task 18)
- Use the `WoodpeckerClient` from Task 16

#### Agent Prompt

````
You are implementing Task 19: universe-cli — Rewrite `promote` + `rollback`.

## Repo and CWD

Work in the universe-cli repo: `/Users/mrugesh/DEV/fCC-U/universe-cli`.

## Your Task

Parallel rewrites to `deploy` (Task 18) for the promote and rollback commands. Same pattern: trigger Woodpecker pipeline with appropriate OP variable.

Read RFC §4.8.3 (lines 1367-1395) and §4.8.4 (lines 1396-1429) for the target shapes.

### Step 1: Write failing tests
`src/commands/promote.test.ts`:

```typescript
describe("universe promote", () => {
  it("triggers pipeline with OP=promote", async () => {
    // Mock WoodpeckerClient; assert createPipeline called with {OP: "promote"} variables
  });
  it("outputs production URL", async () => {});
});
```

`src/commands/rollback.test.ts`:

```typescript
describe("universe rollback", () => {
  it("requires --to <deploy-id>", async () => {
    // Assert fails with clear message when --to is absent
  });
  it("triggers pipeline with OP=rollback and ROLLBACK_TO", async () => {});
  it("validates deploy-id format", async () => {
    // Invalid format (not matching deploy-id regex) should fail before API call
  });
});
```

Tests FAIL (current promote.ts/rollback.ts still do R2 writes).

### Step 2: Rewrite promote.ts
```typescript
import { loadConfig } from "../config/loader.js";
import { getGitState } from "../deploy/git.js";
import { WoodpeckerClient } from "../woodpecker/index.js";
import { resolveWoodpeckerToken } from "../credentials/woodpecker.js";
import { type OutputContext, outputSuccess, outputError } from "../output/format.js";
import { EXIT_CREDENTIALS, exitWithCode } from "../output/exit-codes.js";

export interface PromoteOptions {
  json: boolean;
  follow?: boolean;
}

export async function promote(options: PromoteOptions): Promise<void> {
  const config = loadConfig();
  const ctx: OutputContext = { json: options.json, command: "promote" };
  let token: string;
  try { token = resolveWoodpeckerToken(); }
  catch (err) { outputError(ctx, EXIT_CREDENTIALS, (err as Error).message); exitWithCode(EXIT_CREDENTIALS, (err as Error).message); return; }

  const git = getGitState();
  const client = new WoodpeckerClient(config.woodpecker.endpoint, token);
  const pipeline = await client.createPipeline(config.woodpecker.repo_id, {
    branch: git.branch ?? "main",
    variables: { OP: "promote" },
  });
  const productionDomain = config.domain?.production ?? `${config.name}.freecode.camp`;
  outputSuccess(ctx, `Promote pipeline #${pipeline.number} started\n  Production: https://${productionDomain}`, {
    pipelineNumber: pipeline.number,
    site: config.name,
    productionUrl: `https://${productionDomain}`,
  });

  if (options.follow ?? process.stdout.isTTY) {
    await streamAllStepLogs(client, config.woodpecker.repo_id, pipeline.number);
  }
}
```

### Step 3: Rewrite rollback.ts
```typescript
import { loadConfig } from "../config/loader.js";
import { WoodpeckerClient } from "../woodpecker/index.js";
import { resolveWoodpeckerToken } from "../credentials/woodpecker.js";
import { type OutputContext, outputSuccess, outputError } from "../output/format.js";
import { EXIT_ARGS, EXIT_CREDENTIALS, exitWithCode } from "../output/exit-codes.js";

const DEPLOY_ID_STRICT_REGEX = /^\d{8}-\d{6}-([a-f0-9]{7}|dirty-[a-f0-9]{8})$/;

export interface RollbackOptions {
  json: boolean;
  to?: string;
  follow?: boolean;
}

export async function rollback(options: RollbackOptions): Promise<void> {
  const config = loadConfig();
  const ctx: OutputContext = { json: options.json, command: "rollback" };

  if (!options.to) {
    outputError(ctx, EXIT_ARGS, "--to <deploy-id> is required. Use the Woodpecker UI pipeline history to find prior deploy IDs.");
    exitWithCode(EXIT_ARGS, "--to required");
    return;
  }
  if (!DEPLOY_ID_STRICT_REGEX.test(options.to)) {
    outputError(ctx, EXIT_ARGS, `Invalid deploy ID format: ${options.to}. Expected YYYYMMDD-HHMMSS-<sha7> or YYYYMMDD-HHMMSS-dirty-<hex8>.`);
    exitWithCode(EXIT_ARGS, "Invalid deploy ID");
    return;
  }

  let token: string;
  try { token = resolveWoodpeckerToken(); }
  catch (err) { outputError(ctx, EXIT_CREDENTIALS, (err as Error).message); exitWithCode(EXIT_CREDENTIALS, (err as Error).message); return; }

  const client = new WoodpeckerClient(config.woodpecker.endpoint, token);
  const pipeline = await client.createPipeline(config.woodpecker.repo_id, {
    branch: "main",
    variables: { OP: "rollback", ROLLBACK_TO: options.to },
  });
  outputSuccess(ctx, `Rollback pipeline #${pipeline.number} started → deploy ${options.to}`, {
    pipelineNumber: pipeline.number,
    rollbackTo: options.to,
  });

  if (options.follow ?? process.stdout.isTTY) {
    await streamAllStepLogs(client, config.woodpecker.repo_id, pipeline.number);
  }
}
```

### Step 4: Exit code EXIT_ARGS
If `src/output/exit-codes.ts` doesn't have EXIT_ARGS, add it (use the next unused integer; don't collide with existing codes). Reference existing codes by reading that file first.

### Step 5: Shared helper (optional DRY)
If `streamAllStepLogs` is duplicated across deploy/promote/rollback, extract to `src/woodpecker/stream.ts`:

```typescript
export async function streamAllStepLogs(client: WoodpeckerClient, repoId: number, pipelineNum: number): Promise<void> { /*...*/ }
```

Import from all three commands.

### Step 6: Verify
```bash
pnpm test src/commands/promote src/commands/rollback
pnpm typecheck
```

## Files

- Modify: `src/commands/promote.ts` (full rewrite)
- Modify: `src/commands/promote.test.ts`
- Modify: `src/commands/rollback.ts` (full rewrite)
- Modify: `src/commands/rollback.test.ts`
- Possibly Modify: `src/output/exit-codes.ts` (add EXIT_ARGS if missing)
- Possibly Create: `src/woodpecker/stream.ts` (extract if DRY)

## Acceptance Criteria

- Tests pass for both commands
- `rollback` without --to fails loudly
- `rollback --to bogus` fails format validation BEFORE any API call
- `promote` triggers OP=promote pipeline
- `rollback` triggers OP=rollback pipeline with ROLLBACK_TO
- Typecheck clean
- No R2/rclone imports in either file

## Context

Per RFC §4.6.2, the pipeline handles all R2 operations (promote resolves preview→production in the pipeline itself, rollback writes the explicit ROLLBACK_TO value). The CLI is just a pipeline trigger.

## When Stuck

If `universe history` (future command) would make `--to` optional (interactive picker), defer that UX — for v1, `--to` is required. Keep the code small and deterministic.

## Constraints

- TDD
- Do NOT do R2 operations in either file
- Strict deploy-ID regex validation in rollback
- Do NOT change the existing flag surface except: rollback adds `--to` (was previously `--deploy-id`? check and preserve/migrate)
- Do NOT run git write commands
````

**Depends on:** Task 18

---

### Task 20 [M]: universe-cli — Remove legacy rclone/S3 code + release v0.4.0-beta.1

**Traceability:** Implements R10 scope boundary, §7.2 invariant
**Files:**

- Delete: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/deploy/upload.ts`
- Delete: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/deploy/metadata.ts` (pipeline generates this now)
- Delete: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/storage/*.ts` (all S3-touching code)
- Delete: corresponding `.test.ts` files for deleted modules
- Modify: `/Users/mrugesh/DEV/fCC-U/universe-cli/src/credentials/resolver.ts` (remove rclone credential paths, keep Woodpecker token resolution)
- Modify: `/Users/mrugesh/DEV/fCC-U/universe-cli/package.json` (remove `@aws-sdk/client-s3` from runtime deps; bump version to 0.4.0-beta.1)
- Modify: `/Users/mrugesh/DEV/fCC-U/universe-cli/CHANGELOG.md`

#### Context

Delete all S3-touching code paths (enforces the "no R2 creds on dev machines" invariant). Update deps, bump version to 0.4.0-beta.1. Keep S3 code only in test fixtures (if any remain for Windmill flow tests).

#### Acceptance Criteria

- GIVEN the full test suite WHEN run THEN all tests pass
- GIVEN `package.json` THEN no `@aws-sdk/client-s3` in `dependencies` (may remain in `devDependencies` for test fixtures if needed)
- GIVEN the codebase WHEN grep'd for `rclone|S3Client|createS3Client|putObject|getObject` in `src/` THEN no production code matches (only tests/mocks)
- GIVEN `pnpm typecheck` THEN passes
- GIVEN CHANGELOG THEN documents the breaking changes for v0.4.0-beta.1

#### Verification

```bash
cd /Users/mrugesh/DEV/fCC-U/universe-cli && \
  pnpm install && \
  pnpm test && \
  pnpm typecheck && \
  ! grep -rE 'S3Client|createS3Client|uploadDirectory' src/ --include='*.ts' | grep -v test
```

**Expected output:** all commands exit 0; last grep returns no matches.

#### Constraints

- Do NOT break existing `create`, `register`, `logs`, `status`, `list` commands — scope is deploy/promote/rollback + config + validation
- Do NOT delete files still imported by remaining commands
- Release is local version bump + changelog only; actual npm publish is an operator step

#### Agent Prompt

````
You are implementing Task 20: universe-cli — Remove legacy rclone/S3 code + release v0.4.0-beta.1.

## Repo and CWD

Work in the universe-cli repo: `/Users/mrugesh/DEV/fCC-U/universe-cli`.

## Your Task

Delete every file under `src/` that exists only to do R2 direct access. This enforces the "no R2 creds on dev machines" invariant (RFC §7.2) by removing the capability. Then bump version to 0.4.0-beta.1, update CHANGELOG.

### Step 1: Enumerate files to delete
Files to delete (confirm each exists before deleting; they are all pre-RFC-v0.4 code paths):

- `src/deploy/upload.ts` and `.test.ts`
- `src/deploy/metadata.ts` and `.test.ts` (pipeline writes `_deploy-meta.json` now)
- `src/deploy/id.ts` and `.test.ts` (pipeline generates deploy IDs now) — keep ONLY if still used by output formatting
- `src/deploy/preflight.ts` and `.test.ts` (no local build → no output_dir preflight needed)
- `src/storage/client.ts` (S3 client factory)
- `src/storage/operations.ts` (S3 list/get/put)
- `src/storage/aliases.ts` (writeAlias/readAlias direct to R2)
- `src/storage/deploys.ts`
- Their corresponding `.test.ts` files

Run `grep -rE 'from.*(storage|deploy/(upload|metadata|preflight|id))' src/` to find any remaining imports. If any production file (not test) still imports these, you have a blocker — flag it.

### Step 2: Dependency audit
```bash
grep -rE '@aws-sdk/client-s3' src/
```
If any production `.ts` (not `.test.ts`) matches: you have a leak. Fix or flag.

```bash
cat package.json | jq '.dependencies | keys[]' | grep aws
```
Remove `@aws-sdk/client-s3` from `dependencies`. Move to `devDependencies` ONLY if test fixtures need it; otherwise remove entirely.

### Step 3: src/credentials/resolver.ts
Current file resolves rclone credentials. Delete or slim it:
- If `resolveCredentials` is referenced anywhere in remaining production code, refactor callers to use `resolveWoodpeckerToken` from Task 18's `src/credentials/woodpecker.ts`.
- Otherwise delete the file.

### Step 4: Version bump
`package.json`:
```json
"version": "0.4.0-beta.1"
```

### Step 5: CHANGELOG
Update `CHANGELOG.md`:

```markdown
## [0.4.0-beta.1] — 2026-04-XX

### Breaking
- `universe deploy|promote|rollback` now trigger Woodpecker CI pipelines instead of uploading directly to R2. Developer machines no longer need R2 credentials; set WOODPECKER_TOKEN via direnv.
- Config schema: `static.rclone_remote` and `static.bucket` fields REMOVED. Add `woodpecker: { endpoint, repo_id }` section instead.
- `universe rollback` requires `--to <deploy-id>` (previously optional); format validated against `YYYYMMDD-HHMMSS-<sha7|dirty-hex8>`.
- Constellation site names containing `--` are rejected at `universe create`/`register` time (reserved for preview routing).

### Added
- Woodpecker API client (`src/woodpecker/*`) with SSE log streaming.
- Site-name validation (`src/validation/site-name.ts`).

### Removed
- `@aws-sdk/client-s3` runtime dependency.
- All `src/storage/*` and most `src/deploy/*` modules (legacy R2 upload path).

### Migration
- Install: `pnpm install -g @freecodecamp/universe-cli@0.4.0-beta.1`
- Set `WOODPECKER_TOKEN` (create one at https://woodpecker.freecodecamp.net/user/tokens)
- Update `.universe.yaml` per [RFC §4.8.1](https://github.com/freeCodeCamp/infra/blob/main/docs/rfc/gxy-cassiopeia.md#481-config-schema)
- Delete any local R2/rclone credentials you previously exported for universe-cli
```

### Step 6: Full test run
```bash
pnpm install  # refresh lockfile after package.json changes
pnpm test
pnpm typecheck
pnpm lint
! grep -rE 'S3Client|createS3Client|uploadDirectory|writeAlias|@aws-sdk' src/ --include='*.ts' | grep -vE '\.test\.ts|__mocks__'
```
All exit 0; last command returns no matches (uses of those symbols only remain in tests/mocks if any).

### Step 7: Build
```bash
pnpm build
```
Expect `dist/` to be produced with no errors.

## Files

- Delete: `src/deploy/upload.ts`, `src/deploy/upload.test.ts`
- Delete: `src/deploy/metadata.ts`, `src/deploy/metadata.test.ts`
- Delete: `src/deploy/preflight.ts`, `src/deploy/preflight.test.ts`
- Delete: `src/storage/client.ts`, `src/storage/operations.ts`, `src/storage/aliases.ts`, `src/storage/deploys.ts` (+ corresponding `.test.ts`)
- Possibly Delete: `src/deploy/id.ts`, `src/credentials/resolver.ts` (if unused after refactor)
- Modify: `package.json` (version + remove @aws-sdk/client-s3 from deps)
- Modify: `pnpm-lock.yaml` (regenerated by pnpm install)
- Modify: `CHANGELOG.md`

## Acceptance Criteria

- `pnpm test` all pass
- `pnpm typecheck` clean
- `pnpm lint` clean
- `pnpm build` produces dist/
- `grep -rE 'S3Client' src/ --include='*.ts' | grep -v test` returns no matches
- `package.json` dependencies has no @aws-sdk
- CHANGELOG documents all breaking changes

## Context

This is the cleanup pass that enforces the "no R2 creds on dev machines" invariant by deletion, not by convention. Any future PR reintroducing these files is a protocol violation per RFC §7.2.

## When Stuck

If a remaining command (e.g., `universe status`) still imports a deleted module, it either needs rewriting to use Woodpecker API, OR the command should be marked stub ("Not supported in 0.4.0-beta.1; coming in 0.4.0") with a clear runtime error. Document in CHANGELOG and flag.

## Constraints

- Delete, don't comment out
- Preserve test coverage — moved tests become obsolete; delete them with the implementations
- Do NOT publish to npm in this task (publish is a separate operator action)
- Do NOT run git write commands
````

**Depends on:** Task 19

---

### Task 21 [L]: `.woodpecker/deploy.yaml` pipeline template

**Traceability:** Implements R7, R14, R17 | Constrained by §4.6.2, D24 (step ordering)
**Files:**

- Create: `/Users/mrugesh/DEV/fCC-U/universe-templates/static/.woodpecker/deploy.yaml` (new repo OR seed location TBD — for v1 living in infra repo at `docs/templates/woodpecker-static-deploy.yaml`)

#### Context

The canonical pipeline template that constellation repos copy into their `.woodpecker/deploy.yaml`. 9 steps in the specific order defined by D24 (verify → snapshot → purge → write → smoke → revert). Full YAML in RFC §4.6.2 lines 901-1213.

For v1, we don't have a `universe-templates` repo yet — store the template under `infra/docs/templates/` and document that registration copies it manually.

#### Acceptance Criteria

- GIVEN the YAML WHEN parsed as Woodpecker workflow YAML THEN no errors
- GIVEN the step order THEN: compute-deploy-id → build → upload → resolve-deploy-id → verify-deploy → snapshot-previous-alias → purge-cache-pre → write-alias → smoke-test → revert-alias
- GIVEN OP=deploy THEN: build + upload run; resolve-deploy-id skipped
- GIVEN OP=promote THEN: build + upload skipped; resolve-deploy-id runs
- GIVEN OP=rollback THEN: build + upload skipped; resolve-deploy-id runs; ROLLBACK_TO required
- GIVEN smoke-test fails THEN revert-alias runs (when.evaluate: 'env.SMOKE_OK == "0"')
- GIVEN a lint tool (woodpecker-cli lint) THEN the file lints clean

#### Verification

```bash
cd /Users/mrugesh/DEV/fCC/infra && \
  woodpecker-cli lint docs/templates/woodpecker-static-deploy.yaml 2>&1 || \
  python3 -c 'import yaml; yaml.safe_load(open("docs/templates/woodpecker-static-deploy.yaml"))'
```

**Expected output:** woodpecker-cli lint reports clean, OR the YAML parses without errors if lint tool not available.

#### Constraints

- Must match D24 ordering EXACTLY — out-of-order steps defeat the atomic promote guarantee
- Alias write uses `--header-upload "Cache-Control: no-store"` AND all 5 `x-amz-meta-*` fields (§4.4.3)
- `purge-cache-pre` runs BEFORE `write-alias`, not after
- Use repo-scoped secrets (`from_secret: r2_access_key_id` — resolved by Woodpecker from repo scope per D22)
- `smoke-test` has `failure: ignore` so `revert-alias` can fire
- `revert-alias` exits non-zero on revert to mark the pipeline failed

#### Agent Prompt

````
You are implementing Task 21: .woodpecker/deploy.yaml pipeline template.

## Repo and CWD

Work in the infra repo: `/Users/mrugesh/DEV/fCC/infra`. The template itself is a reference artifact stored under `docs/templates/` for v1 (the `universe-templates` repo doesn't exist yet).

## Your Task

Author the canonical Woodpecker pipeline that every static constellation copies into its own `.woodpecker/deploy.yaml`. Step order is **critical** per D24 (RFC §4.6.2): verify → snapshot → purge-pre → write-alias → smoke → revert. The full YAML is in RFC §4.6.2 lines 886-1213.

### Step 1: Read the RFC section
Open `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md` and read §4.6.2 end-to-end (lines 886-1233). Every step, every env var, every `when.evaluate` gate is specified.

### Step 2: Create the template file
Create `docs/templates/woodpecker-static-deploy.yaml`. Copy the YAML from RFC §4.6.2 verbatim, starting at `when:` (line 889) and ending at the closing `}` (line 1198). This file is what constellation repos will copy into their own `.woodpecker/deploy.yaml`.

Add a header comment at the top explaining:

```yaml
# Canonical Woodpecker pipeline for Universe static constellations.
# COPY this file into your constellation repo at .woodpecker/deploy.yaml.
# DO NOT MODIFY unless you have a reason to diverge from the RFC-specified flow.
# Ref: /Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md §4.6.2 (D24).
#
# Steps (D24 ordering):
#   compute-deploy-id → build → upload → resolve-deploy-id
#   → verify-deploy → snapshot-previous-alias → purge-cache-pre
#   → write-alias → smoke-test → revert-alias
#
# Variables (set by Woodpecker API or defaults):
#   OP            deploy|promote|rollback (default: deploy)
#   DEPLOY_TARGET preview|production (default: preview)
#   ROLLBACK_TO   required when OP=rollback; target deploy ID
#
# Secrets expected (repo-scope per D22):
#   r2_access_key_id, r2_secret_access_key, r2_endpoint, r2_bucket
#   cf_api_token, cf_zone_id
```

### Step 3: Validate YAML structure
```bash
python3 -c '
import yaml
with open("docs/templates/woodpecker-static-deploy.yaml") as f:
    doc = yaml.safe_load(f)
assert "steps" in doc, "missing steps"
step_names = [list(s.keys())[0] if isinstance(s, dict) else s for s in doc["steps"]] if isinstance(doc["steps"], list) else list(doc["steps"].keys())
expected = ["compute-deploy-id", "build", "upload", "resolve-deploy-id", "verify-deploy", "snapshot-previous-alias", "purge-cache-pre", "write-alias", "smoke-test", "revert-alias"]
print("step names:", step_names)
for e in expected:
    assert e in step_names, f"missing step: {e}"
print("OK: all 10 steps present in expected order")
'
```

Expected: "OK: all 10 steps present in expected order"

### Step 4: Anti-check — confirm D24 ordering
```bash
# purge-cache-pre MUST appear BEFORE write-alias (not after)
grep -nE '^\s*(purge-cache-pre|write-alias):' docs/templates/woodpecker-static-deploy.yaml
```
The purge-cache-pre line number MUST be lower than the write-alias line number. If not, the file is in the wrong order.

### Step 5: Alias-write audit metadata
Confirm the write-alias step sets all 5 `x-amz-meta-*` fields per RFC §4.4.3 (or add them if missing):
- x-amz-meta-pipeline-id
- x-amz-meta-git-sha
- x-amz-meta-op
- x-amz-meta-actor
- x-amz-meta-timestamp

If the RFC YAML omits any of these, add `--header-upload "x-amz-meta-*: ..."` flags to the rclone rcat call in write-alias.

### Step 6: Lint with woodpecker-cli if available
```bash
command -v woodpecker-cli && woodpecker-cli lint docs/templates/woodpecker-static-deploy.yaml || echo "woodpecker-cli not installed; skipping lint"
```

## Files

- Create: `docs/templates/woodpecker-static-deploy.yaml`

## Acceptance Criteria

- YAML parses without errors
- All 10 step names present in the D24 order
- `purge-cache-pre` line number < `write-alias` line number
- Header comment documents copy-target + variables + secrets
- All 5 audit metadata fields on write-alias + revert-alias

## Context

This pipeline is the canonical deploy path for all static constellations. The order matters: writing the alias BEFORE smoke-test (the old pattern) meant a failed smoke left production broken. The D24 ordering (snapshot → purge → write → smoke → revert) ensures failed promotes auto-revert.

## When Stuck

If `when.evaluate` syntax is unfamiliar, read https://woodpecker-ci.org/docs/usage/workflow-syntax#evaluate-condition. If you're unsure about `failure: ignore` semantics (used on smoke-test to allow revert to fire), read https://woodpecker-ci.org/docs/usage/workflow-syntax#failure-ignore.

## Constraints

- Step ordering MUST match D24 exactly
- `smoke-test` MUST have `failure: ignore` so `revert-alias` can run on failure
- `revert-alias` MUST exit non-zero on actual revert so pipeline shows failure
- Do NOT inline real secret values
- Do NOT reference org-scope secrets (only repo-scope — D22)
- Do NOT run git write commands
````

**Depends on:** Task 11 (per-site secrets must exist for the template to reference)

---

### Task 22 [M]: Cleanup cron Windmill flow

**Traceability:** Implements R16, D28 (TOCTOU fix) | Constrained by §4.9.1
**Files:**

- Create: `/Users/mrugesh/DEV/fCC-U/windmill/f/static/cleanup_old_deploys.ts`
- Create: `/Users/mrugesh/DEV/fCC-U/windmill/f/static/cleanup_old_deploys.yaml` (flow metadata — cron `0 4 * * *`)
- Create: `/Users/mrugesh/DEV/fCC-U/windmill/f/static/cleanup_old_deploys.test.ts`

#### Context

Daily cleanup per RFC §4.9.1. Implements R2 lock + 1-hour grace window + per-site alias re-check immediately before delete (D28 TOCTOU fix). Dry-run mode on initial deploy.

#### Acceptance Criteria

- GIVEN the flow with `dry_run=true` WHEN run THEN computes the delete list but does NOT delete
- GIVEN `dry_run=false` AND no other instance holds the lock WHEN run THEN acquires lock, processes each site, releases lock
- GIVEN an active lock held by another instance THEN skips and reports
- GIVEN a deploy is currently aliased (production or preview) THEN it is NEVER deleted
- GIVEN a deploy modified < 1 hour ago THEN it is NEVER deleted, regardless of age
- GIVEN a deploy > 7 days old + not aliased + > 1 hour old THEN deleted
- GIVEN alias flip between initial read and final pre-delete check THEN the deploy is skipped (race closed)
- Tests mock R2 + assert correct delete set and lock behavior

#### Verification

```bash
cd /Users/mrugesh/DEV/fCC-U/windmill && deno test f/static/cleanup_old_deploys.test.ts
```

**Expected output:** tests pass.

#### Constraints

- Follow pseudocode in RFC §4.9.1 exactly
- Lock key: `gxy-cassiopeia-1/_ops/cleanup.lock` with expiresAt
- First production deploy MUST be `dry_run=true`

#### Agent Prompt

````
You are implementing Task 22: Cleanup cron Windmill flow.

## Repo and CWD

Work in the Windmill repo: `/Users/mrugesh/DEV/fCC-U/windmill`.

## Your Task

Per RFC §4.9.1 (D28), a daily cron flow that deletes deploys > 7 days old not referenced by any alias. Implements the R2 lock + 1-hour grace + pre-delete alias re-check safeguards.

Read `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md` §4.9.1 in full before starting — the pseudocode there is the authoritative spec.

### Step 1: Write failing tests
Create `f/static/cleanup_old_deploys.test.ts`:

```typescript
import {assertEquals} from "https://deno.land/std/assert/mod.ts";
import {cleanupOldDeploys} from "./cleanup_old_deploys.ts";

// Mock R2 helpers
function mockR2(state: Map<string, {content?: string; mtime: number}>) {
  return {
    lsSites: async () => Array.from(new Set(Array.from(state.keys()).map(k => k.split("/")[0]))),
    readAlias: async (site: string, name: string) => state.get(`${site}/${name}`)?.content ?? null,
    listDeploys: async (site: string) => Array.from(state.keys())
      .filter(k => k.startsWith(`${site}/deploys/`))
      .map(k => ({id: k.split("/")[2], mtime: state.get(k)!.mtime})),
    deletePrefix: async (prefix: string) => {
      for (const k of Array.from(state.keys())) if (k.startsWith(prefix)) state.delete(k);
    },
    tryLock: async () => true,
    releaseLock: async () => {},
  };
}

Deno.test("keeps deploys referenced by aliases", async () => {
  const now = Date.now();
  const state = new Map([
    ["site-a/deploys/old1/", {mtime: now - 10 * 86400_000}],
    ["site-a/production", {content: "old1", mtime: now}],
  ]);
  const r2 = mockR2(state);
  await cleanupOldDeploys({r2, dryRun: false});
  assertEquals(state.has("site-a/deploys/old1/"), true); // aliased; keep
});

Deno.test("keeps last 3 deploys regardless of age", async () => {
  const now = Date.now();
  const state = new Map([
    ["site-a/deploys/d1/", {mtime: now - 100 * 86400_000}],
    ["site-a/deploys/d2/", {mtime: now - 99 * 86400_000}],
    ["site-a/deploys/d3/", {mtime: now - 98 * 86400_000}],
    ["site-a/deploys/d4/", {mtime: now - 97 * 86400_000}],
    ["site-a/production", {content: "d4", mtime: now}],
  ]);
  const r2 = mockR2(state);
  await cleanupOldDeploys({r2, dryRun: false});
  // d4 aliased → keep. Last 3 → d4,d3,d2. d1 is not in keep set AND > 7 days → delete.
  assertEquals(state.has("site-a/deploys/d1/"), false);
  assertEquals(state.has("site-a/deploys/d2/"), true);
  assertEquals(state.has("site-a/deploys/d3/"), true);
});

Deno.test("keeps deploys modified in last 1 hour (grace window)", async () => {
  const now = Date.now();
  const state = new Map([
    ["site-a/deploys/fresh/", {mtime: now - 30 * 60 * 1000}], // 30 min ago
    ["site-a/deploys/d2/", {mtime: now - 2 * 86400_000}],
    ["site-a/deploys/d3/", {mtime: now - 2 * 86400_000}],
    ["site-a/deploys/d4/", {mtime: now - 2 * 86400_000}],
    ["site-a/production", {content: "d4", mtime: now}],
  ]);
  const r2 = mockR2(state);
  await cleanupOldDeploys({r2, dryRun: false});
  assertEquals(state.has("site-a/deploys/fresh/"), true); // grace window
});

Deno.test("skips delete if alias flips during cron (TOCTOU re-check)", async () => {
  const now = Date.now();
  const state = new Map([
    ["site-a/deploys/target/", {mtime: now - 10 * 86400_000}],
    ["site-a/production", {content: "other", mtime: now}],
  ]);
  const r2 = mockR2(state);
  // Simulate alias flip to "target" right before final delete:
  let readCount = 0;
  const origReadAlias = r2.readAlias;
  r2.readAlias = async (site, name) => {
    readCount++;
    if (readCount > 2 && name === "production") return "target"; // flip on third call
    return origReadAlias(site, name);
  };
  await cleanupOldDeploys({r2, dryRun: false});
  assertEquals(state.has("site-a/deploys/target/"), true); // skipped due to TOCTOU re-check
});

Deno.test("dryRun does not delete", async () => {
  const now = Date.now();
  const state = new Map([
    ["site-a/deploys/old/", {mtime: now - 10 * 86400_000}],
    ["site-a/production", {content: "other", mtime: now}],
  ]);
  const r2 = mockR2(state);
  const report = await cleanupOldDeploys({r2, dryRun: true});
  assertEquals(state.has("site-a/deploys/old/"), true);
  assertEquals(report.pending.length, 1);
});

Deno.test("aborts if lock unavailable", async () => {
  const state = new Map();
  const r2 = mockR2(state);
  r2.tryLock = async () => false;
  const report = await cleanupOldDeploys({r2, dryRun: false});
  assertEquals(report.skipped, "cleanup already running");
});
```

Run: `cd /Users/mrugesh/DEV/fCC-U/windmill && deno test f/static/cleanup_old_deploys.test.ts` — tests FAIL.

### Step 2: Implement f/static/cleanup_old_deploys.ts
Match the pseudocode in RFC §4.9.1 lines 1580-1639 exactly. Interface:

```typescript
export interface R2Ops {
  lsSites(): Promise<string[]>;
  readAlias(site: string, name: string): Promise<string | null>;
  listDeploys(site: string): Promise<{id: string; mtime: number}[]>;
  deletePrefix(prefix: string): Promise<void>;
  tryLock(instanceId: string, ttlSec: number): Promise<boolean>;
  releaseLock(instanceId: string): Promise<void>;
}

export interface CleanupReport {
  sitesProcessed: number;
  deploysRetained: number;
  deploysDeleted: number;
  bytesFreed: number;
  pending?: {site: string; deployId: string; mtime: number}[];
  skipped?: string;
}

export async function cleanupOldDeploys(opts: {
  r2: R2Ops;
  dryRun: boolean;
  graceMs?: number;
  retentionDays?: number;
  recentKeep?: number;
  instanceId?: string;
}): Promise<CleanupReport> { /* ... */ }
```

Real R2Ops implementation wraps rclone CLI (or Deno S3 SDK). Use rclone subprocess for consistency with pipeline steps.

### Step 3: Flow metadata
`f/static/cleanup_old_deploys.yaml`:

```yaml
summary: Cleanup old deploys from gxy-cassiopeia-1
description: |
  Daily cron. Deletes R2 deploy prefixes older than 7 days that are not
  referenced by any alias, not among the 3 most recent, and not modified
  in the last hour (grace window). Uses an R2 lock object to prevent
  concurrent runs. First production run MUST be dry_run=true.
  Ref: RFC gxy-cassiopeia §4.9.1 (D28).
schedule:
  cron: "0 4 * * *"  # Daily 04:00 UTC
schema:
  type: object
  properties:
    dry_run:
      type: boolean
      default: true
```

### Step 4: Verify
```bash
cd /Users/mrugesh/DEV/fCC-U/windmill
deno test f/static/cleanup_old_deploys.test.ts
```

## Files

- Create: `f/static/cleanup_old_deploys.ts`
- Create: `f/static/cleanup_old_deploys.yaml`
- Create: `f/static/cleanup_old_deploys.test.ts`

## Acceptance Criteria

- All tests pass
- Dry-run returns `pending` list without deleting
- TOCTOU re-check blocks delete when alias flips mid-cron
- Lock unavailable → skips cleanly
- First production run is dry_run=true (enforced by schema default)

## Context

This cron is the only way R2 storage stays bounded over time. Without the TOCTOU safeguards, a promote during cron could delete the just-promoted deploy. With them, the worst case is a skipped cleanup cycle — safe.

## When Stuck

rclone's `mtime` semantics for S3 objects rely on server-side timestamps. If mtime is not reliable for individual deploy-prefix roots, compute from the `_deploy-meta.json` `timestamp` field instead (fallback).

## Constraints

- TDD
- R2 lock + grace + pre-delete re-check are MANDATORY safeguards
- dry_run=true default
- Do NOT touch other Windmill flows
- Do NOT run git write commands
````

**Depends on:** Task 12 (R2 bucket exists)

---

### Task 23 [M]: Cutover preflight script + CF DNS tooling + justfile recipes

**Traceability:** Implements D25 (CRITICAL #4 fix) | Constrained by §6.8.1
**Files:**

- Create: `/Users/mrugesh/DEV/fCC/infra/scripts/cutover-preflight.sh`
- Create: `/Users/mrugesh/DEV/fCC/infra/scripts/cf-dns-export.sh`
- Create: `/Users/mrugesh/DEV/fCC/infra/scripts/cf-dns-cutover.sh`
- Create: `/Users/mrugesh/DEV/fCC/infra/scripts/cf-dns-restore.sh`
- Modify: `/Users/mrugesh/DEV/fCC/infra/justfile` (add recipes: `cutover-preflight`, `cf-dns-export`, `cf-dns-cutover`, `cf-dns-restore`)

#### Context

Machine-checked preflight for Phase 6. Per RFC §6.8.1: enumerates sites in gxy-static-1, runs 8 checks per site, exits non-zero on any failure. Companion scripts for DNS export/cutover/restore enable the cutover execution itself to be scripted (with safeguards).

#### Acceptance Criteria

- GIVEN the preflight script WHEN run in an env with both R2 buckets accessible THEN produces a per-site matrix and exits 0 only if all checks pass
- GIVEN any site missing from gxy-cassiopeia-1 THEN script exits non-zero with a clear error
- GIVEN `just cf-dns-export freecode.camp` THEN writes JSON snapshot of records to stdout
- GIVEN `just cf-dns-cutover freecode.camp gxy-cassiopeia` THEN updates `*`, `@`, `www` A records to cassiopeia node IPs
- GIVEN `just cf-dns-restore <snapshot.json>` THEN restores records from the snapshot
- GIVEN the scripts WHEN linted with shellcheck THEN no warnings

#### Verification

```bash
cd /Users/mrugesh/DEV/fCC/infra && \
  shellcheck scripts/cutover-preflight.sh scripts/cf-dns-*.sh && \
  just --unstable --fmt --check
```

**Expected output:** exit 0.

#### Constraints

- CF API calls use `CF_API_TOKEN` from env (read via direnv)
- Preflight is read-only — never mutates state
- cf-dns-cutover MUST take a dry-run flag (`--dry-run` default to safe)
- All scripts use `set -euo pipefail`

#### Agent Prompt

````
You are implementing Task 23: Cutover preflight script + CF DNS tooling.

## Repo and CWD

Work in the infra repo: `/Users/mrugesh/DEV/fCC/infra`.

## Your Task

Per RFC §6.8.1 (D25): a shell script that enumerates sites in gxy-static-1 and runs 8 checks per site before the DNS cutover. Plus CF DNS export/cutover/restore scripts for the operator to run the cutover itself.

### Step 1: scripts/cutover-preflight.sh
```bash
#!/usr/bin/env bash
# DNS cutover preflight per RFC gxy-cassiopeia §6.8.1 (D25).
# Enumerates sites in gxy-static-1, runs 8 checks per site against gxy-cassiopeia-1.
# Exits non-zero on ANY site failing ANY check — cutover must not proceed.

set -euo pipefail

: "${STATIC_BUCKET:=gxy-static-1}"
: "${CASSIOPEIA_BUCKET:=gxy-cassiopeia-1}"
: "${CASSIOPEIA_NODE_IP:?Set CASSIOPEIA_NODE_IP to any gxy-cassiopeia node public IP}"
: "${WOODPECKER_ADMIN_TOKEN:?Set WOODPECKER_ADMIN_TOKEN}"
: "${WOODPECKER_ENDPOINT:?Set WOODPECKER_ENDPOINT}"

# Ensure rclone configured for both buckets (sourced from direnv).
rclone lsd "r2:${STATIC_BUCKET}" >/dev/null || { echo "cannot list $STATIC_BUCKET"; exit 2; }
rclone lsd "r2:${CASSIOPEIA_BUCKET}" >/dev/null || { echo "cannot list $CASSIOPEIA_BUCKET"; exit 2; }

# Enumerate sites (top-level prefixes) in gxy-static-1.
SITES=$(rclone lsf --dirs-only "r2:${STATIC_BUCKET}" | sed 's|/$||' | sort -u)
if [ -z "$SITES" ]; then echo "no sites in $STATIC_BUCKET — nothing to cutover"; exit 0; fi

FAIL=0
printf "%-50s | %s\n" "SITE" "STATUS"
printf -- "---------------------------------------------------\n"

for SITE in $SITES; do
  status="ok"
  # 1. exists in cassiopeia
  if ! rclone lsd "r2:${CASSIOPEIA_BUCKET}/${SITE}/deploys/" >/dev/null 2>&1; then
    status="fail:no-deploys-in-cassiopeia"; FAIL=1; printf "%-50s | %s\n" "$SITE" "$status"; continue
  fi
  # 2. production alias exists
  PROD=$(rclone cat "r2:${CASSIOPEIA_BUCKET}/${SITE}/production" 2>/dev/null | tr -d '[:space:]')
  if [ -z "$PROD" ]; then status="fail:no-production-alias"; FAIL=1; printf "%-50s | %s\n" "$SITE" "$status"; continue; fi
  # 3. alias value format
  if ! echo "$PROD" | grep -qE '^[A-Za-z0-9._-]{1,64}$'; then
    status="fail:alias-invalid-format($PROD)"; FAIL=1; printf "%-50s | %s\n" "$SITE" "$status"; continue
  fi
  # 4. alias target has index.html
  if ! rclone lsf "r2:${CASSIOPEIA_BUCKET}/${SITE}/deploys/${PROD}/index.html" >/dev/null 2>&1; then
    status="fail:alias-target-missing-index"; FAIL=1; printf "%-50s | %s\n" "$SITE" "$status"; continue
  fi
  # 5. HTTP 200 via cassiopeia origin
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" -H "Host: ${SITE}" "http://${CASSIOPEIA_NODE_IP}/")
  if [ "$HTTP_CODE" != "200" ]; then
    status="fail:origin-returned-$HTTP_CODE"; FAIL=1; printf "%-50s | %s\n" "$SITE" "$status"; continue
  fi
  # 6. preview alias optional check: if exists, must also return 200
  if rclone lsf "r2:${CASSIOPEIA_BUCKET}/${SITE}/preview" >/dev/null 2>&1; then
    # site is `<subdomain>.freecode.camp`; preview host is `<subdomain>--preview.freecode.camp`
    SUBDOMAIN="${SITE%%.*}"
    PREVIEW_HOST="${SUBDOMAIN}--preview.freecode.camp"
    PREVIEW_CODE=$(curl -o /dev/null -s -w "%{http_code}" -H "Host: ${PREVIEW_HOST}" "http://${CASSIOPEIA_NODE_IP}/")
    if [ "$PREVIEW_CODE" != "200" ]; then
      status="fail:preview-returned-$PREVIEW_CODE"; FAIL=1; printf "%-50s | %s\n" "$SITE" "$status"; continue
    fi
  fi
  # 7. Woodpecker repo registered — strip the trailing `.freecode.camp` to get repo name
  REPO_NAME="${SITE%%.*}"
  if ! curl -fsS -H "Authorization: Bearer ${WOODPECKER_ADMIN_TOKEN}" "${WOODPECKER_ENDPOINT}/api/repos/lookup/freeCodeCamp-Universe/${REPO_NAME}" >/dev/null 2>&1; then
    status="fail:woodpecker-repo-not-registered"; FAIL=1; printf "%-50s | %s\n" "$SITE" "$status"; continue
  fi
  # 8. Site name validation (no --, RFC-1123)
  if echo "$REPO_NAME" | grep -q -- '--'; then
    status="fail:site-name-contains-double-hyphen"; FAIL=1; printf "%-50s | %s\n" "$SITE" "$status"; continue
  fi
  printf "%-50s | %s\n" "$SITE" "$status"
done

if [ "$FAIL" = "1" ]; then
  echo ""
  echo "PREFLIGHT FAILED — fix the failing sites before cutover."
  exit 3
fi
echo ""
echo "PREFLIGHT OK — ready to proceed with cutover."
```

### Step 2: scripts/cf-dns-export.sh
```bash
#!/usr/bin/env bash
# Export current DNS records for a zone as JSON (for cutover snapshotting).
set -euo pipefail

ZONE="${1:?usage: cf-dns-export <zone-name>}"
: "${CF_API_TOKEN:?Set CF_API_TOKEN}"

ZONE_ID=$(curl -fsS -H "Authorization: Bearer ${CF_API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/zones?name=${ZONE}" | \
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["result"][0]["id"])')

curl -fsS -H "Authorization: Bearer ${CF_API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?per_page=200"
```

### Step 3: scripts/cf-dns-cutover.sh
```bash
#!/usr/bin/env bash
# Cutover `*`, `@`, `www` A records on a zone to a set of target IPs.
# Usage: cf-dns-cutover <zone> <target-ips-comma-sep> [--dry-run|--apply]
set -euo pipefail

ZONE="${1:?usage: cf-dns-cutover <zone> <ip1,ip2,...> [--dry-run|--apply]}"
IPS="${2:?missing target IPs (comma-separated)}"
MODE="${3:---dry-run}"

: "${CF_API_TOKEN:?Set CF_API_TOKEN}"

ZONE_ID=$(curl -fsS -H "Authorization: Bearer ${CF_API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/zones?name=${ZONE}" | \
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["result"][0]["id"])')

IFS=, read -ra IP_ARR <<< "$IPS"
for NAME in "@" "www" "*"; do
  # Fetch existing records for this name
  EXISTING=$(curl -fsS -H "Authorization: Bearer ${CF_API_TOKEN}" \
    "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${NAME}.${ZONE}&type=A")
  # Delete existing A records (idempotent on re-run)
  IDS=$(echo "$EXISTING" | python3 -c 'import json,sys; [print(r["id"]) for r in json.load(sys.stdin)["result"]]')
  for ID in $IDS; do
    if [ "$MODE" = "--apply" ]; then
      curl -fsS -X DELETE -H "Authorization: Bearer ${CF_API_TOKEN}" \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${ID}" >/dev/null
      echo "deleted $NAME A record $ID"
    else
      echo "[dry-run] would delete $NAME A record $ID"
    fi
  done
  # Create new A records for each IP
  for IP in "${IP_ARR[@]}"; do
    if [ "$MODE" = "--apply" ]; then
      curl -fsS -X POST -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"${NAME}\",\"content\":\"${IP}\",\"ttl\":60,\"proxied\":true}" \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" >/dev/null
      echo "created $NAME A $IP"
    else
      echo "[dry-run] would create $NAME A $IP"
    fi
  done
done

if [ "$MODE" = "--dry-run" ]; then echo ""; echo "dry-run complete — re-run with --apply to commit"; fi
```

### Step 4: scripts/cf-dns-restore.sh
```bash
#!/usr/bin/env bash
# Restore DNS records from a snapshot JSON file.
set -euo pipefail
SNAPSHOT="${1:?usage: cf-dns-restore <snapshot.json>}"
: "${CF_API_TOKEN:?Set CF_API_TOKEN}"
# Minimal: delete current A/@/www/*, then recreate from snapshot
# Implementation mirrors cf-dns-cutover but reads IPs from snapshot.
# For safety, only touch A records for '@', 'www', '*' (same scope as cutover).
python3 << 'EOF'
import json, os, sys, urllib.request, urllib.parse
snapshot = json.load(open(os.environ.get("SNAPSHOT", sys.argv[1])))
# ... parse records, delete matching, recreate — left as a structured implementation
EOF
```
(Implement the delete-then-recreate in a straightforward Python block. Keep to the same 3 names `@`, `www`, `*`.)

### Step 5: justfile recipes
Append to `justfile`:

```just
[group('cutover')]
cutover-preflight:
    bash scripts/cutover-preflight.sh

[group('cutover')]
cf-dns-export zone:
    bash scripts/cf-dns-export.sh {{zone}}

[group('cutover')]
cf-dns-cutover zone ips mode="--dry-run":
    bash scripts/cf-dns-cutover.sh {{zone}} {{ips}} {{mode}}

[group('cutover')]
cf-dns-restore snapshot:
    bash scripts/cf-dns-restore.sh {{snapshot}}
```

### Step 6: Lint
```bash
shellcheck scripts/cutover-preflight.sh scripts/cf-dns-*.sh
just --unstable --fmt --check
```

## Files

- Create: `scripts/cutover-preflight.sh`
- Create: `scripts/cf-dns-export.sh`
- Create: `scripts/cf-dns-cutover.sh`
- Create: `scripts/cf-dns-restore.sh`
- Modify: `justfile`

## Acceptance Criteria

- `shellcheck` clean on all 4 scripts
- `just --unstable --fmt --check` passes
- cutover-preflight exits non-zero on any site failing any check
- cf-dns-cutover defaults to `--dry-run`
- All scripts use `set -euo pipefail`

## Context

This tooling gates the DNS cutover. Without `just cutover-preflight` returning green, the operator cannot proceed. The scripts replace the "free-form checklist in a doc" failure mode (CRITICAL #4).

## When Stuck

If the CF API response schema has changed, `python3 -c` snippets may need adjustment. The Zone ID lookup endpoint is stable; individual record mutation endpoints sometimes rev. Keep the scripts simple enough that a reader can debug them.

## Constraints

- Scripts must be idempotent (re-running produces same end state)
- cf-dns-cutover MUST default to dry-run; `--apply` is explicit
- NEVER run git write commands
- Do NOT apply to production in this task; creating the tooling is the scope
````

**Depends on:** Task 12 (R2 bucket reachable)

---

### Task 24 [M]: Cloudflare Notifications + Uptime Robot monitors

**Traceability:** Implements D31 (alerting floor) | Constrained by §10.3 Active alerts table
**Files:**

- Create: `/Users/mrugesh/DEV/fCC/infra/cloudflare/notifications.yaml`
- Create: `/Users/mrugesh/DEV/fCC/infra/uptime-robot/monitors.yaml`
- Create: `/Users/mrugesh/DEV/fCC/infra/scripts/cf-notifications-apply.sh`
- Create: `/Users/mrugesh/DEV/fCC/infra/scripts/uptime-robot-apply.sh`
- Modify: `/Users/mrugesh/DEV/fCC/infra/justfile` (add `cf-notifications-apply`, `uptime-robot-apply`)

#### Context

Zero-infrastructure alerting baseline per RFC §10.3 and D31. Cloudflare Notifications cover zone-level 5xx + origin error; Uptime Robot covers per-site uptime + Woodpecker API. Both are declaratively checked in to the repo and applied via script.

#### Acceptance Criteria

- GIVEN `cloudflare/notifications.yaml` THEN declares: zone 5xx > 1% for 5m, origin error rate > 5% for 5m, both notify platform-team email + Google Chat webhook
- GIVEN `uptime-robot/monitors.yaml` THEN declares one monitor per site + one for `woodpecker.freecodecamp.net/api/healthz`
- GIVEN `just cf-notifications-apply` WHEN run with `CF_API_TOKEN` THEN creates or updates notifications via CF API
- GIVEN `just uptime-robot-apply` WHEN run with `UPTIME_ROBOT_API_KEY` THEN creates or updates monitors via Uptime Robot API
- Scripts lint cleanly with shellcheck

#### Verification

```bash
shellcheck scripts/cf-notifications-apply.sh scripts/uptime-robot-apply.sh && \
  yamllint cloudflare/notifications.yaml uptime-robot/monitors.yaml
```

**Expected output:** exit 0.

#### Constraints

- Use idempotent API patterns (create-or-update, not delete-then-create)
- Google Chat webhook URL is a secret; script reads from env
- Do NOT apply to production in this task — create tooling only; runbook documents the apply step

#### Agent Prompt

````
You are implementing Task 24: Cloudflare Notifications + Uptime Robot monitors.

## Repo and CWD

Work in the infra repo: `/Users/mrugesh/DEV/fCC/infra`.

## Your Task

Minimum viable alerting baseline per RFC §10.3 and D31. Declarative configs + apply scripts.

### Step 1: cloudflare/notifications.yaml
```yaml
# Cloudflare Notifications for freecode.camp zone.
# Applied via `just cf-notifications-apply`.
# Ref: RFC gxy-cassiopeia §10.3 (D31).

notifications:
  - name: "gxy-cassiopeia: zone 5xx rate spike"
    description: "Zone-level 5xx rate > 1% sustained for 5m"
    alert_type: "web_analytics_metrics_update"
    filters:
      - field: "zone"
        value: "freecode.camp"
      - field: "status"
        value: "5xx"
      - field: "threshold_percent"
        value: 1
      - field: "duration_minutes"
        value: 5
    mechanisms:
      email:
        - platform-team@freecodecamp.org
      webhooks:
        - name: google-chat-platform
          # URL stored as CF Notification Webhook configured out-of-band

  - name: "gxy-cassiopeia: origin error rate"
    description: "Origin error rate > 5% for 5m on freecode.camp zone"
    alert_type: "origin_monitoring"
    filters:
      - field: "zone"
        value: "freecode.camp"
      - field: "error_rate_percent"
        value: 5
      - field: "duration_minutes"
        value: 5
    mechanisms:
      email:
        - platform-team@freecodecamp.org
      webhooks:
        - name: google-chat-platform
```

(Note: CF Notifications API schema changes; verify against current docs at https://developers.cloudflare.com/notifications/. Treat the YAML as a declarative source-of-truth; the apply script translates to API calls.)

### Step 2: uptime-robot/monitors.yaml
```yaml
# Uptime Robot monitors for gxy-cassiopeia.
# Applied via `just uptime-robot-apply`.
# Ref: RFC gxy-cassiopeia §10.3 (D31).

monitors:
  # Woodpecker API health
  - name: "woodpecker-api-health"
    url: "https://woodpecker.freecodecamp.net/api/healthz"
    type: keyword_exists
    keyword: "ok"
    interval_seconds: 300
    alert_contacts:
      - platform-team-email
      - google-chat-webhook

  # Per-site monitors. Generated from a site list — scripts/uptime-robot-apply.sh
  # reads this file + a sites list (derived from gxy-cassiopeia-1 bucket)
  # and creates/updates a monitor per site.
  per_site_template:
    name_format: "static-{site}"
    url_format: "https://{site}/"
    type: keyword_exists
    keyword: "<html"
    interval_seconds: 300
    alert_contacts:
      - platform-team-email
      - google-chat-webhook
```

### Step 3: scripts/cf-notifications-apply.sh
```bash
#!/usr/bin/env bash
# Idempotent apply of Cloudflare Notifications from cloudflare/notifications.yaml.
# Uses CF Notifications API: https://api.cloudflare.com/client/v4/accounts/{acct}/alerting/v3/policies
set -euo pipefail
: "${CF_API_TOKEN:?Set CF_API_TOKEN}"
: "${CF_ACCOUNT_ID:?Set CF_ACCOUNT_ID}"

# Parse yaml → JSON; for each policy: GET current by name; if exists PUT (update) else POST.
python3 << 'PY'
import json, os, sys, urllib.request, urllib.parse, yaml

spec = yaml.safe_load(open("cloudflare/notifications.yaml"))
base = f"https://api.cloudflare.com/client/v4/accounts/{os.environ['CF_ACCOUNT_ID']}/alerting/v3/policies"
headers = {"Authorization": f"Bearer {os.environ['CF_API_TOKEN']}", "Content-Type": "application/json"}

def api(method, url, body=None):
    req = urllib.request.Request(url, method=method, headers=headers,
                                  data=json.dumps(body).encode() if body else None)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

current = api("GET", base)
by_name = {p["name"]: p for p in current.get("result", [])}

for n in spec["notifications"]:
    body = {
        "name": n["name"],
        "description": n.get("description", ""),
        "alert_type": n["alert_type"],
        "enabled": True,
        "filters": {f["field"]: [str(f["value"])] for f in n.get("filters", [])},
        "mechanisms": n.get("mechanisms", {}),
    }
    if n["name"] in by_name:
        pid = by_name[n["name"]]["id"]
        api("PUT", f"{base}/{pid}", body)
        print(f"updated: {n['name']}")
    else:
        api("POST", base, body)
        print(f"created: {n['name']}")
PY
```

### Step 4: scripts/uptime-robot-apply.sh
```bash
#!/usr/bin/env bash
# Idempotent apply of Uptime Robot monitors from uptime-robot/monitors.yaml.
# Adds a monitor per site from gxy-cassiopeia-1 bucket.
set -euo pipefail
: "${UPTIME_ROBOT_API_KEY:?Set UPTIME_ROBOT_API_KEY}"

# API: https://api.uptimerobot.com/v2/getMonitors, /newMonitor, /editMonitor
python3 << 'PY'
import json, os, sys, urllib.request, urllib.parse, yaml, subprocess

spec = yaml.safe_load(open("uptime-robot/monitors.yaml"))
api_key = os.environ["UPTIME_ROBOT_API_KEY"]

def api(endpoint, params):
    params = dict(params)
    params["api_key"] = api_key
    params["format"] = "json"
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(f"https://api.uptimerobot.com/v2/{endpoint}", data=data)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

current = api("getMonitors", {"limit": 50}).get("monitors", [])
by_name = {m["friendly_name"]: m for m in current}

# Static monitors from spec
for m in spec["monitors"]:
    payload = {
        "friendly_name": m["name"],
        "url": m["url"],
        "type": 2,  # keyword
        "keyword_value": m["keyword"],
        "interval": m["interval_seconds"],
    }
    if m["name"] in by_name:
        payload["id"] = by_name[m["name"]]["id"]
        api("editMonitor", payload)
        print(f"updated: {m['name']}")
    else:
        api("newMonitor", payload)
        print(f"created: {m['name']}")

# Per-site monitors: enumerate sites from R2 bucket (via rclone)
sites_bytes = subprocess.check_output(["rclone", "lsf", "--dirs-only", "r2:gxy-cassiopeia-1"])
sites = [s.rstrip("/") for s in sites_bytes.decode().splitlines() if s.strip()]

tmpl = spec["per_site_template"]
for site in sites:
    if not site.endswith(".freecode.camp"): continue
    name = tmpl["name_format"].format(site=site)
    payload = {
        "friendly_name": name,
        "url": tmpl["url_format"].format(site=site),
        "type": 2,
        "keyword_value": tmpl["keyword"],
        "interval": tmpl["interval_seconds"],
    }
    if name in by_name:
        payload["id"] = by_name[name]["id"]
        api("editMonitor", payload)
        print(f"updated: {name}")
    else:
        api("newMonitor", payload)
        print(f"created: {name}")
PY
```

### Step 5: justfile
Append:

```just
[group('monitoring')]
cf-notifications-apply:
    bash scripts/cf-notifications-apply.sh

[group('monitoring')]
uptime-robot-apply:
    bash scripts/uptime-robot-apply.sh
```

### Step 6: Lint
```bash
shellcheck scripts/cf-notifications-apply.sh scripts/uptime-robot-apply.sh
yamllint cloudflare/notifications.yaml uptime-robot/monitors.yaml
```

## Files

- Create: `cloudflare/notifications.yaml`
- Create: `uptime-robot/monitors.yaml`
- Create: `scripts/cf-notifications-apply.sh`
- Create: `scripts/uptime-robot-apply.sh`
- Modify: `justfile`

## Acceptance Criteria

- shellcheck clean
- yamllint clean
- Scripts are idempotent (re-run is a no-op or update, never duplicate creation)
- No apply to production in this task (create tooling only)

## Context

Without this, gxy-cassiopeia would launch with zero alerting (the exact failure mode §2 cites as motivation). This task closes WARNING #17.

## When Stuck

If CF Notifications API schema differs from the values shown, prefer the official docs. Uptime Robot's v2 API is stable but the `type` integers (1=HTTP, 2=keyword) are undocumented in some references — confirm via a GET first.

## Constraints

- shellcheck clean
- Idempotent apply
- Do NOT hardcode Google Chat webhook URL in yaml files — reference via env or CF-side config
- Do NOT run apply against production in this task
- Do NOT run git write commands
````

**Depends on:** None (can run anytime)

---

### Task 25 [M]: DNS cutover execution runbook + Post-cutover field notes

**Traceability:** Implements §6.8.2, §6.9 | Constrained by D26 (30-day gxy-static retention)
**Files:**

- Create: `/Users/mrugesh/DEV/fCC/infra/docs/runbooks/dns-cutover.md`
- Modify: `/Users/mrugesh/DEV/fCC-U/Universe/spike/field-notes/infra.md` (post-cutover entry)

#### Context

DNS cutover itself is an **operator action** (ClickOps + justfile-scripted). This task creates the runbook that guides the operator through §6.8.2 steps (announce → preflight → snapshot → cutover → watch → exit criterion). Also adds a template for the post-cutover field notes entry (capturing measured metrics).

#### Acceptance Criteria

- GIVEN the runbook THEN covers: announcement window, preflight gate, snapshot step, cutover command, monitoring checklist, rollback steps, exit criterion (15-min soak)
- GIVEN the field notes template THEN has sections for: actual DNS propagation time (fill during cutover), observed 5xx rate, any issues
- GIVEN the `gxy-static` decommission-window note THEN documents the 30-day minimum retention (D26)

#### Verification

```bash
markdownlint docs/runbooks/dns-cutover.md 2>&1 || echo "lint not available, manual review"
```

**Expected output:** no lint errors (if markdownlint available).

#### Constraints

- Runbook MUST include "halt if preflight fails" as an explicit gate
- Runbook MUST specify that no promotes or rollbacks happen during cutover window
- Field notes update is placed after the "Static stack drift from ADR-007" entry, not replacing it

#### Agent Prompt

````
You are implementing Task 25: DNS cutover runbook + post-cutover field notes template.

## Repos and CWDs

- Runbook in infra repo: `/Users/mrugesh/DEV/fCC/infra`
- Field notes in Universe repo: `/Users/mrugesh/DEV/fCC-U/Universe` (infra-team owns ONLY spike/field-notes/infra.md)

## Your Task

Operator-facing runbook for Phase 6 DNS cutover. Derived from RFC §6.8.2-6.9.

### Step 1: docs/runbooks/dns-cutover.md (infra repo)

```markdown
# DNS Cutover: gxy-static → gxy-cassiopeia

Phase 6 of the gxy-cassiopeia rollout. Moves `*.freecode.camp` (+ apex + www) from
gxy-static node IPs to gxy-cassiopeia node IPs. gxy-static stays live as the
rollback substrate for ≥ 30 days post-cutover (D26).

## Prerequisites (must ALL be green)

- [ ] Phase 4 complete: `just phase4-smoke` passed against gxy-cassiopeia
- [ ] Phase 5 complete: `@freecodecamp/universe-cli@0.4.0-beta.1` released
- [ ] All existing gxy-static sites re-deployed to gxy-cassiopeia-1
- [ ] `just cutover-preflight` returns green (no site failures)
- [ ] Cloudflare Notifications + Uptime Robot monitors applied (`just cf-notifications-apply && just uptime-robot-apply`)
- [ ] Platform team + staff announce window (1 hour quiet — no promotes/deploys)

## Execution

### 1. Snapshot current DNS

```bash
cd /Users/mrugesh/DEV/fCC/infra
just cf-dns-export freecode.camp > /tmp/cutover-dns-pre-$(date -u +%Y%m%d-%H%M).json
```

Store this file safely — it is the rollback input.

### 2. Preflight gate

```bash
export CASSIOPEIA_NODE_IP=<one gxy-cassiopeia node IP>
just cutover-preflight
```

**Must exit 0.** Any site failure halts cutover. Fix the failing sites, re-deploy, re-run preflight.

### 3. Dry-run cutover

```bash
CASSIOPEIA_IPS="<ip1>,<ip2>,<ip3>"  # all 3 gxy-cassiopeia node IPs
just cf-dns-cutover freecode.camp "$CASSIOPEIA_IPS" --dry-run
```

Review the printed plan. Confirm: 9 records (3 names × 3 IPs) would be created; old gxy-static records would be deleted.

### 4. Apply cutover

```bash
just cf-dns-cutover freecode.camp "$CASSIOPEIA_IPS" --apply
```

### 5. Watch traffic shift

Open three terminals:

```bash
# Terminal 1: gxy-cassiopeia caddy logs
kubectl --context gxy-cassiopeia -n caddy logs -l app.kubernetes.io/name=caddy -f

# Terminal 2: gxy-static caddy logs (expect traffic to taper)
kubectl --context gxy-static -n caddy logs -l app.kubernetes.io/name=caddy -f

# Terminal 3: Cloudflare dashboard
# Open https://dash.cloudflare.com/?account=<acct>/freecode.camp/analytics/traffic
```

Watch for:

- Caddy pods on cassiopeia showing access log lines for real sites (not just test)
- 5xx rate on CF zone stays < 0.5%
- Origin error rate on CF stays < 1%

### 6. Soak 15 minutes

If all indicators stay green for 15 minutes, proceed. If any spike:

```bash
# IMMEDIATE ROLLBACK
just cf-dns-restore /tmp/cutover-dns-pre-<timestamp>.json
```

DNS revert for proxied records is typically < 60s; verify with `dig`. Preserve pod logs from cassiopeia for postmortem before doing anything remediation-y.

## Exit criteria (all must hold for 15 consecutive minutes)

- [ ] CF zone 5xx rate < 0.5%
- [ ] Origin error rate < 1%
- [ ] Every site in preflight matrix returns 200 on canonical URL
- [ ] Apex + www → 302 redirect to freecodecamp.org
- [ ] Caddy pod memory < 50% of limit

## Post-cutover

1. Record measured DNS revert time (test by flipping back a non-production record earlier — document in field notes)
2. Update field notes (`~/DEV/fCC-U/Universe/spike/field-notes/infra.md`)
3. Start 30-day soak window (D26)
4. Set calendar reminder for day 30: user-led decision on gxy-static decommission

## Rollback budget

The 30-day window (D26) means if a latent regression surfaces at day 5, 15, or 29, DNS revert still has a live gxy-static to fall back to. Do NOT decommission gxy-static before day 30 under any circumstance.
```

### Step 2: Post-cutover field notes entry (Universe repo — infra team owns infra.md only)

Append to `/Users/mrugesh/DEV/fCC-U/Universe/spike/field-notes/infra.md` under "Operational Findings" a new subsection (to be filled by the operator at cutover time — this task creates the template):

```markdown
### Cutover to gxy-cassiopeia (FILL AT CUTOVER TIME)

**Date:** <YYYY-MM-DD HH:MM UTC>
**Operator:** <name>
**DNS revert measured time:** <N seconds> (tested during Phase 4 on cutover-test.freecode.camp)
**Preflight output:** <link or paste of `just cutover-preflight` output>
**Cutover snapshot file:** /tmp/cutover-dns-pre-<timestamp>.json (moved to infra-secrets after cutover)
**Sites cut over:** <count>
**Observed 5xx rate during 15-min soak:** <N%>
**Incidents during cutover:** <none OR description + resolution>
**gxy-static decommission scheduled:** <YYYY-MM-DD, day 30+>

Notes: <free-form ops observations>
```

Make this template clearly marked "FILL AT CUTOVER TIME" so a future reader knows the entry is authoritative only after it is filled.

### Step 3: Cross-reference in FLIGHT-MANUAL
Ensure `docs/FLIGHT-MANUAL.md` links to this runbook in the cutover section (this cross-linking is Task 26's job — flag if Task 26 is already done).

### Step 4: Lint
```bash
markdownlint docs/runbooks/dns-cutover.md 2>&1 || echo "markdownlint not installed; manual review"
```

## Files

- Create (infra repo): `docs/runbooks/dns-cutover.md`
- Modify (Universe repo): `spike/field-notes/infra.md` — add the cutover template subsection

## Acceptance Criteria

- Runbook covers prerequisites, execution, watch, rollback, exit criteria, post-cutover
- Preflight gate is explicit ("must exit 0" — halt if not)
- `--dry-run` THEN `--apply` sequence documented; never `--apply` first
- Field notes template is clearly marked "FILL AT CUTOVER TIME"
- Runbook uses the justfile recipes from Task 23 (no raw curl in operator's path)

## Context

DNS cutover is the most destructive step in this RFC. The runbook prevents human error at the worst possible moment. The 30-day soak + alive gxy-static (D26) are the safety net — this runbook reinforces that.

## When Stuck

If `markdownlint` is not available, manual review is acceptable. If the Universe repo path doesn't match `/Users/mrugesh/DEV/fCC-U/Universe/`, check `~/DEV/fCC/infra/CLAUDE.md` for the doc index and correct the path.

## Constraints

- Do NOT modify Universe ADRs or spike-plan.md (infra team doesn't own them — only the field notes)
- Do NOT execute an actual cutover in this task
- Do NOT run git write commands
````

**Depends on:** Task 23

---

### Task 26 [S]: Migration constraint docs update (FLIGHT-MANUAL)

**Traceability:** Documentation, §6.10 rollback plan
**Files:**

- Modify: `/Users/mrugesh/DEV/fCC/infra/docs/FLIGHT-MANUAL.md`

#### Context

Add a new "gxy-cassiopeia" rebuild section to the FLIGHT-MANUAL so the doomsday rebuild doc covers the new galaxy end-to-end. Cross-references all runbooks created by Tasks 06, 09, 10, 11, 12, 15, 23, 25.

#### Acceptance Criteria

- GIVEN the updated FLIGHT-MANUAL THEN a new section for gxy-cassiopeia + gxy-launchbase listing phases 0-7
- GIVEN each phase THEN references the relevant runbook file(s)
- GIVEN the existing gxy-static and gxy-management sections THEN unchanged (those stay as-is)

#### Verification

```bash
markdownlint docs/FLIGHT-MANUAL.md 2>&1 | head -20
```

**Expected output:** no errors (or same as baseline pre-edit).

#### Constraints

- Do NOT remove existing sections
- Keep the doomsday-rebuild tone (every step to stand up from zero)

#### Agent Prompt

````
You are implementing Task 26: Update FLIGHT-MANUAL for gxy-cassiopeia + gxy-launchbase.

## Repo and CWD

Work in the infra repo: `/Users/mrugesh/DEV/fCC/infra`.

## Your Task

Extend `docs/FLIGHT-MANUAL.md` (the doomsday rebuild doc) with a gxy-cassiopeia + gxy-launchbase section. Every phase from Task 05 onward must be recoverable from this manual with no external context.

### Step 1: Read the current FLIGHT-MANUAL
- `docs/FLIGHT-MANUAL.md` — understand the existing tone, depth, and structure.
- The existing gxy-static + gxy-management sections are the template for the new sections' style.

### Step 2: Add gxy-launchbase + gxy-cassiopeia sections
After the existing cluster sections (or in a logical position — use the TOC of the existing file to decide), add:

```markdown
## gxy-launchbase (CI galaxy, 3× DO s-4vcpu-8gb-amd FRA1 — Hetzner migration post-M5)

### Rebuild from zero

1. **Provision 3× s-4vcpu-8gb-amd in DO FRA1** via `doctl` CLI or UI. Tag: `_gxy-launchbase-k3s`. User data: `cloud-init/k3s-node.yaml`. SSH key: platform-team.
2. **Inventory**: verify `ansible -i ansible/inventory/digitalocean.yml gxy_launchbase_k3s -m ping` reaches all 3 nodes.
3. **Bootstrap k3s**: `just play k3s--bootstrap -e "target_hosts=gxy_launchbase_k3s"`.
4. **CNPG operator**: `just helm-upgrade cnpg-operator` (k3s/gxy-launchbase/apps/cnpg-operator/).
5. **Woodpecker postgres**: `kubectl apply -f k3s/gxy-launchbase/apps/woodpecker/manifests/postgres-cluster.yaml`.
6. **Woodpecker secrets**: decrypt `~/DEV/fCC/infra-secrets/gxy-launchbase/woodpecker-github-oauth.env.enc` → apply as Secret `woodpecker-github-oauth` (see `docs/runbooks/woodpecker-oauth-app.md` for OAuth app creation).
7. **Woodpecker chart**: `just helm-upgrade woodpecker`.
8. **Networking**: `kubectl apply -f k3s/gxy-launchbase/apps/woodpecker/manifests/{httproute,cilium-netpol}.yaml`.
9. **DNS**: Cloudflare record `woodpecker.freecodecamp.net` → all 3 gxy-launchbase node IPs, proxied.
10. **Cloudflare Access**: per `docs/runbooks/woodpecker-cf-access.md`.
11. **Per-site R2 secret provisioning**: Windmill flow `f/static/provision_site_r2_credentials` (see [windmill repo](../../windmill) for definition).

### Routine operations

- `just cnpg-restore-test gxy-launchbase woodpecker` — monthly restore drill (RFC D21).
- `woodpecker-cli repo secret ls --repository freeCodeCamp-Universe/<site>` — inspect per-site secrets.
- Scale agents: edit `WOODPECKER_MAX_WORKFLOWS` in `k3s/gxy-launchbase/apps/woodpecker/values.yaml`.

## gxy-cassiopeia (static-serving galaxy, 3× DO s-4vcpu-8gb-amd FRA1)

### Rebuild from zero

1. **Provision 3× s-4vcpu-8gb-amd in DO FRA1** (ClickOps or `tofu apply` when imported).
2. **Bootstrap k3s**: `just play k3s--bootstrap -e "target_hosts=gxy_cassiopeia_k3s"`.
3. **R2 bucket**: see `docs/runbooks/r2-bucket-provision.md` (gxy-cassiopeia-1, versioning enabled).
4. **Caddy image**: latest pushed from Woodpecker pipeline `.woodpecker/caddy-s3-build.yaml`. Image tag in `k3s/gxy-cassiopeia/apps/caddy/values.production.yaml`.
5. **Caddy chart**: `just helm-upgrade caddy` (k3s/gxy-cassiopeia/apps/caddy/).
6. **Origin allow-list**: `kubectl apply -f k3s/gxy-cassiopeia/apps/caddy/manifests/origin-allowlist-netpol.yaml`.
7. **CF IP refresh cron**: Windmill flow `f/ops/refresh_cf_ips` — first run manually via `wmill job run`.
8. **Smoke test**: `just phase4-smoke` (needs GXY_CASSIOPEIA_NODE_IP export).
9. **DNS cutover**: see `docs/runbooks/dns-cutover.md`.
10. **Observability**: `just cf-notifications-apply && just uptime-robot-apply`.
11. **Cleanup cron**: Windmill flow `f/static/cleanup_old_deploys` — first production run MUST be dry_run=true.

### Routine operations

- Image bump: PR to `k3s/gxy-cassiopeia/apps/caddy/values.production.yaml` updating the tag → ArgoCD syncs.
- Add a new constellation: `just constellation-register <name>` → provisions R2 secrets → staff deploys via `universe deploy`.
- Investigate a 5xx spike: check CF dashboard → Caddy logs (`kubectl -n caddy logs -l app.kubernetes.io/name=caddy`) → R2 status page.
```

### Step 3: Cross-reference new runbooks
Ensure every runbook referenced above exists (they are created by Tasks 06, 09, 10, 11, 12, 15, 23, 25). Flag any missing.

### Step 4: Lint
```bash
markdownlint docs/FLIGHT-MANUAL.md 2>&1 | head -20
```

## Files

- Modify: `docs/FLIGHT-MANUAL.md`

## Acceptance Criteria

- New sections for gxy-launchbase + gxy-cassiopeia added without breaking existing sections
- All 11 steps per galaxy listed with references to the actual runbook file paths
- Existing sections (gxy-static, gxy-management) unchanged

## Context

The FLIGHT-MANUAL is the single doomsday rebuild doc. Without this task, a rebuild from a total loss would require reading the RFC + 10 runbooks — too much coordination under pressure.

## When Stuck

If the FLIGHT-MANUAL has a TOC that auto-generates from headers, ensure your heading levels match. If existing sections have an authorial "voice" (first-person singular, imperative, etc.), match it.

## Constraints

- Do NOT remove or modify existing sections (gxy-static, gxy-management)
- Every step must reference a runbook file path that exists after its corresponding task lands
- Do NOT run git write commands
````

**Depends on:** Task 25

---

## Parallelizable Work (can run concurrently after dependencies resolve)

### Task 27 [S]: Update infra field notes — Phase 0 readiness

**Traceability:** Documentation (infra team owns §6.2 Phase 0 exit)
**Files:**

- Modify: `/Users/mrugesh/DEV/fCC-U/Universe/spike/field-notes/infra.md`

#### Context

Add a field notes entry capturing Phase 0 (Caddy module + image) completion: image tag, build duration, any issues encountered. This is the companion doc-update to Task 05.

#### Acceptance Criteria

- GIVEN Task 05 shipped the image THEN a new dated field notes entry captures: image tag, caddy version, caddy-fs-s3 version, first GHCR push timestamp

#### Verification

Manual review — is the entry present, dated, and accurate?

#### Constraints

- Only infra field notes — do NOT touch ADRs or spike plan (Universe team owns those per the doc-ownership model)

#### Agent Prompt

````
You are implementing Task 27: Update infra field notes — Phase 0 readiness.

## Repo and CWD

Work in the Universe repo: `/Users/mrugesh/DEV/fCC-U/Universe`.

## Your Task

Add a post-Phase-0 entry to `spike/field-notes/infra.md` capturing the shipped Caddy custom module + image.

### Step 1: Read the current file
- `spike/field-notes/infra.md` — match existing format, use the same date convention as other entries.

### Step 2: Append a subsection under "Operational Findings"

Template (fill with actual values at task-run time):

```markdown
### Caddy r2_alias module + image landed (YYYY-MM-DD)

First build of the custom Caddy module + xcaddy image for gxy-cassiopeia.

- **Image tag:** `ghcr.io/freecodecamp-universe/caddy-s3:<YYYYMMDD>-<sha7>`
- **Caddy version:** 2.8.4 (pinned)
- **caddy-fs-s3 version:** v0.12.0 (pinned)
- **r2_alias module LOC:** <measured — `wc -l` on the module files>
- **Module unit test coverage:** <percentage from `go test -cover`>
- **Integration tests:** <pass/fail; note any flakes>
- **First GHCR push:** <ISO timestamp>
- **Image size:** <MB>

Drift from RFC estimate: <comment — RFC said ~300 LOC; actual was <N>>. <brief note on any unexpected complexity>.
```

### Step 3: Verify
Read the modified file; ensure the new section is in the right position and formatted consistently.

## Files

- Modify: `spike/field-notes/infra.md`

## Acceptance Criteria

- New subsection added under the correct top-level section
- Existing content unchanged
- All placeholder `<...>` values filled with actual measurements

## Context

Field notes are the infra team's operational narrative. Each phase gets its post-mortem-ish entry so future maintainers see what was measured vs. planned.

## Constraints

- Do NOT modify Universe ADRs, spike-plan.md, or windmill.md (only infra.md is infra-team-owned)
- Do NOT fabricate numbers; if a measurement is missing, write "<not measured>" and explain why
- Do NOT run git write commands
````

**Depends on:** Task 05

---

### Task 28 [S]: Update infra field notes — Phase 1-2 readiness

**Traceability:** Documentation (infra team owns Phase 1-2 exit)
**Files:**

- Modify: `/Users/mrugesh/DEV/fCC-U/Universe/spike/field-notes/infra.md`

#### Context

Post-M1 entry: gxy-launchbase provisioned + Woodpecker live. Captures: node specs actual, RAM/CPU at idle, Woodpecker version, GitHub OAuth scopes, whether CNPG restore drill passed.

#### Acceptance Criteria

- Field notes entry exists and covers the bulletized items above

#### Verification

Manual review.

#### Constraints

- Do NOT touch Universe ADRs or spike plan

#### Agent Prompt

````
You are implementing Task 28: Update infra field notes — Phase 1-2 readiness.

## Repo and CWD

Work in the Universe repo: `/Users/mrugesh/DEV/fCC-U/Universe`.

## Your Task

Append a post-M1 entry to `spike/field-notes/infra.md` covering gxy-launchbase provisioning + Woodpecker deploy outcomes.

### Step 1: Append subsection (template, fill at run time)

```markdown
### gxy-launchbase + Woodpecker landed (YYYY-MM-DD)

- **Node spec (actual):** DO s-4vcpu-8gb-amd × 3, FRA1, Ubuntu 24.04 (Hetzner migration deferred to post-M5)
- **Per-node idle RAM:** <kubectl top nodes at 1h post-bootstrap>
- **Per-node idle CPU:** <same>
- **DO tag → Ansible group parity check:** <tag `_gxy-launchbase-k3s` resolves to group `gxy_launchbase_k3s` via digitalocean.yml inventory — yes/no>
- **Woodpecker version deployed:** v3.13.<n>
- **Woodpecker server RAM (actual):** <MB>
- **Woodpecker agent RAM idle (actual):** <MB>
- **CNPG restore drill result:** <pass/fail/skipped and why>
- **GitHub OAuth app scopes granted:** `repo`, `read:org`, `user:email` (documented blast radius in RFC §4.2.3)
- **CF Access on woodpecker.freecodecamp.net:** <enabled / deferred>
- **First pipeline run:** <pipeline # + test repo + duration>

Lessons / deviations: <free-form>
```

## Files

- Modify: `spike/field-notes/infra.md`

## Acceptance Criteria

- Subsection appended at the correct position
- All measurements filled with actual values (or "<not measured>" with reason)

## Context

Same rationale as Task 27 — operational narrative per phase.

## Constraints

- Infra team owns only this file in the Universe repo
- Do NOT run git write commands
````

**Depends on:** Task 10

---

### Task 29 [S]: Update infra field notes — Phase 4 and Phase 6 readiness

**Traceability:** Documentation
**Files:**

- Modify: `/Users/mrugesh/DEV/fCC-U/Universe/spike/field-notes/infra.md`

#### Context

Two entries: (1) Phase 4 exit (Caddy deployed + test site smoke), (2) Phase 6 exit (DNS cutover + measured propagation time + any incidents).

#### Acceptance Criteria

- Two dated entries present, both with measured data

#### Verification

Manual review.

#### Constraints

- Do NOT touch Universe ADRs or spike plan

#### Agent Prompt

````
You are implementing Task 29: Update infra field notes — Phase 4 and Phase 6 readiness.

## Repo and CWD

Work in the Universe repo: `/Users/mrugesh/DEV/fCC-U/Universe`.

## Your Task

Two entries: (1) Phase 4 exit after Caddy chart + test-site smoke passed, (2) Phase 6 exit after DNS cutover and 15-min soak.

### Step 1: Phase 4 entry (template)

```markdown
### gxy-cassiopeia Caddy + R2 smoke-validated (YYYY-MM-DD)

Phase 4 exit per RFC §6.6.

- **Caddy image tag deployed:** <ghcr.io/freecodecamp-universe/caddy-s3:...>
- **Alias cache TTL in production:** 15s (per RFC default)
- **Alias cache max entries:** 10000 (per RFC default)
- **phase4-smoke outcome:** pass, <duration>s end-to-end
- **Caddy pod RAM (actual):** <MB> per pod at idle
- **R2 GetObject rate at baseline:** <req/sec>
- **Origin-only latency p95:** <ms> (via `curl -w "%{time_total}"` test)
- **Origin-allowlist patch run:** <pass/fail for the first f/ops/refresh_cf_ips run>

Deviations from RFC: <free-form>
```

### Step 2: Phase 6 entry (cutover) template

Note: if the cutover template from Task 25 already has a "FILL AT CUTOVER TIME" block, update THAT one (don't duplicate). This task is "fill in the template if it's not yet filled" — idempotent.

```markdown
### DNS cutover to gxy-cassiopeia (YYYY-MM-DD HH:MM UTC)

Phase 6 execution per `docs/runbooks/dns-cutover.md`.

- **Sites cut over:** <count>
- **Preflight output:** attached / paste inline
- **DNS cutover snapshot file:** /tmp/cutover-dns-pre-<ts>.json (moved to infra-secrets)
- **Actual DNS propagation time observed:** <N seconds> (for proxied records)
- **15-min soak 5xx rate:** <N%>
- **15-min soak origin error rate:** <N%>
- **Incidents during cutover:** <none / describe>
- **gxy-cassiopeia Caddy pod memory during cutover peak:** <% of limit>
- **gxy-static decommission target date:** YYYY-MM-DD (≥ 30 days post-cutover per D26)

Lessons: <free-form>
```

### Step 3: Verify
- Both entries dated correctly
- No conflicts with existing Phase 0-2 entries from Tasks 27, 28

## Files

- Modify: `spike/field-notes/infra.md`

## Acceptance Criteria

- Both entries present
- Measured values filled (or explicitly marked "<not measured>")
- Cutover entry explicitly calls out the 30-day decommission target

## Context

These are the post-deploy operational records. The cutover entry in particular will be the canonical post-incident analysis if anything bad happens in the 30-day soak.

## Constraints

- Infra team owns only this file
- Do NOT run git write commands
````

**Depends on:** Task 15, Task 25

---

### Task 30 [L]: Post-M5 — Migrate gxy-launchbase DO → Hetzner (DEFERRED)

**Traceability:** D13 (Hetzner migration) | Constrained by §4.1.1, §4.1.3, §6.3 note
**Status:** **Deferred.** Do NOT dispatch until (a) Hetzner Cloud account is provisioned, (b) M5 exit criteria met (30-day soak complete, gxy-cassiopeia stable), (c) operator signals go-ahead.

**Files (when executed):**

- Create: `ansible/inventory/hetzner.yml`
- Modify: `ansible/requirements.yml` (add `hetzner.hcloud` collection)
- Create: `docs/runbooks/hetzner-cloud-init-dryrun.md`
- Modify: `ansible/inventory/group_vars/gxy_launchbase_k3s.yml` (documentary update only — group_vars is provider-agnostic)
- Modify: `docs/FLIGHT-MANUAL.md` (swap gxy-launchbase provider line back to Hetzner)
- Modify: `docs/rfc/gxy-cassiopeia.md` (§4.1.1 provider line + §12.2 risks table) OR spin a new ADR if provider changes warrant it

#### Context

D13 original intent was Hetzner CX32 FSN1 for gxy-launchbase. The initial rollout uses DO FRA1 because the Hetzner account is not yet provisioned. This follow-up restores the original topology once the account exists — giving blast-radius separation between the CI control plane (Hetzner FSN1) and the serving plane (DO FRA1).

The migration is NOT in-place. It is a parallel-build + cutover:

1. Stand up 3 new Hetzner CX32 under a temporary Ansible group (e.g., `gxy_launchbase_k3s_hetzner`).
2. Bootstrap k3s, restore Woodpecker state from CNPG backup + Helm values.
3. Switch `woodpecker.freecodecamp.net` DNS from DO launchbase IPs to Hetzner IPs.
4. Drain and decommission DO launchbase.

#### Acceptance Criteria (when executed)

- GIVEN `ansible/requirements.yml` has `hetzner.hcloud` WHEN `ansible-galaxy install -r ansible/requirements.yml` runs THEN collection installs
- GIVEN `HCLOUD_TOKEN` is exported via direnv WHEN `ansible-inventory -i ansible/inventory/hetzner.yml --list` runs THEN it returns valid JSON (structure correct even if empty)
- GIVEN 1× CX32 is booted with `cloud-init/k3s-node.yaml` THEN cloud-init completes and k3s installs successfully (documented in field notes)
- GIVEN the 3-node Hetzner cluster THEN Woodpecker UI responds via the new IPs AND CNPG reports Ready AND a test pipeline runs end-to-end
- GIVEN the DNS cutover THEN the DO droplets are powered off AND a decommission field-notes entry is written
- GIVEN the migration is complete THEN RFC §4.1.1 and §12.2 are updated OR a new ADR is filed noting the final topology

#### Constraints

- Do NOT decommission the DO launchbase before the Hetzner cluster has served at least 48 h of production deploys without incident
- Do NOT modify `ansible/inventory/digitalocean.yml` — the DO inventory stays for other galaxies
- Do NOT skip the single-node cloud-init parity dry-run described in the old T06
- Keep `gxy_launchbase_k3s` as the Ansible group name (Hetzner label → `galaxy=gxy_launchbase_k3s`) so group_vars remain unchanged

#### Agent Prompt

````
You are implementing Task 30: Post-M5 migration of gxy-launchbase from DigitalOcean FRA1 to Hetzner CX32 FSN1.

## Pre-flight checks

Before doing ANY work, confirm:

1. Hetzner Cloud account is provisioned and `HCLOUD_TOKEN` is available via `~/DEV/fCC/infra-secrets/hetzner/gxy-launchbase.env.enc`.
2. gxy-cassiopeia has completed its 30-day soak and is stable (M5 exit).
3. gxy-launchbase on DO is currently production-healthy (baseline for the cutover).

If ANY of the above is false, STOP and report back. This task is deferred by design.

## Repo and CWD

Work in the infra repo: `/Users/mrugesh/DEV/fCC/infra`.

## Your Task

Stand up a parallel Hetzner gxy-launchbase, cut Woodpecker over, and decommission the DO droplets.

### Step 1: Hetzner inventory tooling

1. Edit `ansible/requirements.yml`, add under `collections:`:
   ```yaml
   - name: hetzner.hcloud
     version: ">=2.0.0"
   ```
2. Create `ansible/inventory/hetzner.yml`:
   ```yaml
   ---
   plugin: hetzner.hcloud.hcloud
   token_env: HCLOUD_TOKEN

   keyed_groups:
     - key: labels.galaxy
       prefix: ""
       separator: ""

   hostnames:
     - name

   compose:
     ansible_host: public_ipv4
   ```
3. Run `ansible-galaxy install -r ansible/requirements.yml` and `ansible-inventory -i ansible/inventory/hetzner.yml --list` to smoke-test.

### Step 2: cloud-init parity dry-run runbook

Create `docs/runbooks/hetzner-cloud-init-dryrun.md` with:
- Prereqs: HCLOUD_TOKEN via direnv, platform-team SSH key registered.
- Steps: provision 1× CX32 FSN1 labeled `galaxy=gxy_launchbase_k3s` with `cloud-init/k3s-node.yaml`; wait for `cloud-init status --wait`; verify k3s service active; ping via `ansible -i ansible/inventory/hetzner.yml gxy_launchbase_k3s -m ping`; tear down.
- Document any diffs vs DO in `~/DEV/fCC-U/Universe/spike/field-notes/infra.md`.

Execute the dry-run (operator action). Do NOT proceed until it passes green.

### Step 3: Parallel build

1. Provision 3× CX32 in FSN1 with the same cloud-init config and labels.
2. `just play k3s--bootstrap -e "target_hosts=gxy_launchbase_k3s_hetzner"` (or adapt; the group_vars file is shared).
3. Install CNPG operator + restore Woodpecker postgres from DO CNPG backup (follow `docs/runbooks/cnpg-restore.md` equivalent).
4. `just helm-upgrade woodpecker` against the new cluster context.
5. Verify Woodpecker UI responds and a hello-world pipeline runs end-to-end against the Hetzner cluster.

### Step 4: DNS cutover + soak

1. Flip `woodpecker.freecodecamp.net` DNS to Hetzner IPs.
2. Run a 48-h soak; monitor error rate, queue latency, CNPG health.

### Step 5: Decommission

1. After the soak, drain DO agents, scale them to 0, power off the droplets.
2. Preserve a final CNPG backup + Helm values archive in `infra-secrets/gxy-launchbase/decommission-<date>/`.
3. Update `docs/FLIGHT-MANUAL.md` — gxy-launchbase provider line back to Hetzner.
4. Update RFC §4.1.1 and §12.2 (or file a follow-up ADR documenting the final topology).
5. Append a field-notes entry: `/Users/mrugesh/DEV/fCC-U/Universe/spike/field-notes/infra.md`.

### Step 6: Verification

- `ansible -i ansible/inventory/hetzner.yml gxy_launchbase_k3s -m ping` reaches all 3 nodes
- Woodpecker UI reachable via new DNS
- Hello-world pipeline passes
- DO droplets powered off in console
- Field notes updated with actual resource numbers

## Constraints

- Do NOT touch `ansible/inventory/digitalocean.yml` — DO inventory stays for other galaxies
- Do NOT commit `HCLOUD_TOKEN` anywhere
- Do NOT decommission DO droplets until 48 h Hetzner soak is clean
- Do NOT run git write commands — user controls git
````

**Depends on:** Task 29 (M5 exit signalled) + external: Hetzner account provisioned. Not dispatched automatically by `/dp-cto:run`.

---

## Deferred / Future Work

- **universe history command** (Q3 open question) — deferred to v0.5 unless trivial
- **GitHub App migration** (D28, Q8) — post-M5 work to replace OAuth app with fine-grained GitHub App
- **Cloudflare Full (Strict) TLS** (Q6) — P1 security hardening post-M5
- **Local disk caching layer** (§3.2.7) — reintroduce if CDN miss rate exceeds 20% sustained
- **Access log analytics** (Vector → ClickHouse per ADR-015) — deferred until gxy-backoffice exists
- **Branch/per-PR previews** — deferred until developer demand
- **Deploy dashboard UI** — CLI-only for v1
- **Custom domains for constellations** — `*.freecode.camp` only for v1
- **OpenTofu import** of R2 bucket and DO droplets — post-M5 cleanup
- **gxy-launchbase Hetzner migration** (Task 30) — migrate CI galaxy from DO FRA1 to Hetzner CX32 FSN1 once the Hetzner account is provisioned

---

## Traceability Matrix

| R-ID | Requirement                             | Tasks                                                                   |
| ---- | --------------------------------------- | ----------------------------------------------------------------------- |
| R1   | Provision gxy-launchbase cluster        | T07 (DO, initial); T30 (post-M5 Hetzner migration). T06 deferred → T30. |
| R2   | Provision gxy-cassiopeia cluster        | T08                                                                     |
| R3   | Deploy Woodpecker CI                    | T09, T10, T11                                                           |
| R4   | Build custom Caddy r2_alias module      | T01, T02, T03, T04, T05                                                 |
| R5   | Provision R2 bucket                     | T12                                                                     |
| R6   | Deploy Caddy Helm chart                 | T13, T14                                                                |
| R7   | Woodpecker pipeline template            | T21                                                                     |
| R8   | DNS `*.freecode.camp` to gxy-cassiopeia | T13 (HTTPRoute), T23, T25                                               |
| R9   | Preview routing                         | T03 (module), T13 (Caddyfile)                                           |
| R10  | Rewrite `universe deploy`               | T16, T17, T18, T20                                                      |
| R11  | Rewrite `universe promote`              | T19                                                                     |
| R12  | Rewrite `universe rollback`             | T19                                                                     |
| R13  | Site name validation                    | T17                                                                     |
| R14  | Cloudflare cache purge                  | T21 (pipeline step)                                                     |
| R15  | Real-time log streaming in CLI          | T16                                                                     |
| R16  | Old deploy cleanup cron                 | T22                                                                     |
| R17  | Post-deploy smoke test                  | T21 (pipeline step)                                                     |
