# T32 — universe-cli v0.4 rewrite (proxy client)

**Status:** pending
**Worker:** w-cli (governing session — broken ownership 2026-04-26)
**Repo:** `~/DEV/fCC-U/universe-cli` (new branch: `feat/proxy-pivot` off `main`)
**Spec:** D016 §CLI surface + §Authn/authz
**Cross-ref:** D43 amendment in sprint `DECISIONS.md`
**Toolchain:** existing — Bun, pnpm, vitest, oxfmt, oxlint, husky, tsup
**Started:** —
**Closed:** —
**Closing commit(s):** —

---

## Why this is a fresh branch

Per D016 / Q14: existing `feat/woodpecker-pivot` branch (4 commits ahead
of `main`) is **archaeology**. Branch off `main` (= published v0.3.x base)
as `feat/proxy-pivot`. v0.3.x stays current published until v0.4 ships.
Old branch never merged.

```bash
cd ~/DEV/fCC-U/universe-cli
git checkout main
git pull --rebase origin main          # operator-deferred
git checkout -b feat/proxy-pivot
```

## CLI surface (locked per D016 + 2026-04-27 amendment §CLI namespace)

Top-level reserved for cross-cutting auth + identity + version. Deploy
verbs namespaced under `static` so future surfaces (workers, dbs,
queues) extend without breaking change.

```
# top-level (cross-cutting)
universe login                                       # GitHub OAuth device flow → ~/.config/universe-cli/token
universe logout                                      # delete stored token
universe whoami                                      # echo current login + authorized sites
universe version                                     # CLI version + build metadata

# static surface (namespaced)
universe static deploy [--promote] [--dir <path>]    # build → upload → preview (or promote)
universe static promote [--from <deployId>]          # swap production alias to preview (or named deploy)
universe static rollback --to <deployId>             # write production alias to past deploy
universe static ls [--site <site>]                   # list recent deploys with timestamps + git sha
```

Future surface skeleton (out of scope this dispatch — register `static`
as a command group cleanly so `worker` / `db` / `queue` etc. layer in
later without restructuring):

```
universe worker deploy ...    # future
universe db migrate ...       # future
universe queue purge ...      # future
```

## Identity resolution priority (Q10)

1. `$GITHUB_TOKEN` or `$GH_TOKEN` env (CI explicit)
2. GHA OIDC `$ACTIONS_ID_TOKEN_REQUEST_TOKEN` (GHA auto)
3. Woodpecker OIDC env (when supported)
4. `gh auth token` shell-out (laptop with gh installed)
5. `~/.config/universe-cli/token` (device-flow stored)

## Files to touch

```
universe-cli/
├── src/
│   ├── commands/
│   │   ├── login.ts                   # NEW — device flow
│   │   ├── logout.ts                  # NEW
│   │   ├── whoami.ts                  # NEW
│   │   ├── deploy.ts                  # REWRITE — proxy client
│   │   ├── promote.ts                 # REWRITE — proxy client
│   │   ├── rollback.ts                # REWRITE — proxy client
│   │   └── ls.ts                      # NEW
│   ├── lib/
│   │   ├── proxy-client.ts            # NEW — typed fetch wrapper for /api/*
│   │   ├── identity.ts                # NEW — priority chain resolver
│   │   ├── device-flow.ts             # NEW — GH OAuth device flow
│   │   ├── token-store.ts             # NEW — ~/.config/universe-cli/token I/O
│   │   ├── platform-yaml.ts           # KEEP+UPDATE — schema v2 reader (T33)
│   │   ├── build.ts                   # NEW — invoke build.command + collect dist/
│   │   ├── upload.ts                  # NEW — multipart upload to proxy
│   │   └── ignore.ts                  # NEW — gitignore-style filter
│   ├── errors.ts                      # SLIM — strip Woodpecker-specific errors
│   └── index.ts                       # entrypoint
├── tests/
│   ├── commands/
│   │   ├── login.test.ts
│   │   ├── deploy.test.ts
│   │   ├── promote.test.ts
│   │   ├── rollback.test.ts
│   │   └── ls.test.ts
│   └── lib/
│       ├── proxy-client.test.ts
│       ├── identity.test.ts
│       ├── device-flow.test.ts
│       └── upload.test.ts
├── package.json                        # version → 0.4.0-alpha.1; drop Woodpecker deps if any
├── README.md                           # full rewrite for proxy model
└── CHANGELOG.md                        # v0.4 entry
```

## Files to delete (post-pivot cleanup, not via git rm — branch never merged)

- `src/lib/woodpecker-client.ts` (if present from `feat/woodpecker-pivot`)
- Any `tests/woodpecker-*.test.ts`

(These do not exist on `main` since `feat/woodpecker-pivot` was never merged. Fresh branch off `main` skips them.)

## Acceptance criteria

### Test gates (TDD)

- vitest coverage ≥ 80% on `src/commands/` + `src/lib/`
- All commands tested with mock proxy server (`undici` MockAgent or `msw`)
- Identity priority chain tested with env mutation per case
- Device flow tested with mock GH device endpoint

### Behavioral gates

- `universe login` opens device-flow URL, polls until authorized, persists token
- `universe whoami` resolves identity via priority chain, returns `{login, sites}`
- `universe static deploy` reads `platform.yaml`, runs `build.command` (or skips if pre-built), POSTs `/api/deploy/init`, multipart-uploads `output/`, POSTs `/finalize`
- `universe static promote` POSTs `/api/site/{site}/promote`
- `universe static rollback --to <id>` POSTs `/api/site/{site}/rollback`
- `universe static ls` returns deploy list, formats as table
- T33-shipped `docs/platform-yaml.md` mention of `universe deploy` updated to `universe static deploy` (single text edit; same commit as T32 work)

### Operational gates

- `bun run build` produces dist with no Woodpecker references
- `oxlint .` clean
- `oxfmt --check .` clean
- README + CHANGELOG updated
- `package.json` version `0.4.0-alpha.1`

## Out of scope (T33 covers)

- `platform.yaml` v2 schema doc + validator update (separate dispatch)

## Closure checklist

- [ ] All files listed present
- [ ] Tests green (vitest)
- [ ] Lint + format clean
- [ ] Single commit per task close
- [ ] T32 Status `done`
- [ ] PLAN matrix row checked
- [ ] HANDOFF entry appended
