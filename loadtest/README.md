# Load Tests (k6)

[k6](https://k6.io/) scenarios for the static-apps pillar. Source files
live under `scenarios/`. Shared helpers under `lib/`. Run via:

```sh
just loadtest <scenario>
```

`scenario` is the file basename under `scenarios/` (no `.js` suffix).

## Install k6

```sh
brew install k6              # macOS
# or: docker run -i grafana/k6 run - < scenarios/<scenario>.js
```

## Scenarios

| File                     | Target                      | Profile                              | Purpose                                    |
| ------------------------ | --------------------------- | ------------------------------------ | ------------------------------------------ |
| `caddy-serve.js`         | `<site>.<root>`             | high-RPS GET, 5 min ramp + steady    | Caddy + R2 + CF cache behavior on hot path |
| `caddy-serve-preview.js` | `<site>.preview.<root>`     | high-RPS GET, 5 min ramp + steady    | Preview alias hot path (no CF cache wins)  |
| `artemis-whoami.js`      | `${ARTEMIS_URL}/api/whoami` | moderate-RPS, GH-bearer hot          | GitHub teams cache + auth middleware       |
| `artemis-deploy.js`      | full deploy chain           | sustained init+upload+finalize burst | R2 PUT + JWT mint + alias write throughput |

## Common env

All scenarios source `lib/config.js` which reads:

| Variable       | Default                         | Purpose                           |
| -------------- | ------------------------------- | --------------------------------- |
| `ARTEMIS_URL`  | `https://uploads.freecode.camp` | Artemis base URL                  |
| `SITE`         | `test`                          | Site key in `sites.yaml`          |
| `ROOT_DOMAIN`  | `freecode.camp`                 | Public root domain                |
| `GH_TOKEN`     | `gh auth token`                 | GH bearer for authenticated paths |
| `LOAD_PROFILE` | `smoke`                         | `smoke` \| `baseline` \| `stress` |

`LOAD_PROFILE` selects the VU/duration ramp:

| Profile    | Peak VUs | Total duration | Use                           |
| ---------- | -------- | -------------- | ----------------------------- |
| `smoke`    | 5        | 1 min          | Quick check, CI-friendly      |
| `baseline` | 50       | 5 min          | Healthy steady-state behavior |
| `stress`   | 200      | 10 min         | Find the breaking point       |

## SLO thresholds (per scenario)

Defined inline in each scenario via k6 `thresholds`. Smoke profile
defaults match D38 (production-alias serve ≤ 2 min) and a generous
p95 on artemis API calls. Adjust per-deployment-environment as
empirical data accumulates.

## Output

k6 prints a summary table at run end. For machine-readable output:

```sh
just loadtest caddy-serve >loadtest/results/caddy-serve-$(date -u +%Y%m%dT%H%M%SZ).txt
# or with JSON:
k6 run --out json=loadtest/results/caddy-serve.json scenarios/caddy-serve.js
```

`loadtest/results/` is gitignored. Persist meaningful runs by
committing the markdown summary in a sprint or runbook doc, not the
raw output.

## Safety

- `caddy-serve` and `caddy-serve-preview` are read-only and safe at
  any RPS — they hit CF edge first, R2 takes the residual.
- `artemis-whoami` is read-only against artemis but hits the GitHub
  API on cache miss. **Watch the GH rate-limit** — keep `LOAD_PROFILE=smoke`
  unless you hold a high-rate token (org-level App).
- `artemis-deploy` is **write-heavy**. Every iteration uploads an
  immutable deploy prefix to R2. Cleanup cron (T22, 7-day retention)
  sweeps these eventually, but a long stress run will accumulate
  R2 storage. Cap with `LOAD_PROFILE=baseline` and trim runs by
  duration.

## Adding a scenario

1. Drop the new file at `scenarios/<name>.js`.
2. Import `lib/config.js` for env resolution.
3. Define `options` with `scenarios` or `stages` keyed by `LOAD_PROFILE`.
4. Define realistic `thresholds`.
5. Document it in the scenario table above.
