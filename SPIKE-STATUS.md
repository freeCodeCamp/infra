# Universe gxy-management Spike Status

Status as of 2026-04-04. This document captures all research, decisions, and progress for the first Universe galaxy cluster deployment.

## Spike Goal

Deploy gxy-management — the first Universe galaxy cluster — on DigitalOcean FRA1 with Cilium CNI, Traefik ingress, and three core services (Windmill, ArgoCD, Zot).

Day 0 deliverable: Windmill accessible to all staff at windmill.freecodecamp.net.

## Architecture Decisions (from Universe ADRs)

| ADR                           | Decision                                       | Impact on This Spike                               |
| ----------------------------- | ---------------------------------------------- | -------------------------------------------------- |
| 001 - Infrastructure Topology | K3s, 4 galaxies planned                        | gxy-management is first, 3-node HA                 |
| 002 - IaC Tooling             | OpenTofu + Ansible                             | Using Ansible for bootstrap, TF migration separate |
| 005 - GitOps                  | ArgoCD multi-cluster                           | Installed on gxy-management, manages all galaxies  |
| 008 - Data Storage            | Rook-Ceph (later), local-path Day 0            | No Longhorn, K3s default storage                   |
| 009 - Networking              | Cilium CNI, Cloudflare TLS, Tailscale SSH only | No cert-manager, origin certs from CF              |
| 010 - Secrets                 | SOPS + age Phase 1, OpenBao Phase 2            | SOPS + age implemented in private repo             |
| 011 - Security                | Pin by SHA, PSS, audit logging                 | PSS + audit policy in cluster config               |
| 015 - Observability           | VictoriaMetrics + ClickHouse + HyperDX         | Not in this spike, future galaxy                   |

## Infrastructure Provisioned

### DigitalOcean (Universe Account, FRA1)

| Resource      | Details                                                         | Status |
| ------------- | --------------------------------------------------------------- | ------ |
| VPC           | `gxy-management-vpc`, 10.110.0.0/20, FRA1                       | Done   |
| Firewall      | `universe-firewall` (80, 443, 6443 from VPC, 22 from Tailscale) | Done   |
| Droplet 1     | `gxy-vm-mgmt-k3s-1`, s-8vcpu-16gb, 104.248.36.250               | Done   |
| Droplet 2     | `gxy-vm-mgmt-k3s-2`, s-8vcpu-16gb, 134.122.69.214               | Done   |
| Droplet 3     | `gxy-vm-mgmt-k3s-3`, s-8vcpu-16gb, 104.248.40.237               | Done   |
| Spaces bucket | `net.freecodecamp.universe-backups` (etcd snapshots)            | Done   |
| Spaces bucket | `net.freecodecamp.universe-registry` (Zot images)               | Done   |

Tag: `gxy-mgmt-k3s` → Ansible inventory group: `gxy_mgmt_k3s`

### Cloud-init

All droplets use `cloud-init/basic.yml` which provides:

- Package updates/upgrades
- fail2ban (5 retries, 3600s ban)
- SSH hardening via `/etc/ssh/sshd_config.d/99-hardening.conf` (no root login, no passwords, pubkey only)
- `freecodecamp` user with sudo NOPASSWD + GitHub SSH key import
- Uses `ssh.service` (Ubuntu 24.04 naming, with `sshd` fallback)

### Cluster Specs

| Setting      | Value                                                    |
| ------------ | -------------------------------------------------------- |
| K3s version  | v1.34.5+k3s1                                             |
| CNI          | Cilium (eBPF, Hubble enabled, kube-proxy replacement)    |
| Pod CIDR     | 10.1.0.0/16                                              |
| Service CIDR | 10.11.0.0/16                                             |
| Ingress      | Traefik via ServiceLB (Klipper), ports 80/443            |
| Storage      | local-path (K3s default)                                 |
| etcd backups | Every 6h → DO Spaces (net.freecodecamp.universe-backups) |
| Security     | Secrets encryption, PSS admission, audit logging         |

## Secrets Architecture

### What Changed

Migrated from ansible-vault (single shared password, whole-file encryption in public repo) to sops+age (per-person keys, value-level encryption in private repo).

Commit: `6ac1504 refactor: migrate secrets from ansible-vault to sops+age`

### How It Works

```
infra-secrets (private repo)              infra (public repo)
─────────────────────────                 ──────────────────────

global/.env.enc ──── direnv ───────────→  env: LINODE_API_TOKEN, TAILSCALE_AUTH_KEY,
                                               HCP_CLIENT_ID, CLOUDFLARE_*, GRAFANA_*

do-primary/.env.enc ── direnv ─────────→  env: DO_API_TOKEN (ops-backoffice-tools)
do-universe/.env.enc ── direnv ────────→  env: DO_API_TOKEN, DO_SPACES_ACCESS_KEY,
                                               DO_SPACES_SECRET_KEY (gxy-management)

k3s/<cluster>/kubeconfig.yaml.enc
  └── just kubeconfig-sync ── sops -d →  k3s/<cluster>/.kubeconfig.yaml (persists)

k3s/<cluster>/<app>.secrets.env.enc
k3s/<cluster>/<app>.tls.crt.enc         k3s/<cluster>/apps/<app>/.../secrets/
k3s/<cluster>/<app>.tls.key.enc           ├── .secrets.env  (temp)
  └── just deploy ── sops -d ─────────→  ├── tls.crt       (temp)
                                          └── tls.key       (temp)
                                            (all deleted after kubectl apply)
```

### direnv Hierarchy

| Directory                   | What Loads                                                  |
| --------------------------- | ----------------------------------------------------------- |
| `infra/` (root)             | Global tokens (Linode, Tailscale, HCP, Cloudflare, Grafana) |
| `k3s/gxy-management/`       | Above + DO_API_TOKEN (universe account) + KUBECONFIG        |
| `k3s/ops-backoffice-tools/` | Above + DO_API_TOKEN (primary account) + KUBECONFIG         |

### Key Files

- `infra/.envrc` — defines `use_sops()` function, loads global tokens, adds ansible venv to PATH
- `infra/k3s/<cluster>/.envrc` — sources parent, loads cluster-specific DO token, sets KUBECONFIG
- `infra-secrets/.sops.yaml` — creation rules with age public keys
- `~/.config/sops/age/keys.txt` — your age private key (from your password manager)

### infra-secrets File Inventory

```
22 encrypted files (.enc)
16 sample files (.sample)

global/.env.enc              — Linode, Tailscale, HCP, Cloudflare, Grafana Cloud tokens
do-primary/.env.enc          — Primary DO team API token
do-universe/.env.enc         — Universe DO team API token
ansible/vault-k3s.yaml.enc  — DO Spaces creds, Tailscale OAuth (YAML format)
appsmith/.env.enc            — Appsmith app secrets
outline/.env.enc             — Outline app secrets

k3s/ops-backoffice-tools/
  kubeconfig.yaml.enc        — Cluster kubeconfig
  appsmith.secrets.env.enc   — Appsmith deployed secrets
  appsmith.tls.crt.enc       — Appsmith Cloudflare origin cert
  appsmith.tls.key.enc       — Appsmith origin private key
  outline.secrets.env.enc    — Outline deployed secrets
  outline.tls.crt.enc        — Outline Cloudflare origin cert
  outline.tls.key.enc        — Outline origin private key

k8s/o11y/
  kubeconfig.yaml.enc        — o11y cluster kubeconfig
  o11y.secrets.env.enc       — o11y deployed secrets
  o11y.tls.crt.enc           — o11y Cloudflare origin cert
  o11y.tls.key.enc           — o11y origin private key

docker/oldeworld/oncall.env.enc — Oncall stack secrets
scratchpad/                     — dev.env.enc, org.env.enc, sample.env.enc
```

## justfile Recipes

| Recipe                              | Purpose                             | Requires              |
| ----------------------------------- | ----------------------------------- | --------------------- |
| `just secret-verify-all`            | Verify all secrets decrypt          | age key               |
| `just secret-view <name>`           | View a secret (auto-detects format) | age key               |
| `just secret-edit <name>`           | Edit a secret in $EDITOR            | age key               |
| `just kubeconfig-sync <cluster>`    | Decrypt kubeconfig (run once)       | age key               |
| `just play <playbook> <host> [inv]` | Run any ansible playbook            | API token via direnv  |
| `just deploy <cluster> <app>`       | Deploy app (secrets + TLS → apply)  | KUBECONFIG via direnv |
| `just helm-upgrade <cluster> <app>` | Install/upgrade Helm chart          | KUBECONFIG via direnv |
| `just k8s-validate [version]`       | Validate manifests with kubeconform | —                     |
| `just ansible-install`              | Install ansible + dependencies      | —                     |
| `just tf <cmd> [workspace]`         | Run terraform (selective or all)    | API tokens via direnv |
| `just tf-fmt`                       | Format all terraform files          | —                     |
| `just tf-list`                      | List terraform workspaces           | —                     |

## What's Done

- [x] DigitalOcean infrastructure (VPC, firewall, 3 droplets, 2 Spaces buckets)
- [x] Cloud-init hardening (fail2ban, SSH, user creation) tested on OrbStack + deployed
- [x] Secrets migration: ansible-vault → sops+age in private infra-secrets repo
- [x] direnv wiring: root + cluster .envrc files with use_sops
- [x] justfile recipes: secrets, deploy, play, helm-upgrade, kubeconfig-sync, tf
- [x] gxy-management cluster configs (Cilium values, security policies, Traefik config)
- [x] App manifests (ArgoCD, Windmill, Zot — kustomization, gateway, httproutes)
- [x] Helm chart values (ArgoCD, Windmill, Zot — credentials stripped to secret overlays)
- [x] Documentation (infra-secrets README wiring doc, gxy-management README runbook)
- [x] Tailscale installed and connected on all 3 nodes (verified: online, SSH enabled)
- [x] Cloudflare origin certs encrypted for all 3 apps (reused existing wildcard)
- [x] Code review: 3 CRITICALs + 10 WARNINGs + 6 SUGGESTIONs found and fixed
- [x] Justfile overhaul: 18 → 11 parametric recipes, no special-case orchestration

## Secrets → Helm Flow

Public values.yaml (structure, resources, flags) are overlaid with secret values from infra-secrets:

```
Public: k3s/<cluster>/apps/<app>/charts/<chart>/values.yaml
Secret: infra-secrets/k3s/<cluster>/<app>.values.yaml.enc  (optional, sops-encrypted)

just helm-upgrade → helm upgrade --install -f values.yaml -f /tmp/secret-values.yaml → cleanup
```

Apps that only need K8s Secrets (ArgoCD, Zot) use `just deploy` which decrypts `.secrets.env` + TLS.

## What's Next

Deploy sequentially. Verify each before moving to the next.

### Phase A: Bootstrap Cluster

| #   | Task                          | Status | Command / Notes                                            |
| --- | ----------------------------- | ------ | ---------------------------------------------------------- |
| A1  | Populate Windmill secrets     | TODO   | Create `windmill.values.yaml.enc` (PG password, DB URL)    |
| A2  | Populate Windmill app secrets | TODO   | Create `windmill.secrets.env.enc` (admin email + password) |
| A3  | Run K3s galaxy playbook       | TODO   | `just play k3s--galaxy gxy_mgmt_k3s` (from cluster dir)    |
| A4  | Verify cluster health         | TODO   | 3 nodes Ready, Cilium green, Traefik running, Gateway CRDs |
| A5  | Encrypt kubeconfig            | TODO   | sops encrypt to infra-secrets                              |

### Phase B: Windmill (Day 0 Deliverable)

| #   | Task                  | Status | Command / Notes                                       |
| --- | --------------------- | ------ | ----------------------------------------------------- |
| B1  | Install Windmill Helm | TODO   | `just helm-upgrade gxy-management windmill`           |
| B2  | Verify pods ready     | TODO   | `kubectl get pods -n windmill`                        |
| B3  | Deploy manifests      | TODO   | `just deploy gxy-management windmill` (Gateway + TLS) |
| B4  | Cloudflare DNS        | TODO   | ClickOps: A records (proxied) → 3 node public IPs     |
| B5  | Cloudflare Access     | TODO   | ClickOps: email OTP gate, all staff                   |
| B6  | Smoke test            | TODO   | curl + browser, verify Access gate                    |

### Phase C: ArgoCD (Platform Team)

| #   | Task                    | Status | Command / Notes                                         |
| --- | ----------------------- | ------ | ------------------------------------------------------- |
| C1  | Populate ArgoCD secrets | TODO   | Create `argocd.secrets.env.enc` (bcrypt admin password) |
| C2  | Install ArgoCD Helm     | TODO   | `just helm-upgrade gxy-management argocd`               |
| C3  | Deploy manifests        | TODO   | `just deploy gxy-management argocd`                     |
| C4  | DNS + Access            | TODO   | ClickOps: argocd.freecodecamp.net, platform team only   |
| C5  | Verify                  | TODO   | Login, verify dashboard                                 |

### Phase D: Zot (Platform Team)

| #   | Task                 | Status | Command / Notes                                         |
| --- | -------------------- | ------ | ------------------------------------------------------- |
| D1  | Populate Zot secrets | TODO   | Create `zot.secrets.env.enc` (S3 creds, htpasswd)       |
| D2  | Install Zot Helm     | TODO   | `just helm-upgrade gxy-management zot`                  |
| D3  | Deploy manifests     | TODO   | `just deploy gxy-management zot`                        |
| D4  | DNS + Access         | TODO   | ClickOps: registry.freecodecamp.net, platform team only |
| D5  | Verify               | TODO   | Push/pull test image                                    |

### Phase E: Cleanup

| #   | Task                   | Status | Notes                                          |
| --- | ---------------------- | ------ | ---------------------------------------------- |
| E1  | Commit infra-secrets   | TODO   | Push to GitHub                                 |
| E2  | Remove SPIKE-STATUS.md | TODO   | Absorb permanent decisions into cluster README |
| E3  | Clean up stale files   | TODO   | Orphaned samples, archive cruft                |

Unblocked now: A1, A2 (populate secrets).

## Existing Infrastructure (Unchanged)

### ops-backoffice-tools (live, 101 days uptime)

- 3 nodes: ops-vm-tools-k3s-nyc3-{01,02,03}, k3s v1.32.11
- Apps: Appsmith (1 pod), Outline (3 containers)
- Storage: Longhorn v1.10.1 (31 pods)
- Ingress: Traefik v3.5.1
- Network: Tailscale operator
- Helm: longhorn, tailscale-operator, traefik, traefik-crd

### What Was Archived (this branch)

Observability stack torn down and moved to `.archive/2026-03-observability-teardown/`:

- ops-logs-clickhouse cluster (3 droplets)
- Grafana, Prometheus, Vector from ops-backoffice-tools
- Savings: ~$231/month

### Branch History

```
feat/k3s-universe (13 commits ahead of main)

ab0f800 chore: add tailscale justfile recipes and update gxy-management README
6ac1504 refactor: migrate secrets from ansible-vault to sops+age
9c902c1 feat(cloud-init): update config for Ubuntu 24.04
0619242 fix(k8s): exclude JSON and dashboards from kubeconform validation
2332a1c feat(k8s): add kubeconform manifest validation — local + CI
b5fc35b feat(gxy-management): align Day 0 config with spike-plan and ADRs
c9c1b4e fix: move archive
6137073 fix: move scratchpad
5810c79 feat: add direnv hierarchy and secrets bootstrap workflow
4ebcc24 feat: consolidate secrets management with ansible-vault
a564bd6 refactor: consolidate justfiles into root justfile
b0fae18 feat(k3s): add gxy-management galaxy configs and Day 0 spike infrastructure
e72beb5 feat(k3s): add ops-mgmt cluster configs and tooling
```

## Errors and Fixes (for Future Reference)

| Issue                                                | Root Cause                                | Fix                                                       |
| ---------------------------------------------------- | ----------------------------------------- | --------------------------------------------------------- |
| cloud-init heredoc syntax error                      | runcmd `\|` strings don't support heredoc | Moved to write_files section                              |
| `systemctl restart sshd` fails on Ubuntu 24.04       | Service renamed to `ssh.service`          | `ssh \|\| sshd \|\| true` fallback                        |
| SSH hardening sed had no effect                      | Ubuntu 24.04 ships commented defaults     | Drop-in file at sshd_config.d/99-hardening.conf           |
| sops `path_regex: .*\.enc$` didn't match input files | Regex matches input path, not output      | Changed to `.*` (match all)                               |
| sops `dotenv` format failed on YAML file             | ansible vars are YAML, not dotenv         | Renamed to `.yaml.enc`, format detection in verify recipe |
| direnv `$(dirname "$0")` empty                       | Not available in direnv context           | Use `expand_path ../infra-secrets`                        |

## Open Questions

- **Helm chart versions**: Need to verify latest stable for ArgoCD, Windmill, Zot before install
- **Cloudflare Access policies**: Exact group/email configuration TBD
- **Windmill DB**: Using embedded SQLite or external PostgreSQL? (ADR-008 says CNPG later)
- **TLS for gxy-management apps**: Need to create Cloudflare origin cert for \*.freecodecamp.net
