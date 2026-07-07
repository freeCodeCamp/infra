# 12 — Windmill decommission (gxy-management)

Retire and uninstall Windmill from `gxy-management`. Windmill's platform-ops responsibilities have moved to artemis + Hatchet; this runbook removes the now-idle deployment, its data, DNS, and repo footprint.

- **Owner:** operator (cluster mutations, secrets, DNS).
- **Cluster:** `gxy-management` (namespace `windmill`).
- **Design of record:** ADR-020 (durable execution + Windmill role reframe).
- **Tracking:** `.scratchpad/dossier/2026-07-04-universe-consol-decommission` T17.

## Why this is safe now (gate evidence, live-verified 2026-07-07)

Nothing rides on Windmill:

- **Deploy-retention GC** → moved to artemis + Hatchet, live since 2026-06-06 (`hatchet-engine` in ns `artemis`; ADR-020 tranche 1). Windmill's `cleanup_old_deploys` cron is functionally dead.
- **Repo creation / approval (Apollo-11)** → replaced by artemis `/api/repo*`, **enabled in prod** (all 3 `artemis` replicas boot `repo-creation feature enabled`, org `freeCodeCamp-Universe`, create `staff`, approve `gh-artemis-approvers`) + the `universe repo {create,ls,status,approve,reject,rm}` CLI. The Google-Chat intake is unused.
- **Constellation DNS/OIDC/DB provisioning (tranche 2)** → unimplemented anywhere; static-site provisioning already redirected to `universe sites register` (ADR-016). No live flow to migrate.

Re-verify before starting:

```
KUBECONFIG=k3s/gxy-management/.kubeconfig.yaml \
  kubectl -n artemis logs -l app.kubernetes.io/name=artemis | grep 'repo-creation feature enabled'
```

## Pre-flight

1. Confirm no in-flight Windmill work. The intake is dark, so this should be empty, but check the Windmill UI (jobs/schedules) or the app logs for recent flow runs:

   ```
   kubectl -n windmill logs deploy/windmill-workers-default --since=168h | grep -i 'job\|flow' | tail
   ```

1. Confirm the artemis replacement is healthy (see gate evidence above) and that staff know repo creation is now `universe repo create` (CLI), not Google Chat.

## Phase 1 — Final data capture

Windmill's bundled Postgres holds job-run history and schedule state that does **not** round-trip via `wmill sync` — the only copy after teardown is a dump.

1. Confirm the nightly R2 backup pipeline is healthy and take a fresh dump:

   ```
   just inspect-windmill-backup gxy-management
   just backup-windmill gxy-management          # ad-hoc pg_dumpall → .backups/ (local)
   just test-windmill-backup-restore gxy-management   # verifies newest R2 object restores
   ```

1. Archive the local dump somewhere durable outside the cluster (the `windmill-backup` CronJob pushes to R2 `windmill/gxy-management/`; keep at least one dump after the CronJob is deleted).

## Phase 2 — Close the stale IaC cron flag

In the Windmill IaC repo (`../fCC-U/windmill`), the retired cleanup cron is still committed as enabled (it was disabled via the live UI only):

- Edit `workspaces/platform/f/static/cleanup_old_deploys.schedule.yaml` → `enabled: false` (or delete the file). Commit. This prevents a future `wmill sync push` from silently re-enabling a cron that Hatchet already owns.

## Phase 3 — Scale to zero (reversible checkpoint)

```
NS=windmill
kubectl -n $NS scale deploy windmill-app windmill-extra windmill-workers-default windmill-workers-native --replicas=0
kubectl -n $NS get pods            # workers drained; postgres sts still up
```

Observe for a burn-in window if desired — the cluster stays in this reversible state (scale back up to roll back) until Phase 4. Take one more `pg_dumpall` (`just backup-windmill gxy-management`) as a final safety net before deleting storage.

## Phase 4 — Remove Kubernetes resources

Windmill deploys as helm (chart) **+** kustomize (manifests). Tear down both:

```
NS=windmill
# helm release (windmill-labs chart)
helm --kubeconfig k3s/gxy-management/.kubeconfig.yaml -n $NS uninstall windmill
# kustomize base (gateway, httproutes, namespace, backup-cronjob)
kubectl -n $NS delete -k k3s/gxy-management/apps/windmill/manifests/base/
# bundled Postgres PVC — only after Phase-1 backup is confirmed restorable
kubectl -n $NS delete pvc data-windmill-postgresql-0
kubectl delete namespace $NS
```

## Phase 5 — Security + DNS

1. Remove the `windmill` PSS-admission exemption: `k3s/gxy-management/cluster/security/pss-admission.yaml` (drop the `windmill` list entry ~line 25 + the explanatory comment ~line 6). Re-apply the cluster security kustomization.
1. The `Gateway` + `HTTPRoute` for `windmill.freecodecamp.net` are removed by the Phase-4 kustomize delete. Delete the `windmill.freecodecamp.net` DNS record in Cloudflare.
1. **Wildcard origin cert:** Windmill was the sole live consumer of the shared `freecodecamp.net` Cloudflare origin cert (runbook 10). Decide whether to keep rotating it (dormant argocd/zot reactivation) or retire it. Record the call.

## Phase 6 — Repo cleanup (this repo)

- **justfile:** delete `backup-windmill`, `inspect-windmill-backup`, `test-windmill-backup-restore`; remove or rewrite `register` (it shells out to the Windmill constellation flow — superseded by `universe sites register`, ADR-016); drop `windmill/.env.enc` from the secrets-classification allowlist (~line 268).
- **k3s:** delete `k3s/gxy-management/apps/windmill/`.
- **docs:** delete `docs/runbooks/06-windmill-pg-backup.md`; prune Windmill mentions from `docs/runbooks/00-index.md`, `docs/flight-manuals/{00-index,UNIVERSE,gxy-management,gxy-launchbase,gxy-cassiopeia}.md`, `docs/infra-guides/{k3s-general,cilium-cnp}.md`, `docs/architecture/{rfc-gxy-cassiopeia-ga,rfc-secrets-layout}.md`, and refresh `docs/architecture/universe-state-2026-07-06.md`.

Do the docs prune **after** Phase 4 so the docs never claim a retirement that hasn't happened.

## Phase 7 — Secrets (companion PR, separate repo)

In `../infra-secrets` (sops+age — its own PR, never from this repo): retire `k3s/gxy-management/windmill.values.yaml.enc`, `k3s/gxy-management/windmill-backup.secrets.env.enc`, and the top-level `windmill/.env.enc` namespace. Do this last so no live config points at a deleted app while a decrypt path lingers.

## Phase 8 — Archive the Windmill IaC repo

Archive `../fCC-U/windmill` read-only (do **not** delete) — it is the auditable record of the Apollo-11 / repo_mgmt / cleanup flows, in case a future dedicated user-facing Windmill instance (a fresh decision, likely backoffice, only if a user requests one) needs the prior designs.

## Phase 9 — Governance

- Land the ADR-020 amendment (demote → retire) + the cascading updates (ADR-001/003/004/005/007/008/009/010/011/012/018/019 + `decisions/README.md` + spike-plan) recording the full retirement.
- Flip consol dossier T17 → `x` with the teardown commit cite; refresh §X.

## Rollback

Reversible through **Phase 3** (scale back up). After Phase 4 (helm uninstall + PVC delete), recovery requires re-`just release gxy-management windmill` and restoring the Phase-1 `pg_dumpall` into a fresh `windmill-postgresql`.
