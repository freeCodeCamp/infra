# T33 — platform.yaml v2 schema + README + validator

**Status:** done
**Worker:** w-cli (multi-session true-parallel — T33 worker session)
**Repo:** `~/DEV/fCC-U/universe-cli` (branch: `feat/proxy-pivot`)
**Spec:** D016 §`platform.yaml` schema
**Cross-ref:** D43 amendment in sprint `DECISIONS.md`
**Started:** 2026-04-27
**Closed:** 2026-04-27
**Closing commit(s):** `universe-cli@8788648` (feat) + `universe-cli@5d7b6ef` (docs)

---

## Why v2

v0.3 schema carries R2 token references in `platform.yaml`. v0.4 strips
all credential paths; staff repos hold only build + deploy config. Auth
happens via GitHub identity at proxy layer. Site → team mapping lives
server-side (per D016 / Q11).

## v2 schema (locked per D016)

```yaml
# Required. Becomes <site>.freecode.camp + <site>.preview.freecode.camp.
site: my-site

# Optional. Omit if uploading pre-built artifacts.
build:
  command: bun run build # build script
  output: dist # output dir relative to repo root

# Optional. Defaults shown.
deploy:
  preview: true # `universe deploy` → preview unless --promote
  ignore: # gitignore-style, applied to upload set
    - "*.map"
    - "node_modules/**"
    - ".git/**"
    - ".env*"
```

**Removed from v1:**

- `r2.*` block — proxy holds R2 admin credentials
- `region`, `bucket`, `key`, `endpoint` — out of staff hands
- Per-site team declaration — server-side static map per Q11

## Files to touch

```
universe-cli/
├── src/lib/
│   ├── platform-yaml.ts             # validator + parser
│   └── platform-yaml.schema.ts      # zod schema definition
├── tests/lib/
│   └── platform-yaml.test.ts
├── docs/
│   └── platform-yaml.md             # NEW — schema reference
├── CHANGELOG.md                      # v0.4 schema delta entry
└── README.md                         # schema reference link + minimal example
```

## Acceptance criteria

### Test gates (TDD)

- Valid v2 sample passes
- Missing required `site` rejected
- Invalid site name (uppercase, leading hyphen, consecutive hyphens) rejected (D19 + D37 carry forward)
- Site name validator: lowercase letters, digits, single hyphens, 1–63 chars, no leading/trailing hyphen
- v1 schema with `r2.*` block rejected with migration error pointing to docs
- Optional `build` omitted → defaults to `{output: "dist"}`
- Optional `deploy.ignore` defaults to gitignore-style with sane defaults

### Behavioral gates

- Validator surface: `parsePlatformYaml(text: string): {ok: true, value: Schema} | {ok: false, error: string}`
- Migration helper: detects v1, prints message "platform.yaml v1 detected. v0.4 removes credential paths. See docs/platform-yaml.md migration."
- README example uses minimal valid file (`site: my-site` only)

### Doc gate

- `docs/platform-yaml.md` documents every field, defaults, validation rules, examples
- Migration note: v0.3 → v0.4 schema delta (what's removed, why)

## Closure checklist

- [x] Schema validator landed (`src/lib/platform-yaml.{ts,schema.ts}`)
- [x] Tests green (252/252; new file 32/32 RED→GREEN)
- [x] Doc landed (`docs/platform-yaml.md` + README link + CHANGELOG)
- [x] T33 Status `done`
- [x] PLAN matrix row checked
- [x] HANDOFF entry appended
