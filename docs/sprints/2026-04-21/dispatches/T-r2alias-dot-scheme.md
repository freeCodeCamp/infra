# T-r2alias-dot-scheme — Caddy r2_alias module dot-scheme migration

**Status:** in-progress
**Type:** code dispatch (Go module rewrite + chart bump + GH Actions workflow)
**Worker:** session
**Repo:** `~/DEV/fCC/infra` (branch: `feat/k3s-universe`)
**Spec:** D35 ([`DECISIONS.md`](../DECISIONS.md)) — preview host scheme `<site>.preview.<root>` (dot) supersedes D5 (`<site>--preview.<root>`)
**Audit ref:** smoke run failure 2026-04-26 (G1.1.smoke step 6, deploy `phase4-20260426-065204`); Caddy logs confirm 404 from `test.preview.freecode.camp` despite alias write — module hardcoded to D5 suffix scheme.
**Predecessor:** G1.0a, G1.0b, G1.1
**Blocks:** G1.1.smoke
**Wave:** A.1
**Started:** 2026-04-26
**Closed:** —

---

## What this delivers

D35 ratified 2026-04-22 flipped preview scheme from `<site>--preview.<root>` to `<site>.preview.<root>` (dot). Caddy `r2alias` Go module never updated. Smoke caught it: prod alias works (suffix logic falls through to production for any non-`--preview` host), preview alias misses because module treats `test.preview.freecode.camp` as a multi-label production site.

This dispatch:

1. Rewrites `parseSiteAndAlias` for dot-scheme (`<labels>.preview.<root>` → site=`<labels>.<root>`, alias=preview).
2. Renames Caddyfile option `preview_suffix` → `preview_subdomain` (default `"preview"`).
3. Updates `caddy-caddyfile` ConfigMap on cassiopeia chart.
4. Establishes GH Actions as the canonical builder (build-residency principle: platform pillars must build outside Universe to dodge bootstrap chicken-egg).
5. Marks Woodpecker pipeline secondary; full retirement via separate `T-build-residency` dispatch.

## Build-residency rationale (why GH Actions, not Woodpecker)

Caddy is a Universe platform pillar. Building it on Woodpecker (which lives on `gxy-launchbase` inside Universe) creates a chicken-egg: if Universe is down, Caddy can't be rebuilt → Universe can't be recovered. Anything in Universe's recovery path must build externally. GHCR storage is fine (already external by design). The build pipeline must also be external.

Field-note observation logged for ADR proposal by Universe team.

## Steps

### 1. TDD red — host_test.go dot-scheme cases

Add cases for: `test.preview.freecode.camp` → site=`test.freecode.camp`, alias=preview; multi-label `foo.bar.preview.freecode.camp` → site=`foo.bar.freecode.camp`, alias=preview; `preview.freecode.camp` (apex preview) → reject. Verify red via `go test ./docker/images/caddy-s3/modules/r2alias/...`.

### 2. Green — rewrite `parseSiteAndAlias`

Detect `.preview.<root>` boundary (preview is the rightmost label before root). Strip `.preview` from prefix → site=`<remaining>.<root>`. Drop suffix-matching branch.

### 3. Rename option

Module struct: `PreviewSuffix` → `PreviewSubdomain`. Caddyfile: `preview_suffix` → `preview_subdomain`. Default `"preview"`.

### 4. Update chart configmap

`k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/configmap.yaml`: `preview_suffix "--preview"` → `preview_subdomain "preview"`.

### 5. New GH Actions workflow

`.github/workflows/caddy-s3-build.yml`: trigger on push to any branch matching `docker/images/caddy-s3/**` + `workflow_dispatch`. Steps: `go test -race ./...` on module → `docker/build-push-action` to `ghcr.io/freecodecamp-universe/caddy-s3:${SHA}` + branch tag. Use `GITHUB_TOKEN` for ghcr.

### 6. Mark Woodpecker secondary

`.woodpecker/caddy-s3-build.yaml`: header comment "Secondary builder. Canonical = .github/workflows/caddy-s3-build.yml. Will retire via T-build-residency."

### 7. Field-note observation

Append to `~/DEV/fCC-U/Universe/spike/field-notes/infra.md` — build-residency principle finding. Separate cross-repo commit.

### 8. Operator: trigger build

Operator pushes feat branch (or `workflow_dispatch`). GH Actions builds + pushes `<SHA>` tag. Operator reports SHA.

### 9. Bump chart values

`k3s/gxy-cassiopeia/apps/caddy/values.yaml` (or chart-local): `image.tag = <SHA>`.

### 10. Operator: helm-upgrade

Operator runs `just helm-upgrade caddy gxy-cassiopeia` (or eq.). Verify caddy pods Ready.

### 11. Re-run smoke

`direnv exec ~/DEV/fCC/infra/k3s/gxy-cassiopeia bash -c 'export GXY_CASSIOPEIA_NODE_IP="$(doctl ...)"; cd ~/DEV/fCC/infra && just phase4-smoke'`. Expect 8/8 green.

### 12. Strip stale `--preview` refs from RFC

`docs/architecture/rfc-gxy-cassiopeia.md`: scrub 14+ stale refs to align with D35. Separate doc commit.

## Acceptance criteria

- `go test -race ./docker/images/caddy-s3/modules/r2alias/...` green (incl new dot-scheme cases).
- `caddy-caddyfile` ConfigMap on cassiopeia uses `preview_subdomain "preview"`.
- `ghcr.io/freecodecamp-universe/caddy-s3:<SHA>` exists, built by GH Actions.
- caddy pods on cassiopeia run new image.
- `just phase4-smoke` exits 0 with `OK: phase 4 smoke passed — phase4-<ts>`.
- `cf-cache-status: DYNAMIC` confirmed for both prod + preview hostnames during smoke.
- `.woodpecker/caddy-s3-build.yaml` carries secondary-builder header comment.
- RFC body free of stale `--preview` references (`grep -c '\-\-preview' docs/architecture/rfc-gxy-cassiopeia.md` = 0 except in D5/D35 supersession trail).

## Verify command (read-only, post-run)

```bash
# Module tests:
cd docker/images/caddy-s3/modules/r2alias && go test -race ./... && cd -

# ConfigMap reflects new option:
direnv exec ~/DEV/fCC/infra/k3s/gxy-cassiopeia kubectl -n caddy get cm caddy-caddyfile -o jsonpath='{.data.Caddyfile}' | grep -E 'preview_subdomain'

# Caddy image SHA on cluster:
direnv exec ~/DEV/fCC/infra/k3s/gxy-cassiopeia kubectl -n caddy get pods -l app.kubernetes.io/name=caddy -o jsonpath='{.items[0].spec.containers[0].image}'

# Smoke green:
just phase4-smoke   # last line: OK: phase 4 smoke passed — phase4-<ts>

# Bucket clean:
aws s3 ls "s3://universe-static-apps-01/test.freecode.camp/" --recursive \
  --endpoint-url "https://ad45585c4383c97ec7023d61b8aef8c8.r2.cloudflarestorage.com" \
  --region auto
# expect: empty
```

## Closure (worker fills on close)

- **Status:** —
- **Closing commit(s):** —
  - `feat(caddy-s3): r2_alias dot-scheme preview routing per D35`
  - `chore(caddy-s3): preview_subdomain option in chart configmap`
  - `ci(caddy-s3): GH Actions canonical builder; mark Woodpecker secondary`
  - `chore(caddy): bump image to <SHA>`
  - `docs(rfc): strip --preview suffix refs per D35 supersession`
  - `feat(sprint): close G1.1 + G1.1.smoke + T-r2alias-dot-scheme`
- **Verify output:** —
- **Sprint-doc patches owed:**
  - PLAN.md Wave A.1 matrix → add T-r2alias-dot-scheme `[x] done`
  - HANDOFF.md → append closure entry with smoke deploy ID + image SHA
  - STATUS.md → mark Wave A.1 fully closed
  - Field-note: build-residency principle (cross-repo Universe commit)
- **Follow-up dispatch:** `T-build-residency` (audit all platform pillar builds; retire Woodpecker for those; ADR proposal to Universe team)
