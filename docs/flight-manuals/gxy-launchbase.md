# Flight Manual — gxy-launchbase

Supply-chain galaxy. Hosts Woodpecker CI + CNPG-backed Postgres for Universe
pipeline builds. Think "GitHub Actions layer" where staff/platform builds run.

Last rebuild-verified: 2026-04-20.

## Pre-flight

```
cd ~/DEV/fCC/infra
just ansible-install
just secret-verify-all
```

- All secrets decrypt OK
- age key on local machine (`~/.config/sops/age/keys.txt`)
- `infra-secrets/global/tls/freecodecamp-net.{crt,key}.enc` — CF Origin
  wildcard for the zone, picked up via
  `infra/k3s/gxy-launchbase/cluster.tls.zone` = `freecodecamp-net`
- `infra-secrets/k3s/gxy-launchbase/` contains:
  - `woodpecker.values.yaml.enc` (chart overlay — `server.env` with OAuth + org gate)
  - `woodpecker.secrets.env.enc` (`WOODPECKER_SERVER_SECRET`,
    `WOODPECKER_AGENT_SECRET`, `WOODPECKER_GITHUB_CLIENT`,
    `WOODPECKER_GITHUB_SECRET`)
  - `woodpecker-backup.secrets.env.enc` (`ACCESS_KEY_ID`, `SECRET_ACCESS_KEY`
    — DO Spaces for CNPG base backups)

## Phase 13: Infrastructure (ClickOps — codify in OpenTofu)

### 13.1 DO Droplets

- Create 3× `s-4vcpu-8gb-amd` in FRA1
- Names: `gxy-vm-launchbase-k3s-{1,2,3}`
- Image: Ubuntu 24.04, VPC: `universe-vpc-fra1`, Tag: `gxy-launchbase-k3s`
- Cloud-init: `cloud-init/basic.yml`

### 13.2 DO Cloud Firewall

- Add tag `gxy-launchbase-k3s` to existing `gxy-fw-fra1`

### 13.3 Tailscale

```
just play tailscale--0-install gxy_launchbase_k3s
just play tailscale--1b-up-with-ssh gxy_launchbase_k3s
```

Verify: `tailscale status | grep gxy-vm-launchbase`

## Phase 14: Cluster bootstrap

```
cd k3s/gxy-launchbase
just play k3s--bootstrap gxy_launchbase_k3s
```

Per-galaxy config lives in `ansible/inventory/group_vars/gxy_launchbase_k3s.yml`
(cluster CIDR `10.6.0.0/16`, service CIDR `10.16.0.0/16`, `cilium_cluster_id: 3`).
etcd snapshots land in `s3://net-freecodecamp-universe-backups/etcd/gxy-launchbase/`
every 6h, 20 retained.

### Post-bootstrap checks

```
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get nodes -o wide
# All 3 Ready, InternalIP = VPC IPs (10.110.0.x)

kubectl get pods -n kube-system
# All Running, no CrashLoopBackOff
```

## Phase 15: CNPG + Postgres cluster

### 15.1 Install CNPG operator

```
just helm-upgrade gxy-launchbase cnpg-system
```

Chart at `k3s/gxy-launchbase/apps/cnpg-system/charts/`. The operator is
cluster-scoped; installs CRDs (`Cluster`, `ScheduledBackup`, `Pooler`, etc.)
and the controller in namespace `cnpg-system`.

### 15.2 Verify

```
kubectl get pods -n cnpg-system
# cnpg-controller-manager Running

just crds-grep gxy-launchbase cnpg
# postgresql.cnpg.io CRDs present
```

The `Cluster` CR and `ScheduledBackup` for `woodpecker-postgres` are part of
the Woodpecker kustomize base and land in Phase 16.2.

## Phase 16: Woodpecker

### 16.1 Helm install

```
just helm-upgrade gxy-launchbase woodpecker
```

Chart at `k3s/gxy-launchbase/apps/woodpecker/charts/woodpecker/`. The sops
overlay `woodpecker.values.yaml.enc` injects `server.env` with the GitHub
OAuth client, `WOODPECKER_ADMIN=freeCodeCamp-bot,raisedadead,camperbot`,
`WOODPECKER_ORGS=freeCodeCamp-Universe`, `WOODPECKER_OPEN=true`.

### 16.2 Deploy manifests (namespace, Postgres Cluster CR, ScheduledBackup, Gateway, HTTPRoute)

```
just deploy gxy-launchbase woodpecker
```

This decrypts `woodpecker.secrets.env.enc`, `woodpecker-backup.secrets.env.enc`,
and the TLS cert pair, then applies
`k3s/gxy-launchbase/apps/woodpecker/manifests/base/`:

- `namespace.yaml` — `woodpecker` namespace
- `postgres-cluster.yaml` — CNPG `Cluster` CR for `woodpecker-postgres`
- `scheduled-backup.yaml` — 6-hour base backups via `barmanObjectStore` plugin
- `gateway.yaml` — `:80` + `:443` listeners, TLS terminated with
  `woodpecker-tls-cloudflare`
- `httproute.yaml` — routes `woodpecker.freecodecamp.net` to the Woodpecker
  server

Wait for the CNPG cluster to settle before Woodpecker pods recover:

```
just cnpg-wait gxy-launchbase woodpecker woodpecker-postgres
```

### 16.3 Verify

```
kubectl get pods -n woodpecker
# woodpecker-server, woodpecker-agent-*, woodpecker-postgres-{1,2,3} Running

kubectl get cluster -n woodpecker
# woodpecker-postgres  3/3 instances Ready

kubectl get scheduledbackup -n woodpecker
# woodpecker-postgres-base  schedule 0 0 0,6,12,18 * * *

kubectl get gateway -n woodpecker
# woodpecker-gateway Programmed=True

kubectl get httproute -n woodpecker
# woodpecker-route
```

## Phase 17: DNS + access

### 17.1 Get node public IPs

```
doctl compute droplet list --tag-name gxy-launchbase-k3s --format Name,PublicIPv4
```

### 17.2 Cloudflare DNS

- 3× A records: `woodpecker.freecodecamp.net` → launchbase node public IPs
- Proxy: ON (orange cloud)
- SSL mode: Full (Strict)

Without the Cloudflare Origin Certificate at the origin, Traefik serves
`CN=TRAEFIK DEFAULT CERT` and CF Full (Strict) rejects the origin with
error 526 — the cert in `woodpecker-tls-cloudflare` (Phase 16.2) is what
prevents that.

### 17.3 Auth gate

Per D22 resolution (sprint 2026-04-21): OAuth org-gate is canonical.
Woodpecker uses `WOODPECKER_ORGS=freeCodeCamp-Universe` + `WOODPECKER_OPEN=true`
to admit only GitHub org members. No CF Access layer.

See [../runbooks/gxy-launchbase.md](../runbooks/gxy-launchbase.md) for OAuth
provisioning details.

### 17.4 Smoke test

```
curl -sI https://woodpecker.freecodecamp.net
# 200
```

- Browser: visit `https://woodpecker.freecodecamp.net`
- Log in via GitHub — OAuth grant page shows `freeCodeCamp-Universe` scope

## Phase 18: OAuth app provisioning

See [../runbooks/woodpecker-oauth-app.md](../runbooks/woodpecker-oauth-app.md)
when it lands (tracked as `gxy-static-k7d.10`). Inline procedure until then:

1. GitHub → `freeCodeCamp-Universe` org → Settings → Developer settings →
   OAuth Apps → New OAuth App
2. Application name: `Woodpecker CI`
3. Homepage URL: `https://woodpecker.freecodecamp.net`
4. Authorization callback URL: `https://woodpecker.freecodecamp.net/authorize`
5. Copy Client ID + Client Secret into
   `infra-secrets/k3s/gxy-launchbase/woodpecker.values.yaml.enc` under
   `server.env.WOODPECKER_GITHUB_CLIENT` + `server.env.WOODPECKER_GITHUB_SECRET`
6. Mutate via `sops --input-type yaml --output-type yaml <file>` — `sops <file>`
   auto-detects `.enc` as binary and errors out
7. Re-run `just helm-upgrade gxy-launchbase woodpecker` to roll the new
   credentials into the chart

## Backups

### What is backed up

| Data                 | Method                                          | Schedule                | Storage                                                       | Restore time                   |
| -------------------- | ----------------------------------------------- | ----------------------- | ------------------------------------------------------------- | ------------------------------ |
| etcd (cluster state) | k3s built-in S3 snapshots                       | Every 6h, 20 retained   | `s3://net-freecodecamp-universe-backups/etcd/gxy-launchbase/` | Minutes (k3s native restore)   |
| woodpecker-postgres  | CNPG base backup + continuous WAL (R2)          | 6h base, WAL continuous | R2 bucket via `barmanObjectStore` plugin                      | Minutes–hours (PITR)           |
| Woodpecker app state | Not backed up — reproduced from Postgres        | N/A                     | N/A                                                           | Re-attach chart to restored DB |
| Helm releases        | Not backed up — reproducible from values        | N/A                     | infra repo                                                    | `just helm-upgrade`            |
| TLS certs, secrets   | Not backed up — reproducible from infra-secrets | N/A                     | infra-secrets repo                                            | `just deploy`                  |

CNPG base backups are scheduled by the `woodpecker-postgres-base`
`ScheduledBackup` CR (6-hour cadence, aligns with etcd snapshots for
consistent recovery planning). WAL archiving runs continuously.

The earlier `barmanObjectStore` native mode was deprecated in CNPG ≥ 1.26;
the plugin-based replacement is now the default. If the cluster ever
deadlocks on `restore_command`, drop `spec.backup` from the `Cluster` CR
temporarily and re-apply the `ScheduledBackup` after the cluster is healthy.
A belt-and-braces weekly `pg_dump` export remains an operator-side
compensating control until plugin operation has a few months of track record.

### Restore woodpecker-postgres from backup

Recovery from the latest base backup + WAL replay:

```
kubectl delete cluster -n woodpecker woodpecker-postgres
# Re-apply the Cluster CR with spec.bootstrap.recovery pointing at the same
# barman-cloud backup source — see CNPG recovery docs.
kubectl apply -k k3s/gxy-launchbase/apps/woodpecker/manifests/base/
just cnpg-wait gxy-launchbase woodpecker woodpecker-postgres
```

For a full cluster-reset drill see
[CNPG recovery](https://cloudnative-pg.io/documentation/current/recovery/).

### Restore etcd from S3

Same procedure as gxy-management — see
[gxy-management.md](gxy-management.md) → Backups → Restore etcd from S3.
Substitute `etcd/gxy-launchbase` for the folder.

## Usage — first pipeline

1. In the Woodpecker UI, hit **Add repository** and pick a repo under
   `freeCodeCamp-Universe` (OAuth grant must include that org).
2. Drop a minimal `.woodpecker.yaml` in the repo:

   ```yaml
   steps:
     smoke:
       image: alpine:3.20
       commands:
         - echo "pipeline runs on gxy-launchbase"
   ```

3. Push to a branch → Woodpecker picks it up → pipeline runs on the agent.
4. Confirm via `kubectl logs -n woodpecker deploy/woodpecker-agent` (or via
   the UI).

Scale agents by editing `server.env.WOODPECKER_MAX_WORKFLOWS` in the sops
overlay, then re-run `just helm-upgrade gxy-launchbase woodpecker`.

## Teardown

Destructive: this kills the CNPG cluster and Woodpecker state. Export any
needed pipeline state before teardown.

### Cluster only (preserves VMs)

```
just play k3s--teardown gxy_launchbase_k3s
```

### Full teardown (VMs too)

```
just play k3s--teardown gxy_launchbase_k3s
doctl compute droplet delete gxy-vm-launchbase-k3s-1 gxy-vm-launchbase-k3s-2 gxy-vm-launchbase-k3s-3 --force
```

Also pull the DNS records for `woodpecker.freecodecamp.net`. No CF Access
application to delete (org-gate canonical per D22).
