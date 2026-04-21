# RFC: Secrets Layout — Two-Scope Convention + Shared Wildcard Cert

**Date:** 2026-04-22
**Status:** Accepted (implemented 2026-04-22)
**Target Release:** Pre-#22 (rename exec gate)
**Author:** Infra team
**Related:** ADR-003 (Universe topology), ADR-011 (admin plane + secrets),
ADR-012 (DR — parked)
**Gates:** sprint task #22 (gxy-mgmt → gxy-management reprovision)

## Summary

Formalize `infra-secrets` layout into two explicit scopes — platform-wide
(`<app>/`, `global/`) and cluster-local (`k3s/<cluster>/`). Deduplicate the
`*.freecodecamp.net` Cloudflare Origin wildcard into a single canonical
source at `global/tls/<zone>.{crt,key}.enc`. Extend `just deploy` with a
zone-fallback probe so apps that need the wildcard don't each carry a
copy. Backfill missing `.enc` assets flagged during the 2026-04-21 audit
(wooodpecker TLS, Windmill backup S3). Sync all flight-manuals + the
rename runbook + infra-secrets README to match.

Out of scope: legacy retirement of `appsmith/` + `outline/` + `docker/`

- `k8s/o11y/` — handled post-Universe launch.

## Motivation

The 2026-04-21 cluster audit surfaced drift that blocks task #22:

- Wildcard `*.freecodecamp.net` origin cert is encrypted **three times**
  on gxy-management (argocd / windmill / zot pairs), once on
  gxy-launchbase **manifest only — no `.enc` source file exists**, and
  zero times on gxy-static + gxy-cassiopeia even though they serve
  `freecode.camp` (different zone).
- `k3s/gxy-launchbase/woodpecker.tls.{crt,key}.enc` is MISSING from
  `infra-secrets` despite `woodpecker-tls-cloudflare` Secret running in
  cluster for 27h+. Source-of-truth broken.
- `k3s/gxy-management/windmill-backup.secrets.env.enc` is MISSING. Only
  `.sample` stub. `backup-cronjob.yaml` commented out in kustomization
  with "TODO re-enable". Blocks #22 step-1 (pre-teardown backup).
- Rename runbook §Preconditions names `.enc` files that don't exist —
  operator misread risk during live exec.
- Classification confusion: top-level `argocd/` / `windmill/` / `zot/`
  (Universe platform-wide, reserved) was nearly misclassified as legacy
  during audit. Need explicit documented convention.

## Current state (verified 2026-04-21)

### infra-secrets tree (trimmed)

```
.sops.yaml                       # single path_regex `.*` → platform age key
README.md                        # existing directory-structure doc
global/.env.enc                  # platform-wide tokens (CF, Tailscale, HCP, ...)
do-primary/.env.enc              # DO API token — legacy account
do-universe/.env.enc             # DO API token — Universe account
argocd/.env.sample               # (empty — reserved platform-wide namespace)
windmill/.env.sample             # (empty — reserved platform-wide namespace)
zot/.env.sample                  # (empty — reserved platform-wide namespace)
appsmith/.env.enc                # LEGACY (oldeworld Swarm)
outline/.env.enc                 # LEGACY (oldeworld Swarm)
docker/oldeworld/*.env.{enc,sample}   # LEGACY
k8s/o11y/*                       # legacy managed k8s cluster
k3s/<cluster>/<app>.values.yaml.enc         # helm chart overlay
k3s/<cluster>/<app>.secrets.env.enc         # dotenv → kustomize secretGenerator
k3s/<cluster>/<app>-backup.secrets.env.enc  # backup-specific dotenv (suffix `-backup`)
k3s/<cluster>/<app>.tls.{crt,key}.enc       # per-app TLS
k3s/<cluster>/kubeconfig.yaml.enc           # encrypted kubeconfig
scratchpad/                      # dev scratch
```

### Deploy pipeline (existing `just deploy <cluster> <app>`)

```
for suffix in '.secrets.env.enc' '.tls.crt.enc' '.tls.key.enc' '-backup.secrets.env.enc':
    if infra-secrets/k3s/<cluster>/<app><suffix> exists:
        sops -d → k3s/<cluster>/apps/<app>/manifests/base/secrets/<plain-name>
kubectl apply -k apps/<app>/manifests/base/
trap cleanup decrypted files on exit
```

`just helm-upgrade <cluster> <app>` similarly probes
`infra-secrets/k3s/<cluster>/<app>.values.yaml.enc`.

### Drift matrix

| Galaxy         | App                 | In-cluster Secret               | `.enc` source present? | Notes                                        |
| -------------- | ------------------- | ------------------------------- | ---------------------- | -------------------------------------------- |
| gxy-management | argocd              | argocd-tls-cloudflare (14d)     | Yes (duplicate 1 of 3) | Wildcard dup                                 |
| gxy-management | windmill            | windmill-tls-cloudflare (3d23h) | Yes (duplicate 2 of 3) | Wildcard dup                                 |
| gxy-management | zot                 | —                               | Yes (duplicate 3 of 3) | Zot not deployed; pre-staged cert            |
| gxy-management | windmill-backup     | —                               | **No (.sample only)**  | Blocks #22 preflight backup                  |
| gxy-launchbase | woodpecker (tls)    | woodpecker-tls-cloudflare (27h) | **No**                 | Bootstrap drift — canonical missing          |
| gxy-launchbase | woodpecker (env)    | woodpecker-env                  | Yes                    | OK                                           |
| gxy-launchbase | woodpecker (backup) | woodpecker-postgres-s3-backup   | Yes                    | OK                                           |
| gxy-static     | caddy               | —                               | values.yaml.enc only   | No TLS cert on that gateway pattern          |
| gxy-cassiopeia | caddy               | —                               | values.yaml.enc only   | No TLS cert today; `*.freecode.camp` pending |

## Proposed layout

### Two explicit scopes

| Scope                             | Path shape                                                | What lives here                                                                                                               |
| --------------------------------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| **Platform-wide direnv**          | `<namespace>/.env.enc`                                    | Global tokens loaded by direnv on `cd infra/`                                                                                 |
| **Platform-wide per-app**         | `<app>/.env.enc`                                          | Cross-cluster Universe app secrets (reserved today; empty `.sample` stubs for `argocd`, `windmill`, `zot` mark the namespace) |
| **Platform-wide TLS**             | `global/tls/<zone>.{crt,key}.enc`                         | CF Origin wildcards per DNS zone                                                                                              |
| **Cluster-local helm**            | `k3s/<cluster>/<app>.values.yaml.enc`                     | Helm chart value overlay                                                                                                      |
| **Cluster-local secrets**         | `k3s/<cluster>/<app>.secrets.env.enc`                     | dotenv → kustomize secretGenerator                                                                                            |
| **Cluster-local backup**          | `k3s/<cluster>/<app>-backup.secrets.env.enc`              | `-backup` suffix convention                                                                                                   |
| **Cluster-local TLS override**    | `k3s/<cluster>/<app>.tls.{crt,key}.enc`                   | Only when the cluster/app needs a cert distinct from the zone default                                                         |
| **Cluster-local kubeconfig**      | `k3s/<cluster>/kubeconfig.yaml.enc`                       | Encrypted kubeconfig                                                                                                          |
| **Legacy (retire post-Universe)** | `appsmith/`, `outline/`, `docker/oldeworld/`, `k8s/o11y/` | Frozen — delete on oldeworld shutdown                                                                                         |

### Zone mapping

Each cluster declares its default TLS zone via an **unencrypted** single-line
marker file:

```
k3s/<cluster>/cluster.tls.zone       # contents: `freecodecamp-net` or `freecode-camp`
```

| Cluster        | `cluster.tls.zone` | Wildcard source                                          |
| -------------- | ------------------ | -------------------------------------------------------- |
| gxy-management | `freecodecamp-net` | `global/tls/freecodecamp-net.{crt,key}.enc`              |
| gxy-launchbase | `freecodecamp-net` | `global/tls/freecodecamp-net.{crt,key}.enc`              |
| gxy-static     | `freecode-camp`    | `global/tls/freecode-camp.{crt,key}.enc` (added Phase 2) |
| gxy-cassiopeia | `freecode-camp`    | `global/tls/freecode-camp.{crt,key}.enc` (added Phase 2) |

### Extended `just deploy` probe order

```
# TLS resolution for `just deploy <cluster> <app>`:
if k3s/<cluster>/<app>.tls.crt.enc exists:
    use per-app override
elif k3s/<cluster>/cluster.tls.zone exists:
    zone = $(cat k3s/<cluster>/cluster.tls.zone)
    if global/tls/$zone.crt.enc exists:
        use zone wildcard
    else:
        error: zone declared but wildcard missing
else:
    skip TLS stage (no override + no zone → no TLS on this app)
```

No change to per-app kustomization.yaml. Generated Secret name
(`<app>-tls-cloudflare`) unchanged. Ephemeral decrypt path
(`secrets/tls.{crt,key}`) unchanged.

## Decision Index

| ID  | Decision                                                                                                                                                                  | Rationale                                                          | Alternatives                                                                  |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| D1  | Store CF Origin wildcard once per zone at `global/tls/<zone>.{crt,key}.enc`                                                                                               | Single source of truth; single re-encrypt on rotation              | cert-manager + CF DNS-01 (deferred — adds controller + API scope)             |
| D2  | Zone = unencrypted marker file `k3s/<cluster>/cluster.tls.zone`                                                                                                           | Plain text, grep-friendly, survives sops errors                    | Put zone inside helm values (couples to chart); env var (invisible)           |
| D3  | Per-app `.tls.*.enc` override only when app needs a cert ≠ cluster zone                                                                                                   | Preserve escape hatch without default duplication                  | Always use zone (no override); always per-app (status quo)                    |
| D4  | Keep top-level `argocd/`/`windmill/`/`zot/` as reserved platform-wide namespaces                                                                                          | Universe platform pattern; document explicitly in README           | Delete placeholders (loses convention marker); move under `platform/` (churn) |
| D5  | Leave `appsmith/` + `outline/` + `docker/oldeworld/` + `k8s/o11y/` in place                                                                                               | Legacy consumers still live; retire together post-Universe launch  | Move under `legacy/` now (churn for no gain while still referenced)           |
| D6  | Backfill `k3s/gxy-launchbase/woodpecker.tls.{crt,key}.enc` by re-encrypting the wildcard AND simultaneously populate `global/tls/freecodecamp-net.*.enc` from same source | Bootstrap drift fixed; woodpecker becomes first zone-fallback user | Only create `global/tls/` (launchbase source still missing until next deploy) |
| D7  | Encrypt `k3s/gxy-management/windmill-backup.secrets.env.enc` from real S3 creds before Phase 4                                                                            | Backup-cronjob re-enable is prerequisite to #22 step-1             | Defer backup — unblocks #22 immediately but leaves DR gap                     |
| D8  | argocd + zot `.secrets.env.sample` stubs — audit whether apps actually need runtime dotenv; encrypt if yes, delete stub if no                                             | Don't keep dead samples; don't invent secrets apps don't consume   | Encrypt empty placeholder (clutter); leave stubs (status-quo confusion)       |

## Migration phases

| Phase | Action                                                                                                                                                                                                                                                                                                       | Scope                                         | Rollback                                                                                      |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------- | --------------------------------------------------------------------------------------------- |
| 1     | This RFC + operator tick of Decision Index                                                                                                                                                                                                                                                                   | Docs only                                     | Discard RFC                                                                                   |
| 2     | Create `global/tls/freecodecamp-net.{crt,key}.enc` (from existing `windmill.tls.*.enc` decrypt). Add `cluster.tls.zone` markers. Backfill `k3s/gxy-launchbase/woodpecker.tls.*.enc` + `k3s/gxy-management/windmill-backup.secrets.env.enc`. Validate via `just secret-verify-all`.                           | infra-secrets only (no live impact)           | `git revert` in infra-secrets                                                                 |
| 3     | Extend `just deploy` recipe with zone-fallback probe. Local dry-run (decrypt + cleanup trap) against every (cluster, app) pair.                                                                                                                                                                              | infra repo only (justfile)                    | `git revert` in infra                                                                         |
| 4     | Live reconcile: `just deploy gxy-management windmill` (expect no-diff or cert-secret update). Repeat argocd. Repeat `just deploy gxy-launchbase woodpecker`.                                                                                                                                                 | Live clusters — idempotent kubectl apply      | `kubectl apply -k` with old secret contents (tls unchanged on rotation; nothing to roll back) |
| 5     | Delete `k3s/gxy-management/{argocd,windmill,zot}.tls.{crt,key}.enc` once Phase 4 green. Clean disk residue `apps/<app>/manifests/base/secrets/tls.{crt,key}`. Uncomment `backup-cronjob.yaml` + `windmill-backup-s3` secretGenerator in windmill kustomization; `just deploy gxy-management windmill` again. | infra-secrets + infra repos                   | Restore deleted .enc from prior commit                                                        |
| 6     | Docs sync: infra-secrets/README.md (two-scope table), all 6 flight-manuals §Pre-flight, `00-index.md`, runbook §Preconditions + §Touchpoints.                                                                                                                                                                | Docs only                                     | `git revert`                                                                                  |
| 7     | Run Windmill backup via restored CronJob (or `just windmill-backup gxy-management` if cron cadence too slow). Confirm pg_dump lands in configured S3 target. Capture fresh `.backups/windmill-<ts>.sql.gz` if justfile backup.                                                                               | Live gxy-management — read-only DB + write S3 | Backup is additive; no rollback needed                                                        |

## Exit criteria

- [ ] `just secret-verify-all` exits 0 across repo.
- [ ] `rtk grep -rn 'cloudflare-origin' infra-secrets/` → 0 matches (new convention uses `<zone>.{crt,key}.enc`).
- [ ] Three `k3s/gxy-management/{argocd,windmill,zot}.tls.*.enc` files deleted from infra-secrets HEAD.
- [ ] `infra-secrets/global/tls/freecodecamp-net.{crt,key}.enc` present + decrypts.
- [ ] `k3s/gxy-launchbase/woodpecker.tls.{crt,key}.enc` OR zone-fallback path working (operator verifies no unencrypted source).
- [ ] `k3s/gxy-management/windmill-backup.secrets.env.enc` present + decrypts.
- [ ] `backup-cronjob.yaml` re-enabled in windmill kustomization.
- [ ] Windmill pg_dump written to configured S3 target within last 24h.
- [ ] All 6 flight-manuals + 00-index reference actual filenames; zero stale references.
- [ ] Runbook §Preconditions lists actual filenames.
- [ ] #22 unblocks (TaskUpdate removes blockedBy=#36).

## Open questions

| ID  | Question                                                                                                                          | Default                                                                                                                               |
| --- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| OQ1 | Do argocd + zot apps actually need `.secrets.env.enc`? (Check chart values + manifest env refs.)                                  | Resolve during Phase 2; encrypt or delete per D8.                                                                                     |
| OQ2 | Should `cluster.tls.zone` marker sit in `infra-secrets/k3s/<cluster>/` (source of truth) or in the `infra` repo `k3s/<cluster>/`? | infra-secrets side. Deploy recipe already reads from `{{secrets_dir}}/k3s/<cluster>/`; keeps zone co-located with wildcards.          |
| OQ3 | Rotation runbook — post-MVP write `runbooks/rotate-cf-origin-cert.md`?                                                            | Yes, but out-of-scope for this RFC. Track as separate task.                                                                           |
| OQ4 | `k3s/gxy-launchbase/woodpecker.tls.*.enc` — keep per-app override or rely on zone fallback once ready?                            | Start as per-app override (Phase 2 backfill), migrate to zone fallback in Phase 4 after live reconcile green. Avoids big-bang change. |

## Non-goals

- cert-manager introduction — deferred to post-MVP.
- Moving `appsmith/`, `outline/`, `docker/oldeworld/`, `k8s/o11y/` — deferred to post-Universe launch retirement pass.
- Split firewall per-galaxy (raised in cluster-audit) — deferred post-MVP.
- Etcd snapshot s3-target configuration — orthogonal; Phase 7 references it opportunistically but doesn't block.

## Acknowledgments

Inputs: 2026-04-21 cluster audit (`docs/sprints/2026-04-21/cluster-audit.md`),
HANDOFF naming-convention table, infra-secrets README §Directory Structure,
`just deploy` + `just helm-upgrade` recipes, runtime kubectl inspection of
gxy-management + gxy-launchbase clusters.
