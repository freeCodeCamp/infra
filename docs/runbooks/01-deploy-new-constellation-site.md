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
the identity, looks up the site → teams map in `sites.yaml`, probes
GitHub team membership, writes the artifact to the shared R2 bucket
under `<site>.freecode.camp/deploys/<ts>-<sha>/`, and (on `promote`)
flips the `production` alias to that prefix. Caddy on
`gxy-cassiopeia` serves `*.freecode.camp` from R2 via the
`r2_alias` D35 dot-scheme. No R2 token leaves artemis.

## Two-side flow

| Side                   | Frequency         | Surface                                  |
| ---------------------- | ----------------- | ---------------------------------------- |
| **A — Platform admin** | Once per new site | `freeCodeCamp/artemis` repo `sites.yaml` |
| **B — Staff dev**      | Per build         | `universe-cli` against site repo         |

Side A unblocks Side B. After A lands, staff devs deploy without
further admin involvement.

---

## Side A — Platform admin (one-time per site)

Bring a new `<site>` slug into the artemis authorization map.

### A1. PR to `freeCodeCamp/artemis` `config/sites.yaml`

Add an entry under `sites:`. The slug must match the public hostname
prefix exactly (`forum` → `forum.freecode.camp`).

```yaml
sites:
  test:
    teams: [staff]
  forum: # new
    teams: [dev-team, staff] # any matching team membership grants access
```

Schema: `sites.<slug>.teams: [<gh-team-slug>, ...]`. ANY team match
authorizes. Team slugs match `freeCodeCamp` org GitHub teams (e.g.
`bots`, `curriculum`, `dev-team`, `i18n`, `mobile`, `moderators`,
`ops`, `staff`).

### A2. Review + merge

Platform team reviews the PR. Merge to `main`.

### A3. Reload artemis ConfigMap

Operator on the deploy host:

```bash
git -C ~/DEV/fCC/artemis pull --ff-only
cd ~/DEV/fCC/infra
just deploy gxy-management artemis
```

The `just deploy` recipe re-renders the ConfigMap from the operator's
local artemis checkout via `--set-file sites=$ARTEMIS_REPO/config/sites.yaml`
(default `$HOME/DEV/fCC/artemis`). The artemis pod watches the
ConfigMap mount with fsnotify and hot-reloads in ≤1 minute. **No pod
restart, no downtime.**

### A4. Verify reload landed

```bash
direnv exec ~/DEV/fCC/infra/k3s/gxy-management \
  kubectl -n artemis logs -l app.kubernetes.io/name=artemis --tail=50 \
  | grep -i 'sites.yaml'
```

Look for the `sites.yaml reloaded; N entries` line. `N` should match
the count in the merged file.

### A5. Verify the slug is live

From any laptop with a GitHub identity in one of the new site's
teams:

```bash
universe whoami
```

The output should list the new `<site>` slug under "authorized
sites". If missing, A3 did not reload the ConfigMap; re-run.

### A6. DNS

`*.freecode.camp` (wildcard) and `*.preview.freecode.camp` (wildcard)
are already proxied through Cloudflare to `gxy-cassiopeia` Caddy
under the `r2_alias` D35 dot-scheme. **No DNS work needed for
standard subdomain sites.**

Exceptions requiring a separate dispatch:

- Apex names (e.g. `freecode.camp` itself) — needs a CNAME flattening
  decision and is out of artemis scope.
- Custom domains outside the `freecode.camp` zone — needs CF zone
  setup + R2 alias key-format extension.

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

Confirms login + lists authorized site slugs (the union of all teams
the user belongs to, intersected with the artemis `sites.yaml` map).

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

The `site:` field MUST match the `sites.yaml` slug exactly. The
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

| Symptom                                      | Cause                                              | Action                                                               |
| -------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------------------- |
| `universe whoami` does not list the new site | Side A not run, or A3 ConfigMap reload not yet hot | ping platform admin; retry after 1 minute                            |
| `403 forbidden` on `static deploy`           | user not in any team listed for the site           | add user to a team in `sites.yaml` `<site>.teams`, or amend the file |
| `404 site not found` on deploy               | `platform.yaml` `site:` does not match sites.yaml  | fix the slug in `platform.yaml`                                      |
| Preview URL returns 404                      | `finalize` not called yet                          | re-run `universe static deploy`                                      |
| Preview URL returns 502                      | artemis pod unhealthy or rate-limited              | check `https://uploads.freecode.camp/healthz`; ping ops              |
| `build.command` fails                        | command not present, deps missing                  | run command locally first; install deps in CI step                   |
| 429 on bulk upload                           | Traefik middleware rate-limit tripped              | retry after 1 second; tune `rateLimit.average` in chart values       |
| Production URL stale after `promote`         | CF edge cache still hot                            | wait 30 seconds; if persistent, purge CF cache for the site          |

## Cross-references

- [ADR-016 — Universe deploy proxy](https://github.com/freeCodeCamp-Universe/Universe/blob/main/decisions/016-deploy-proxy.md)
- [`02-deploy-artemis-service.md`](02-deploy-artemis-service.md) — operator-side artemis lifecycle
- [`03-artemis-postdeploy-check.md`](03-artemis-postdeploy-check.md) — post-deploy smoke
- [`05-r2-keys-rotation.md`](05-r2-keys-rotation.md) — R2 admin + read-only key rotation
- [`universe-cli` README](https://github.com/freeCodeCamp-Universe/universe-cli/blob/main/README.md) — full CLI surface
- `freeCodeCamp/artemis` `config/sites.yaml` — authorization SOT
- `infra/k3s/gxy-management/apps/artemis/` — Helm chart + production overlay
