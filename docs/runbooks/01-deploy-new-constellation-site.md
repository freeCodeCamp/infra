# Deploy a new constellation site

End-to-end runbook for landing a new `<site>.freecode.camp` on the
freeCodeCamp Universe static-apps platform. Audience: freeCodeCamp
staff developers + platform admins. Spec: ADR-016 (deploy proxy).
Adjacent runbook: [`deploy-artemis-service.md`](deploy-artemis-service.md)
(operator-side artemis lifecycle).

## What you get

- `https://<site>.freecode.camp/` — production
- `https://<site>.preview.freecode.camp/` — preview (per-deploy alias)
- Authorization gated on GitHub team membership in the
  `freeCodeCamp` org. No R2 keys in staff hands; no CI secrets to
  rotate.

## Architecture in one paragraph

Staff dev runs `universe static deploy` from a laptop or CI. The CLI
resolves a GitHub identity (env → GHA OIDC → `gh auth token` →
device-flow token), packages the build output, and uploads it to the
artemis proxy at `https://uploads.freecode.camp`. Artemis verifies
the identity, looks up the site → teams map in its Valkey-backed
registry, probes GitHub team membership, writes the artifact to the
shared R2 bucket
under `<site>.freecode.camp/deploys/<ts>-<sha>/`, and (on `promote`)
flips the `production` alias to that prefix. Caddy on
`gxy-cassiopeia` serves `*.freecode.camp` from R2 via the
`r2_alias` D35 dot-scheme. No R2 token leaves artemis.

## Two-side flow

| Side                   | Frequency         | Surface                                                 |
| ---------------------- | ----------------- | ------------------------------------------------------- |
| **A — Platform admin** | Once per new site | `universe sites register` (staff-gated) against artemis |
| **B — Staff dev**      | Per build         | `universe static deploy` against site repo              |

Side A unblocks Side B. After A lands, staff devs deploy without
further admin involvement.

---

## Side A — Platform admin (one-time per site)

Bring a new `<site>` slug into the artemis registry.

### A1. Register the site

From any staff laptop with a GitHub identity in the `staff` team:

```bash
universe sites register <slug> --team <team>[,<team>...]
```

`--team` repeats or comma-separates. Omit it and the server defaults
to `[staff]`. Slugs match `^[a-z][a-z0-9-]{0,62}$` (DNS-safe; the
slug becomes the `<slug>.freecode.camp` subdomain). Team slugs match
`freeCodeCamp` org GitHub teams (e.g. `bots`, `curriculum`,
`dev-team`, `i18n`, `mobile`, `moderators`, `ops`, `staff`). ANY
listed team grants deploy access.

The CLI `POST`s `/api/site/register` against artemis; the handler
writes a row into the Valkey-backed registry and publishes a
`registry.changed` event. Every artemis replica picks up the new
row within seconds via pub-sub (or ≤60 s via the TTL fallback). No
pod restart, no Helm upgrade, no PR.

Mutations are gated on `staff` (the `REGISTRY_AUTHZ_TEAM` env on the
artemis chart; default `staff`). Per-site teams are independent of
the gate — anyone in `staff` may register any slug for any teams.

### A2. Verify

```bash
universe sites ls --slug <slug>
```

Row returned → registry has it. The 3-column body shows the team
list, creator, and timestamps.

```bash
universe whoami
```

The authorized-sites count goes up by one if you're in any team
listed on the new slug. `universe sites ls --mine` inspects the
full list.

### A3. DNS

`*.freecode.camp` (wildcard) and `*.preview.freecode.camp` (wildcard)
are already proxied through Cloudflare to `gxy-cassiopeia` Caddy
under the `r2_alias` D35 dot-scheme. **No DNS work needed for
standard subdomain sites.**

Exceptions requiring a separate dispatch:

- Apex names (e.g. `freecode.camp` itself) — needs a CNAME flattening
  decision and is out of artemis scope.
- Custom domains outside the `freecode.camp` zone — needs CF zone
  setup + R2 alias key-format extension.

### A4. Cold-start bootstrap (rare)

The authoritative registry is Valkey. The file at
`freeCodeCamp/artemis` `config/sites.yaml` is a **dormant seed** —
checked in for cold-recovery reference only, **not consumed at
runtime**. A fresh artemis pod against an empty Valkey starts with
zero sites; the operator re-populates by replaying
`universe sites register` for each entry in the seed. Editing
`config/sites.yaml` alone does **not** register anything live.

---

## Side B — Staff dev (every deploy)

Build a new constellation site and ship it.

### B1. Install the CLI (one-time, laptop)

```bash
npm i -g @freecodecamp/universe-cli
universe --version
```

Or use `npx @freecodecamp/universe-cli <command>` ad-hoc. Linux/macOS
binaries are also published on the
[`universe-cli` GitHub Releases page](https://github.com/freeCodeCamp-Universe/universe-cli/releases).

### B2. Authenticate (one-time, laptop)

```bash
universe login
```

Opens a GitHub device-flow code in the browser. Token lands at
`~/.config/universe-cli/token`. CI does not need this — see B6.

```bash
universe whoami
```

Confirms login + lists the authorized-sites count (the intersection
of the user's GitHub teams with the artemis registry). Inspect the
list with `universe sites ls --mine`.

### B3. Add `platform.yaml` to the site repo root

Minimal valid file:

```yaml
# ~/DEV/fCC/forum/platform.yaml
site: forum
```

Most sites also need a build:

```yaml
site: forum
build:
  command: pnpm build
  output: dist
```

The `site:` field MUST match the registered slug exactly. The
`build.output` directory is what gets uploaded; everything else in
the repo is ignored. Full schema reference (every field, defaults,
validation rules, v0.3 → v0.4 migration):
[`universe-cli/docs/platform-yaml.md`](https://github.com/freeCodeCamp-Universe/universe-cli/blob/main/docs/platform-yaml.md).

**No credential fields.** The CLI never reads or writes an R2 key —
the proxy holds them.

Commit + push the `platform.yaml`.

### B4. Deploy a preview

```bash
cd ~/DEV/fCC/forum
universe static deploy
```

The CLI:

1. Resolves an identity (priority chain — see CLI README).
2. Reads `platform.yaml` → runs `build.command` → packages
   `build.output/`.
3. `POST /api/deploy/init` against artemis → receives a deploy-session
   JWT (HS256, 15min TTL, scope `(login, site, deployId)`).
4. Multipart-uploads the artifact under that JWT.
5. `POST /api/deploy/{id}/finalize?mode=preview`.
6. Prints the preview URL: `https://<site>.preview.freecode.camp/`.

QA the preview. Re-running `universe static deploy` overwrites the
preview alias to the latest deploy.

### B5. Promote to production

```bash
universe static promote
```

`POST /api/site/<site>/promote`. Re-authenticates against GitHub
(the deploy JWT scope ended at finalize, by design). Artemis flips
the `production` R2 alias key to the most recent deploy prefix.

Production live at `https://<site>.freecode.camp/`. Rollout latency:
seconds (CF + caddy serve next request from the new prefix).

### B6. CI flow (GitHub Actions)

Skip B2 entirely. Slot 2 of the identity chain (GHA OIDC) takes
over. Workflow snippet:

```yaml
permissions:
  id-token: write # required for OIDC slot 2
  contents: read
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npx @freecodecamp/universe-cli@latest static deploy --promote
```

The `--promote` flag rolls preview + promote into one step for CI
fast-paths (use only on already-validated branches, e.g. `main`).

For non-OIDC CI (Woodpecker today, until slot 3 ships), pass an
explicit token via `GITHUB_TOKEN` env.

### B7. List deploys / roll back

```bash
universe static ls --site forum
universe static rollback --to 20260427-141522-abc1234
```

Rollback re-targets the production alias to a prior deploy prefix.
Same latency as promote.

---

## Failure modes (staff-side)

| Symptom                                      | Cause                                               | Action                                                                                      |
| -------------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `universe whoami` does not list the new site | A1 not run, or Valkey cache lag (≤60 s TTL)         | `universe sites ls --slug <site>` to confirm registry; if listed, retry `whoami` after 60 s |
| `403 forbidden` on `static deploy`           | user not in any team registered for the site        | `universe sites update <site> --team +<your-team>` (staff)                                  |
| `404 site not found` on deploy               | `platform.yaml` `site:` does not match the registry | fix the slug in `platform.yaml`, or `universe sites register <slug>` it                     |
| Preview URL returns 404                      | `finalize` not called yet                           | re-run `universe static deploy`                                                             |
| Preview URL returns 502                      | artemis pod unhealthy or rate-limited               | check `https://uploads.freecode.camp/healthz`; ping ops                                     |
| `build.command` fails                        | command not present, deps missing                   | run command locally first; install deps in CI step                                          |
| 429 on bulk upload                           | Traefik middleware rate-limit tripped               | retry after 1 second; tune `rateLimit.average` in chart values                              |
| Production URL stale after `promote`         | CF edge cache still hot                             | wait 30 seconds; if persistent, purge CF cache for the site                                 |

## Cross-references

- [ADR-016 — Universe deploy proxy](https://github.com/freeCodeCamp-Universe/Universe/blob/main/decisions/016-deploy-proxy.md)
- [`02-deploy-artemis-service.md`](02-deploy-artemis-service.md) — operator-side artemis lifecycle
- [`03-artemis-postdeploy-check.md`](03-artemis-postdeploy-check.md) — post-deploy smoke
- [`05-r2-keys-rotation.md`](05-r2-keys-rotation.md) — R2 admin + read-only key rotation
- [`universe-cli` README](https://github.com/freeCodeCamp-Universe/universe-cli/blob/main/README.md) — full CLI surface
- `freeCodeCamp/artemis` registry (Valkey-backed; `config/sites.yaml`
  in the artemis repo is a dormant cold-start seed only) — authorization SOT
- `infra/k3s/gxy-management/apps/artemis/` — Helm chart + production overlay
