# RFC: Secrets Layout — Two-Scope Convention + Shared Wildcard Cert

**Date:** 2026-04-22 **Status:** Accepted (implemented 2026-04-22) **Target Release:** Pre-#22 (rename exec gate) **Author:** Infra team **Related:** ADR-003 (Universe topology), ADR-011 (admin plane + secrets), ADR-012 (DR — parked) **Gates:** sprint task #22 (gxy-mgmt → gxy-management reprovision)

## Summary

Formalize `infra-secrets` layout into two explicit scopes — platform-wide (`<app>/`, `global/`) and cluster-local (`k3s/<cluster>/`). Deduplicate the `*.freecodecamp.net` Cloudflare Origin wildcard into a single canonical source at `global/tls/<zone>.{crt,key}.enc`. Extend `just release` with a zone-fallback probe so apps that need the wildcard don't each carry a copy. Backfill missing `.enc` assets flagged during the 2026-04-21 audit (wooodpecker TLS, Windmill backup S3). Sync all flight-manuals + the rename runbook + infra-secrets README to match.

Out of scope: legacy retirement of `appsmith/` + `outline/` + `docker/`

- `k8s/o11y/` — handled post-Universe launch.

## Motivation

The 2026-04-21 cluster audit surfaced drift that blocks task #22:

- Wildcard `*.freecodecamp.net` origin cert is encrypted **three times** on gxy-management (argocd / windmill / zot pairs), once on gxy-launchbase **manifest only — no `.enc` source file exists**, and zero times on gxy-static + gxy-cassiopeia even though they serve `freecode.camp` (different zone).
- `k3s/gxy-launchbase/woodpecker.tls.{crt,key}.enc` is MISSING from `infra-secrets` despite `woodpecker-tls-cloudflare` Secret running in cluster for 27h+. Source-of-truth broken.
- `k3s/gxy-management/windmill-backup.secrets.env.enc` is MISSING. Only `.sample` stub. `backup-cronjob.yaml` commented out in kustomization with "TODO re-enable". Blocks #22 step-1 (pre-teardown backup).
- Rename runbook §Preconditions names `.enc` files that don't exist — operator misread risk during live exec.
- Classification confusion: top-level `argocd/` / `windmill/` / `zot/` (Universe platform-wide, reserved) was nearly misclassified as legacy during audit. Need explicit documented convention.

## Current state (verified 2026-04-21)

### infra-secrets tree (trimmed)

```text
.sops.yaml                       # single path_regex `.*` → platform age key
README.md                        # existing directory-structure doc
global/.env.enc                  # platform-wide tokens (CF, Tailscale, HCP, ...) — opt-in via INFRA_ADMIN=1 (2026-07-17), never auto-loaded
r2-read/.env.enc                 # read-only R2 keys (added 2026-05-12) — same INFRA_ADMIN gate
do-primary/.env.enc              # DO API token — legacy account
do-universe/.env.enc             # DO API token — Universe account
argocd/.env.sample               # (empty — reserved platform-wide namespace)
windmill/.env.sample             # (empty — reserved platform-wide namespace)
zot/.env.sample                  # (empty — reserved platform-wide namespace)
appsmith/.env.enc                # LEGACY (oldeworld Swarm)
outline/.env.enc                 # LEGACY (oldeworld Swarm)
docker/oldeworld/*.env.{enc,sample}   # LEGACY
k8s/o11y/*                       # legacy managed k8s cluster — DELETED 2026-07-14 (infra-secrets ed460a3)
k3s/<cluster>/<app>.values.yaml.enc         # helm chart overlay
k3s/<cluster>/<app>.secrets.env.enc         # dotenv → kustomize secretGenerator
k3s/<cluster>/<app>-backup.secrets.env.enc  # backup-specific dotenv (suffix `-backup`)
k3s/<cluster>/<app>.tls.{crt,key}.enc       # per-app TLS
k3s/<cluster>/kubeconfig.yaml.enc           # encrypted kubeconfig
scratchpad/                      # dev scratch
```

### Deploy pipeline (existing `just release <cluster> <app>`)

```text
for suffix in '.secrets.env.enc' '.tls.crt.enc' '.tls.key.enc' '-backup.secrets.env.enc':
    if infra-secrets/k3s/<cluster>/<app><suffix> exists:
        sops -d → k3s/<cluster>/apps/<app>/manifests/base/secrets/<plain-name>
kubectl apply -k apps/<app>/manifests/base/
trap cleanup decrypted files on exit
```

`just release <cluster> <app>` similarly probes `infra-secrets/k3s/<cluster>/<app>.values.yaml.enc`.

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

| Scope                             | Path shape                                                    | What lives here                                                                                                               |
| --------------------------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| **Platform-wide direnv**          | `<namespace>/.env.enc`                                        | Global tokens loaded by direnv on `cd infra/`                                                                                 |
| **Platform-wide per-app**         | `<app>/.env.enc`                                              | Cross-cluster Universe app secrets (reserved today; empty `.sample` stubs for `argocd`, `windmill`, `zot` mark the namespace) |
| **Platform-wide TLS**             | `global/tls/<zone>.{crt,key}.enc`                             | CF Origin wildcards per DNS zone                                                                                              |
| **Cluster-local helm**            | `k3s/<cluster>/<app>.values.yaml.enc`                         | Helm chart value overlay                                                                                                      |
| **Cluster-local secrets**         | `k3s/<cluster>/<app>.secrets.env.enc`                         | dotenv → kustomize secretGenerator                                                                                            |
| **Cluster-local backup**          | `k3s/<cluster>/<app>-backup.secrets.env.enc`                  | `-backup` suffix convention                                                                                                   |
| **Cluster-local TLS override**    | `k3s/<cluster>/<app>.tls.{crt,key}.enc`                       | Only when the cluster/app needs a cert distinct from the zone default                                                         |
| **Cluster-local kubeconfig**      | `k3s/<cluster>/kubeconfig.yaml.enc`                           | Encrypted kubeconfig                                                                                                          |
| **Legacy (retire post-Universe)** | `appsmith/`, `outline/`, `docker/oldeworld/`, ~~`k8s/o11y/`~~ | Frozen — delete on oldeworld shutdown (`k8s/o11y/` decommissioned 2026-07-14, see D5a)                                        |

### Zone mapping

Each cluster declares its default TLS zone via an **unencrypted** single-line marker file:

```text
k3s/<cluster>/cluster.tls.zone       # contents: `freecodecamp-net` or `freecode-camp`
```

| Cluster        | `cluster.tls.zone` | Wildcard source                                          |
| -------------- | ------------------ | -------------------------------------------------------- |
| gxy-management | `freecodecamp-net` | `global/tls/freecodecamp-net.{crt,key}.enc`              |
| gxy-launchbase | `freecodecamp-net` | `global/tls/freecodecamp-net.{crt,key}.enc`              |
| gxy-static     | `freecode-camp`    | `global/tls/freecode-camp.{crt,key}.enc` (added Phase 2) |
| gxy-cassiopeia | `freecode-camp`    | `global/tls/freecode-camp.{crt,key}.enc` (added Phase 2) |

### Extended `just release` probe order

```text
# TLS resolution for `just release <cluster> <app>`:
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

No change to per-app kustomization.yaml. Generated Secret name (`<app>-tls-cloudflare`) unchanged. Ephemeral decrypt path (`secrets/tls.{crt,key}`) unchanged.

## Decision Index

| ID  | Decision                                                                                                                                                                                                                                                                                                                                                                                                              | Rationale                                                                                                                     | Alternatives                                                                  |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| D1  | Store CF Origin wildcard once per zone at `global/tls/<zone>.{crt,key}.enc`                                                                                                                                                                                                                                                                                                                                           | Single source of truth; single re-encrypt on rotation                                                                         | cert-manager + CF DNS-01 (deferred — adds controller + API scope)             |
| D2  | Zone = unencrypted marker file `k3s/<cluster>/cluster.tls.zone`                                                                                                                                                                                                                                                                                                                                                       | Plain text, grep-friendly, survives sops errors                                                                               | Put zone inside helm values (couples to chart); env var (invisible)           |
| D3  | Per-app `.tls.*.enc` override only when app needs a cert ≠ cluster zone                                                                                                                                                                                                                                                                                                                                               | Preserve escape hatch without default duplication                                                                             | Always use zone (no override); always per-app (status quo)                    |
| D4  | Keep top-level `argocd/`/`windmill/`/`zot/` as reserved platform-wide namespaces                                                                                                                                                                                                                                                                                                                                      | Universe platform pattern; document explicitly in README                                                                      | Delete placeholders (loses convention marker); move under `platform/` (churn) |
| D4a | **2026-07-07 update:** `windmill/` namespace retired — unlike `argocd`/`zot` (still reserved-but-dormant), Windmill was built, deployed, and then fully decommissioned; its envelopes (`windmill.values.yaml.enc`, `windmill-backup.secrets.env.enc`, top-level `windmill/.env.enc`) are removed from `infra-secrets`                                                                                                 | Windmill's platform-ops role moved to artemis + Hatchet (ADR-020)                                                             | n/a — historical record of D4's outcome for the `windmill/` slot              |
| D5  | Leave `appsmith/` + `outline/` + `docker/oldeworld/` + ~~`k8s/o11y/`~~ in place                                                                                                                                                                                                                                                                                                                                       | Legacy consumers still live; retire together post-Universe launch                                                             | Move under `legacy/` now (churn for no gain while still referenced)           |
| D5a | **2026-07-14 update:** `k8s/o11y/` decommissioned — the do-primary DOKS `o11y-cluster` (nyc3) was deleted with its associated load balancers + volumes; envelopes `kubeconfig.yaml.enc`, `o11y.secrets.env.enc`, `o11y.tls.{crt,key}.enc` removed from `infra-secrets/k8s/o11y/`. oncall swarm logging moved from loki to json-file. `appsmith/` + `outline/` + `docker/oldeworld/` remain pending oldeworld shutdown | o11y served the retiring legacy swarm; api already shipped to Sentry, oncall was the last live producer and is now local-only | n/a — historical record of D5's partial outcome                               |
| D6  | Backfill `k3s/gxy-launchbase/woodpecker.tls.{crt,key}.enc` by re-encrypting the wildcard AND simultaneously populate `global/tls/freecodecamp-net.*.enc` from same source                                                                                                                                                                                                                                             | Bootstrap drift fixed; woodpecker becomes first zone-fallback user                                                            | Only create `global/tls/` (launchbase source still missing until next deploy) |
| D7  | Encrypt `k3s/gxy-management/windmill-backup.secrets.env.enc` from real S3 creds before Phase 4                                                                                                                                                                                                                                                                                                                        | Backup-cronjob re-enable is prerequisite to #22 step-1                                                                        | Defer backup — unblocks #22 immediately but leaves DR gap                     |
| D8  | argocd + zot `.secrets.env.sample` stubs — audit whether apps actually need runtime dotenv; encrypt if yes, delete stub if no                                                                                                                                                                                                                                                                                         | Don't keep dead samples; don't invent secrets apps don't consume                                                              | Encrypt empty placeholder (clutter); leave stubs (status-quo confusion)       |

## Migration phases

| Phase | Action                                                                                                                                                                                                                                                                                                                                                                                             | Scope                                         | Rollback                                                                                      |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- | --------------------------------------------------------------------------------------------- |
| 1     | This RFC + operator tick of Decision Index                                                                                                                                                                                                                                                                                                                                                         | Docs only                                     | Discard RFC                                                                                   |
| 2     | Create `global/tls/freecodecamp-net.{crt,key}.enc` (from existing `windmill.tls.*.enc` decrypt). Add `cluster.tls.zone` markers. Backfill `k3s/gxy-launchbase/woodpecker.tls.*.enc` + `k3s/gxy-management/windmill-backup.secrets.env.enc`. Validate via `just verify-secrets`.                                                                                                                    | infra-secrets only (no live impact)           | `git revert` in infra-secrets                                                                 |
| 3     | Extend `just release` recipe with zone-fallback probe. Local dry-run (decrypt + cleanup trap) against every (cluster, app) pair.                                                                                                                                                                                                                                                                   | infra repo only (justfile)                    | `git revert` in infra                                                                         |
| 4     | Live reconcile: `just release gxy-management windmill` (expect no-diff or cert-secret update). Repeat argocd. Repeat `just release gxy-launchbase woodpecker`.                                                                                                                                                                                                                                     | Live clusters — idempotent kubectl apply      | `kubectl apply -k` with old secret contents (tls unchanged on rotation; nothing to roll back) |
| 5     | Delete `k3s/gxy-management/{argocd,windmill,zot}.tls.{crt,key}.enc` once Phase 4 green. Clean disk residue `apps/<app>/manifests/base/secrets/tls.{crt,key}`. Uncomment `backup-cronjob.yaml` + `windmill-backup-r2` secretGenerator in windmill kustomization (renamed from `windmill-backup-s3` 2026-05-18 alongside the awscli→rclone migration); `just release gxy-management windmill` again. | infra-secrets + infra repos                   | Restore deleted .enc from prior commit                                                        |
| 6     | Docs sync: infra-secrets/README.md (two-scope table), all 6 flight-manuals §Pre-flight, `00-index.md`, runbook §Preconditions + §Touchpoints.                                                                                                                                                                                                                                                      | Docs only                                     | `git revert`                                                                                  |
| 7     | Run Windmill backup via restored CronJob (or `just backup-windmill gxy-management` if cron cadence too slow). Confirm pg_dump lands in configured R2 target. Capture fresh `.backups/windmill-<ts>.sql.gz` if justfile backup.                                                                                                                                                                     | Live gxy-management — read-only DB + write R2 | Backup is additive; no rollback needed                                                        |

## Exit criteria

Ticked/annotated 2026-07-05 against live repo + infra-secrets state. Sops decrypt itself is policy-gated for the verifying operator — items needing an actual `sops -d` are marked accordingly; structural envelope checks (JSON/dotenv shape, recipient key, key-name cross-reference) were done via direct file read instead, without decrypting ciphertext.

- [ ] `just verify-secrets` exits 0 across repo. **Not run** — stage 1 requires decrypting every `.enc` (policy-gated). Cross-checked stage 2's path-layout contract by hand against the current `infra-secrets` tree instead (see ticks below); stage 2 only validates path *shape*, so it would not have caught the doc-reference drift found under the flight-manual criterion.
- [x] `rtk grep -rn 'cloudflare-origin' infra-secrets/` → 0 matches (new convention uses `<zone>.{crt,key}.enc`). Verified: 0 matches.
- [x] Three `k3s/gxy-management/{argocd,windmill,zot}.tls.*.enc` files deleted from infra-secrets HEAD. Verified via directory listing: no `argocd.tls.*`, `windmill.tls.*.enc`, or `zot.tls.*.enc` under `k3s/gxy-management/` — only unrelated `.sample` stubs (`argocd.tls.yaml.sample`, `windmill.tls.yaml.sample`, `zot.tls.yaml.sample`) and current `*.values.yaml.enc` remain.
- [x] `infra-secrets/global/tls/freecodecamp-net.{crt,key}.enc` present + decrypts. Present confirmed (both files exist). Decrypt: not run (policy-gated); direct read confirms a structurally valid sops JSON envelope with a single age recipient (`age1dj2tk...`) matching `.sops.yaml`'s sole `path_regex: .*` rule. Operator should confirm actual decrypt with `just verify-secrets` stage 1.
- [ ] `k3s/gxy-launchbase/woodpecker.tls.{crt,key}.enc` OR zone-fallback path working (operator verifies no unencrypted source). **Moot** — Woodpecker retired 2026-05-03 (`docs/runbooks/00-index.md`); `infra-secrets/k3s/gxy-launchbase/` carries only `kubeconfig.yaml.enc` and `k3s/gxy-launchbase/apps/` has only `cnpg-system` (chart-only, no `manifests/base`, so the TLS phase of `just release` never runs there). The zone-fallback mechanism itself is proven live-wired elsewhere: `k3s/gxy-management/cluster.tls.zone` = `freecodecamp-net`, no `windmill.tls.*.enc` override present, `global/tls/freecodecamp-net.{crt,key}.enc` present — windmill's `just release` already rides the fallback branch (`justfile` release recipe, TLS block).
- [x] `k3s/gxy-management/windmill-backup.secrets.env.enc` present + decrypts. Present confirmed. Decrypt: not run (policy-gated); direct read confirms a structurally valid dotenv sops envelope with keys `PG_PASSWORD` / `R2_BUCKET` / `R2_ENDPOINT` / `R2_ACCESS_KEY` / `R2_SECRET_KEY` — matching exactly what `k3s/gxy-management/apps/windmill/manifests/base/backup-cronjob.yaml`'s `secretKeyRef`s expect — and the same single age recipient as above. **Superseded 2026-07-07** — Windmill retired; `windmill.values.yaml.enc` / `windmill-backup.secrets.env.enc` / the top-level `windmill/.env.enc` namespace were removed from `infra-secrets` (`docs/runbooks/archive/2026-07-07/12-windmill-decommission.md` Phase 7).
- [x] `backup-cronjob.yaml` re-enabled in windmill kustomization. Verified: `k3s/gxy-management/apps/windmill/manifests/base/kustomization.yaml` lists `backup-cronjob.yaml` as an active resource (not commented) and declares the `windmill-backup-r2` secretGenerator from `secrets/.backup-secrets.env`. **Superseded 2026-07-07** — `k3s/gxy-management/apps/windmill/` deleted whole (`7ade2f8b`); moot now that Windmill is retired.
- [ ] Windmill pg_dump written to configured S3 target within last 24h. **Live-only** — needs live-cluster + R2 read access to confirm; not checked. **Moot 2026-07-07** — Windmill retired; no further backups apply (final pre-teardown dump captured per decommission runbook Phase 1).
- [ ] All 6 flight-manuals + 00-index reference actual filenames; zero stale references. **Not met.** (a) `UNIVERSE.md` §2.1 lists `artemis.env.enc` under `k3s/gxy-management/`, but the real file lives at top-level `infra-secrets/management/artemis.env.enc` (confirmed present only there; corroborated by `docs/runbooks/05-r2-keys-rotation.md` and this repo's `verify-secrets` stage-2 `management/artemis.env.enc` case, both calling it the pre-Universe artemis SoT). (b) `gxy-cassiopeia.md` §A.1 references `infra-secrets/k3s/gxy-cassiopeia/r2-rw.env.enc` + `r2-ro.env.enc` — neither exists (no `k3s/gxy-cassiopeia/r2-*` files, no top-level `gxy-cassiopeia/` dir either); the actual caddy-ro key lives inside `k3s/gxy-cassiopeia/caddy.values.yaml.enc` per `05-r2-keys-rotation.md`, and no rw key exists for cassiopeia today. `scripts/r2-bucket-verify.sh` independently hard-codes a third, also-nonexistent path (`$SECRETS_DIR/gxy-cassiopeia/r2-rw.env.enc`, missing the `k3s/` prefix) — `just verify-r2` would fail at the file-existence check as written today. (c) the "6" count is itself stale: `gxy-backoffice.md` + `gxy-triangulum.md` were archived to `docs/flight-manuals/archive/2026-05-10/` on 2026-05-10; 4 active flight-manuals + `00-index.md` remain.
- [ ] Runbook §Preconditions lists actual filenames. **Moot** — the flagged runbook was the one-off sprint task #21 ("rename runbook", gxy-mgmt → gxy-management), confirmed **done** in `.scratchpad/sprints/archive/2026-04-21/PLAN.md` and executed per that sprint's `HANDOFF.md` 2026-04-22 entry; it is not a standalone file in current `docs/runbooks/`. The runbook most plausibly meant for this RFC's own Phase 6 sync, `04-secrets-decrypt.md`, uses only generic path patterns in §Preconditions (no concrete filenames) — nothing stale to find there.
- [ ] #22 unblocks (TaskUpdate removes blockedBy=#36). **External tracker — cannot verify from this repo.** `#22`/`#36` don't match this repo's own sprint numbering (`.scratchpad/sprints/archive/2026-04-21/PLAN.md` uses #17–#35 for a different task set; its own #22 "Execute rename via reprovision" is marked **done**). Filesystem evidence corroborates the underlying rename is complete — zero `gxy-mgmt` residue outside archived history, all live paths use `gxy-management` — but the tracker-side unblock action is outside this repo's visibility.

## Open questions

| ID  | Question                                                                                                                          | Default                                                                                                                               |
| --- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| OQ1 | Do argocd + zot apps actually need `.secrets.env.enc`? (Check chart values + manifest env refs.)                                  | Resolve during Phase 2; encrypt or delete per D8.                                                                                     |
| OQ2 | Should `cluster.tls.zone` marker sit in `infra-secrets/k3s/<cluster>/` (source of truth) or in the `infra` repo `k3s/<cluster>/`? | infra-secrets side. Deploy recipe already reads from `{{secrets_dir}}/k3s/<cluster>/`; keeps zone co-located with wildcards.          |
| OQ3 | Rotation runbook — post-MVP write `runbooks/rotate-cf-origin-cert.md`?                                                            | Yes, but out-of-scope for this RFC. Track as separate task.                                                                           |
| OQ4 | `k3s/gxy-launchbase/woodpecker.tls.*.enc` — keep per-app override or rely on zone fallback once ready?                            | Start as per-app override (Phase 2 backfill), migrate to zone fallback in Phase 4 after live reconcile green. Avoids big-bang change. |

## Non-goals

- cert-manager introduction — deferred to post-MVP.
- Moving `appsmith/`, `outline/`, `docker/oldeworld/`, ~~`k8s/o11y/`~~ — deferred to post-Universe launch retirement pass (`k8s/o11y/` done 2026-07-14, see D5a).
- Split firewall per-galaxy (raised in cluster-audit) — deferred post-MVP.
- Etcd snapshot s3-target configuration — orthogonal; Phase 7 references it opportunistically but doesn't block.

## Operational pitfalls

Promotes findings from `Universe/.archive/infra/2026-04-25-secrets-architecture.md` + `Universe/.archive/infra/2026-04-20-pitfalls-reference.md` into canonical guidance. The fixes already live in code (group_vars + playbook post_task); the WHY belongs here.

### Two-account isolation — silent etcd S3 backup failure

The infra repo is a monorepo spanning two DigitalOcean accounts:

| Account      | Purpose                                 | Region | Loaded by            |
| ------------ | --------------------------------------- | ------ | -------------------- |
| **Primary**  | Legacy (ops-backoffice-tools, ops-mgmt) | NYC3   | root `.envrc`        |
| **Universe** | All Universe galaxies                   | FRA1   | `k3s/gxy-<g>/.envrc` |

The direnv hierarchy overrides Primary creds with Universe creds when inside a galaxy directory. **Trap (discovered 2026-04-07):** the Universe Spaces key has historically drifted — `do-universe/.env.enc` carried `DO0036N72V…` while the actual `ops-allbuckets` key was `DO00QGF8PA…`. k3s **logs errors but does not crash** when its etcd S3 backup credentials are wrong. Snapshots silently failed for the entire spike Phase 0 window.

**Symptom shape.** `k3s etcd-snapshot save` reports `failed to test for existence of bucket: Access Denied`. The misleading shape: `aws s3api list-buckets --endpoint-url https://fra1.digitaloceanspaces.com` returns **empty** (not an error) when the key belongs to a different account or lacks bucket access.

**Pre-deploy verification.** From inside `k3s/gxy-<g>/`:

```bash
# direnv loads do-universe/.env.enc here
aws s3 ls "s3://net-freecodecamp-universe-backups/" \
  --endpoint-url https://fra1.digitaloceanspaces.com \
  || echo "✗ key does not see Universe bucket"
```

If the list returns empty without an error, the credentials are likely Primary-account scope. Refresh `do-universe/.env.enc` before provisioning.

### Dotted bucket names break HTTPS wildcard certs

DO Spaces' SSL wildcard `*.fra1.digitaloceanspaces.com` does NOT match multi-label subdomains. A bucket named `net.freecodecamp.universe-backups` resolves to `net.freecodecamp.universe-backups.fra1.digitaloceanspaces.com` in virtual-hosted-style (k3s default `etcd-s3-bucket-lookup-type: auto`), which the wildcard cert refuses → `Access Denied` even with correct credentials.

**Pattern.** Use dashes, not dots, when naming any DO Spaces / R2 bucket Universe owns. Today's canonical bucket is `net-freecodecamp-universe-backups` (dashes). If a dotted name is unavoidable for legacy reasons, force path-style:

```yaml
# ansible/inventory/group_vars/gxy_<g>_k3s.yml
server_config_yaml:
  etcd-s3-bucket-lookup-type: "path"
```

### `extra_service_envs` lineinfile-without-regexp duplicates

The k3s-ansible role (v1.1.1) `extra_service_envs` uses `lineinfile` without `regexp` — new lines appended, old NOT removed on value change. Systemd env files read the first occurrence; stale keys win. This is how the wrong S3 key from the prior section silently persisted after rotation.

**Pattern abandoned.** All etcd-S3 credentials now live in `/etc/rancher/k3s/config.yaml` via playbook post_task using `lineinfile` with `regexp` — idempotent on value change. Do not reach for `extra_service_envs` for any credential rotation surface.

## Acknowledgments

Inputs: 2026-04-21 cluster audit (`docs/sprints/2026-04-21/cluster-audit.md`), HANDOFF naming-convention table, infra-secrets README §Directory Structure, `just release` + `just release` recipes, runtime kubectl inspection of gxy-management + gxy-launchbase clusters.
