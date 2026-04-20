# gxy-management

First Universe galaxy. Control plane brain — manages all galaxies.

## Specifications

- **Nodes**: 3× DigitalOcean s-8vcpu-16gb-amd (FRA1)
- **CNI**: Cilium (eBPF, Hubble observability)
- **Pod CIDR**: 10.1.0.0/16
- **Service CIDR**: 10.11.0.0/16
- **Storage**: local-path (K3s default)
- **Ingress**: Traefik with Gateway API

## Applications

| App      | Purpose                       | Access                                    |
| -------- | ----------------------------- | ----------------------------------------- |
| Windmill | Workflow engine               | windmill.freecodecamp.net (all staff)     |
| ArgoCD   | GitOps (all galaxies)         | argocd.freecodecamp.net (platform team)   |
| Zot      | Container registry (deferred) | registry.freecodecamp.net (platform team) |

## Quick Access

```bash
cd k3s/gxy-management   # direnv loads KUBECONFIG + DO_API_TOKEN
kubectl get nodes
```

## Deploy

```bash
just play k3s--bootstrap gxy_mgmt_k3s
```

## Deployment Runbook

### Pre-deployment (ClickOps)

1. Create 3x DO droplets (s-8vcpu-16gb-amd) in FRA1 -- attach to VPC, configure firewall (80, 443, 6443 from VPC, 22 from Tailscale)
2. Create DO Spaces bucket `net-freecodecamp-universe-backups` in FRA1 (etcd snapshots)
3. Create DO Spaces bucket `net.freecodecamp.universe-registry` in FRA1 (Zot images)
4. Install Tailscale: `just play tailscale--0-install gxy_mgmt_k3s` then `just play tailscale--1b-up-with-ssh gxy_mgmt_k3s`
5. Create Cloudflare origin certificate for `*.freecodecamp.net` (15-year, RSA)
6. Populate app secrets in infra-secrets repo (see samples in each app directory)

### K3s Bootstrap

```bash
just play k3s--bootstrap gxy_mgmt_k3s
```

Deploys k3s HA cluster with Cilium CNI, Traefik ingress, etcd S3 backups, and fetches kubeconfig.

### Helm Installations

After playbook completes:

```bash
just helm-upgrade gxy-management argocd
just helm-upgrade gxy-management windmill
just helm-upgrade gxy-management zot   # deferred — Phase 1
```

Release names match the app directory names. The recipe reads the chart repo URL from `charts/<chart>/repo` and the values from `charts/<chart>/values.yaml`. When no repo file exists, the chart is installed from the local directory.

### App Secrets and Manifests

```bash
just deploy gxy-management argocd
just deploy gxy-management windmill
just deploy gxy-management zot        # deferred — Phase 1
```

### Post-deployment (ClickOps)

1. Create DNS A records (proxied) for windmill/argocd.freecodecamp.net pointing to all 3 node public IPs
2. Create Cloudflare Access policies for each service (deferred)

### Smoke Tests

1. `kubectl get nodes` -- all 3 Ready
2. `cilium status` -- all green
3. `curl -H "Host: windmill.freecodecamp.net" https://<node-ip> -k`
4. Verify Cloudflare Access gate (deferred)
