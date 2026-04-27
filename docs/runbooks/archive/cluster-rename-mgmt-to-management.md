# Runbook — Rename `gxy-mgmt` → `gxy-management`

**Blast radius:** gxy-management serves the whole platform control plane —
ArgoCD, Windmill, (future) Zot. Expect a ~30 min outage window for
`argocd.freecodecamp.net` and `windmill.freecodecamp.net` during cluster
rebuild and DNS propagation. No end-user static-site traffic affected
(gxy-cassiopeia + gxy-static handle that).

**Last verified:** unverified — first execution in sprint 2026-04-21.

## Context

Operator decision (2026-04-21): rename the `mgmt` shorthand to the full
word `management` everywhere. Accepted path: teardown + reprovision,
dogfooding `docs/flight-manuals/gxy-management.md`.

Inconsistency surfaced during audit:

- `infra-secrets/k3s/gxy-management/` already uses full word (no rename).
- `ansible/inventory/group_vars/gxy_mgmt_k3s.yml` + DO droplet tags +
  droplet names use short form — these are the rename targets.

DO inventory plugin derives group names from tags (see
`ansible/inventory/digitalocean.yml` keyed_groups): droplet tag
`gxy-mgmt-k3s` → ansible group `gxy_mgmt_k3s`. So tag rename drives the
group rename downstream.

## Preconditions

- Working tree clean on `feat/k3s-universe`.
- `doctl` authenticated against the Universe DO account.
- age key on operator's local machine (`~/.config/sops/age/keys.txt`).
- `just secret-verify-all` exits 0.
- `infra-secrets` sibling repo at `../infra-secrets` contains:
  - `global/tls/freecodecamp-net.{crt,key}.enc` — CF Origin wildcard
    for the zone; `just deploy` picks it up via
    `infra/k3s/gxy-management/cluster.tls.zone`.
  - `k3s/gxy-management/windmill.values.yaml.enc` — Windmill chart overlay
    (GitHub OAuth, postgres password, oauth config).
  - `k3s/gxy-management/windmill-backup.secrets.env.enc` — Backup cronjob
    secret (PG_PASSWORD + S3 creds for `net-freecodecamp-universe-backups`).
  - Per-app overrides if any app ever diverges from the zone default
    (currently none on gxy-management — argocd/windmill/zot all use the
    shared zone wildcard).
- Latest Windmill backup in S3
  (`s3://net-freecodecamp-universe-backups/windmill/gxy-management/`)
  within the last 24h — triggered via
  `kubectl create job --from=cronjob/windmill-backup` or the 02:00 UTC
  cron cycle. Local `.backups/` from `just windmill-backup gxy-management`
  is acceptable as a second copy.
- ArgoCD state is reproducible from git (Universe apps live in git
  manifests; no ad-hoc applications that live only in-cluster).

## Steps

### 1. Preflight backup

```sh
# Windmill ad-hoc backup to .backups/
cd /Users/mrugesh/DEV/fCC/infra
just windmill-backup gxy-management

# Confirm the dump exists
ls -la k3s/gxy-management/.backups/ | tail -3

# Confirm etcd snapshots present in S3
k3s etcd-snapshot list --s3 \
  --s3-bucket net-freecodecamp-universe-backups \
  --s3-folder etcd/gxy-management \
  --s3-endpoint fra1.digitaloceanspaces.com \
  --s3-region fra1 | tail -5
```

**Verify:** a recent pg_dump in `.backups/` + at least one etcd snapshot
from the last 6h.

### 2. Capture droplet IPs for DNS restoration

```sh
doctl compute droplet list --tag-name gxy-mgmt-k3s --format Name,PublicIPv4
```

**Save the output** — DNS records referencing these IPs need to be
updated to the new droplet IPs after step 7.

### 3. Update repo refs (no live impact)

Touchpoints and rename:

- `ansible/inventory/group_vars/gxy_mgmt_k3s.yml` → `gxy_management_k3s.yml`
- Doc refs in:
  - `docs/architecture/task-gxy-cassiopeia.md`
  - `docs/architecture/rfc-gxy-cassiopeia.md`
  - `docs/flight-manuals/gxy-management.md`
  - `docs/flight-manuals/gxy-static.md` (may mention shared firewall tag)
  - `docs/flight-manuals/gxy-launchbase.md` (cross-refs mgmt backups)
  - `docs/flight-manuals/gxy-cassiopeia.md` (cross-refs mgmt)
  - `docs/infra-guides/gxy-management.md`
  - `docs/infra-guides/k3s-general.md`
  - `docs/sprints/2026-04-21/HANDOFF.md`
  - `CLAUDE.md` — galaxy table
- String substitutions (apply per file via Edit tool or sed-safe script):
  - `gxy-mgmt-k3s` → `gxy-management-k3s` (droplet tags)
  - `gxy_mgmt_k3s` → `gxy_management_k3s` (ansible group)
  - `gxy-vm-mgmt-k3s-` → `gxy-vm-management-k3s-` (droplet names)
  - `gxy-vm-mgmt` (bare) → `gxy-vm-management` (tailscale grep
    patterns)
- Sprint archive under `docs/sprints/archive/` — DO NOT touch. Archives
  are historical.

Commit repo refs:

```sh
git mv ansible/inventory/group_vars/gxy_mgmt_k3s.yml \
        ansible/inventory/group_vars/gxy_management_k3s.yml
# Edit doc refs per the list above
git add -u
git status --short
git commit -m "refactor(naming): gxy-mgmt → gxy-management (repo refs only; infra rename pending)"
```

**Verify:** `rtk grep -rn 'gxy[-_]mgmt' /Users/mrugesh/DEV/fCC/infra
--include='*.md' --include='*.yml' --include='*.yaml' --include='justfile'`
returns zero matches outside `docs/sprints/` (active sprint + archive
docs legitimately narrate the rename and are exempt; all operational
files — ansible, flight-manuals, runbooks — must be clean).

Do **not** push yet. Push after step 10 when the infra is back green.

### 4. Pause ArgoCD auto-sync (keeps it from reconciling during rebuild)

If Universe applications are auto-synced, disable them so they do not try
to reconcile while the cluster is dying / rebuilding:

```sh
export KUBECONFIG=$(pwd)/k3s/gxy-management/.kubeconfig.yaml
for app in $(kubectl -n argocd get applications -o name); do
  kubectl -n argocd patch "$app" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":null}}}'
done
```

**Verify:** `kubectl -n argocd get applications` shows none with
`automated: true`.

### 5. Teardown cluster (preserves VMs)

Dry run ansible first:

```sh
just play k3s--teardown gxy_mgmt_k3s --check
```

Note: `just play` forwards `*args` directly — no `--` separator.

If clean:

```sh
just play k3s--teardown gxy_mgmt_k3s
```

Alternative: skip the teardown play entirely when the rebuild target is
"cluster from scratch" — jump straight to Step 6 droplet delete. The
teardown play gracefully wipes k3s from still-living VMs; if the VMs will
be obliterated anyway, the wipe is redundant.

**Verify:** kubectl contexts fail (expected). `/var/lib/rancher/k3s/`
gone on every node.

### 6. Delete droplets (full teardown)

```sh
doctl compute droplet delete gxy-vm-mgmt-k3s-1 gxy-vm-mgmt-k3s-2 gxy-vm-mgmt-k3s-3 --force
```

VPC + firewall + DO Spaces bucket + R2 buckets persist (shared
infrastructure per `docs/flight-manuals/00-index.md`).

### 7. Provision new droplets with renamed tag + names

Follow `docs/flight-manuals/gxy-management.md` Phase 1 (Infrastructure) +
Phase 1.3 (firewall) with the renamed tag:

- Droplet names: `gxy-vm-management-k3s-{1,2,3}`
- Droplet tag: `gxy-management-k3s`
- Same cloud-init, same sizes, same VPC.

Update existing firewall `gxy-fw-fra1`:

```sh
doctl compute firewall remove-tags <firewall-id> --tag-names gxy-mgmt-k3s
doctl compute firewall add-tags <firewall-id> --tag-names gxy-management-k3s
```

Tailscale:

```sh
just play tailscale--0-install gxy_management_k3s
just play tailscale--1b-up-with-ssh gxy_management_k3s
```

**Verify:** `tailscale status | grep gxy-vm-management` shows 3 new
nodes connected.

### 8. Cluster bootstrap via flight-manual

Follow `docs/flight-manuals/gxy-management.md` Phase 2 onwards — Phase 2
cluster bootstrap, Phase 3 Windmill, Phase 5 ArgoCD, Phase 6 Zot (if
active).

`just play k3s--bootstrap gxy_management_k3s` + `just helm-upgrade
gxy-management windmill` + `just deploy gxy-management windmill` + etc.

**Verify per phase:** checks in the flight-manual exit green.

### 9. Restore state

Windmill restore from pg_dump (captured in step 1) — follow
`docs/flight-manuals/gxy-management.md` §Restore Windmill from backup.

ArgoCD state re-applies from git — `just deploy gxy-management argocd`
replays the manifests. No restore step needed.

**Verify:** `kubectl -n argocd get applications` matches the pre-rebuild
list; Windmill UI shows previous flows, apps, resources.

### 10. Update DNS to new droplet IPs

For each of `windmill.freecodecamp.net`, `argocd.freecodecamp.net`,
`zot.freecodecamp.net` (if active):

- CF DNS dashboard → zone `freecodecamp.net`
- For each A record: replace old IP with the corresponding new droplet
  public IP (captured from step 7 via
  `doctl compute droplet list --tag-name gxy-management-k3s --format
Name,PublicIPv4`)
- Keep proxy ON, SSL Full (Strict)

**Verify:**

```sh
dig +short windmill.freecodecamp.net
# Still returns CF anycast IPs (CF hides origins); open in browser:
curl -sI https://windmill.freecodecamp.net
# 200
curl -sI https://argocd.freecodecamp.net
# 200 (after Access redirect, if any)
```

### 11. Re-enable ArgoCD auto-sync

Reverse step 4 — re-apply `automated` policy to each application manifest
via `just deploy gxy-management <app>` or by `kubectl patch`.

**Verify:** `kubectl -n argocd get applications -o
jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.syncPolicy.automated}{"\n"}{end}'`
shows `automated` set for the originally-auto-synced ones.

### 12. Push repo refs

```sh
cd /Users/mrugesh/DEV/fCC/infra
git push origin feat/k3s-universe
```

**Verify:** GitHub shows the rename commit on the branch.

### 13. Field-note journal entry

Append to `~/DEV/fCC-U/Universe/spike/field-notes/infra.md` per GUIDELINES
format:

```
### 2026-MM-DD — gxy-mgmt → gxy-management rename (dogfood of
flight-manual)

- Time to rebuild: ~X min
- Gaps surfaced in `docs/flight-manuals/gxy-management.md`: ...
- Field notes on DO tag reassignment of firewall: ...
- Post-rename invariants to promote during next monthly trim: ...
```

Commit field note; push Universe main.

## Rollback

If rebuild fails after droplet deletion, there is no path back to the old
cluster — the old etcd state is gone. Recovery is "forward": re-execute
the rebuild from step 7 with corrective changes.

If repo refs were committed but rebuild is NOT yet started:

```sh
git revert <rename-commit-sha>
```

If DNS was changed to point at new IPs but clients are unhappy,
temporarily repoint DNS to old IPs — but the old droplets are gone by
then, so there are no old IPs to point at. The mitigation is to complete
the rebuild; no true rollback exists past droplet deletion.

## Exit criteria

- [ ] Zero matches of `gxy[-_]mgmt` in live repo tree (outside
      `docs/sprints/` — active sprint + archive docs exempt).
- [ ] DO droplets: 3× `gxy-vm-management-k3s-{1,2,3}` with tag
      `gxy-management-k3s`.
- [ ] `kubectl --kubeconfig=k3s/gxy-management/.kubeconfig.yaml get
nodes` → all 3 Ready.
- [ ] `curl -sI https://windmill.freecodecamp.net` → 200.
- [ ] `curl -sI https://argocd.freecodecamp.net` → 200.
- [ ] ArgoCD applications list matches pre-rebuild.
- [ ] Windmill resources + flows + apps restored from pg_dump, validated
      via `wmill sync pull` in the windmill repo.
- [ ] Field note entry appended to `spike/field-notes/infra.md`.
- [ ] Rename commit pushed on `feat/k3s-universe`.

## Alternative: in-place rename (not recommended)

If teardown is unacceptable, the in-place path exists but is risky:

1. Repo refs + `group_vars` filename rename (same as step 3 above)
2. DO tag rename per droplet (not rename — add new tag, remove old)
3. Firewall tag swap (same as step 7)
4. Droplet rename (cosmetic only; does not change IPs or cluster state)
5. Update `gxy-fw-fra1` tag attachments
6. Re-run ansible plays for idempotence (`just play k3s--cluster
gxy_management_k3s` — expect no changes)

This path is untested and leaves droplet naming inconsistent with the
tag during the transition window. The teardown path above is the
operator-chosen canonical.
