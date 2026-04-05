# gxy-management Flight Manual

Checklist for spinning up the gxy-management galaxy from scratch. Each step is sequenced — do not skip ahead. ClickOps steps will be codified into OpenTofu later.

## Pre-flight

```
cd ~/DEV/fCC/infra
just ansible-install
just secret-verify-all
```

- [ ] All secrets decrypt OK
- [ ] age key on local machine (`~/.config/sops/age/keys.txt`)
- [ ] Cloudflare origin cert + key in `infra-secrets/k3s/gxy-management/`

## Phase 1: Infrastructure (ClickOps — codify in OpenTofu)

### 1.1 DO VPC

- [ ] Create VPC `universe-vpc-fra1` in FRA1, CIDR `10.110.0.0/20`

### 1.2 DO Droplets

- [ ] Create 3x `s-8vcpu-16gb-amd` in FRA1
- [ ] Names: `gxy-vm-mgmt-k3s-{1,2,3}`
- [ ] Image: Ubuntu 24.04, VPC: `universe-vpc-fra1`, Tag: `gxy-mgmt-k3s`
- [ ] Cloud-init: `cloud-init/basic.yml`

### 1.3 DO Cloud Firewall

- [ ] Create firewall `gxy-fw-fra1`, attach to tag `gxy-mgmt-k3s`
- [ ] VPC rules (source 10.110.0.0/20): 2379-2380, 4240, 4244, 5001, 6443, 8472, 10250
- [ ] Public rules: 22/TCP, 80/TCP, 443/TCP

### 1.4 DO Spaces

- [ ] Bucket `net.freecodecamp.universe-backups` in FRA1 (etcd snapshots + Zot storage)

### 1.5 Tailscale

SSH into each node and join:

```
tailscale up --ssh
```

Verify from local:

```
tailscale status | grep gxy-vm-mgmt
```

All 3 nodes should show as connected.

## Phase 2: Cluster Bootstrap (Automated)

```
cd k3s/gxy-management
just play k3s--bootstrap gxy_mgmt_k3s
```

This runs 5 plays: validate → prerequisites → k3s deploy → Cilium → verify + kubeconfig.

### Post-bootstrap checks

```
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get nodes -o wide
# All 3 Ready, InternalIP = VPC IPs (10.110.0.x)

kubectl top nodes
# All 3 reporting CPU/memory (metrics-server working)

kubectl get pods -n kube-system
# All Running, no CrashLoopBackOff

kubectl exec -n kube-system $(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}') -- cilium-health status
# 3/3 reachable, all endpoints 1/1
```

## Phase 3: Windmill

### 3.1 Helm install

```
just helm-upgrade gxy-management windmill
```

### 3.2 Gateway + TLS manifests

```
just deploy gxy-management windmill
```

### 3.3 Verify

```
kubectl get pods -n windmill
# 6 pods Running (app, 2x workers-default, workers-native, extra, postgresql)

kubectl get gateway -n windmill
# windmill-gateway Programmed=True

kubectl get httproute -n windmill
# windmill-route, http-redirect

kubectl get svc -n kube-system traefik
# EXTERNAL-IP shows all 3 node VPC IPs
```

## Phase 4: DNS + Access (ClickOps — codify in OpenTofu)

### 4.1 Get node public IPs

```
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="ExternalIP")].address}{"\n"}{end}'
```

If no ExternalIP (DO doesn't always populate it):

```
doctl compute droplet list --tag-name gxy-mgmt-k3s --format Name,PublicIPv4
```

### 4.2 Cloudflare DNS

- [ ] A record: `windmill.freecodecamp.net` → node 1 public IP
- [ ] A record: `windmill.freecodecamp.net` → node 2 public IP
- [ ] A record: `windmill.freecodecamp.net` → node 3 public IP
- [ ] Proxy: ON (orange cloud)
- [ ] SSL mode: Full (Strict)

### 4.3 Cloudflare Access

- [ ] Create Access application for `windmill.freecodecamp.net`
- [ ] Policy: email OTP, allow all `@freecodecamp.org`

### 4.4 Smoke test

```
curl -sI https://windmill.freecodecamp.net
# Should return 200 or 302 (Cloudflare Access redirect)
```

- [ ] Browser: visit `https://windmill.freecodecamp.net`
- [ ] Cloudflare Access gate prompts for email
- [ ] After auth, Windmill login page loads

## Phase 5: ArgoCD

### 5.1 Deploy

```
just helm-upgrade gxy-management argocd
just deploy gxy-management argocd
```

### 5.2 Verify

```
kubectl get pods -n argocd
# All Running

kubectl get gateway -n argocd
kubectl get httproute -n argocd
```

### 5.3 DNS + Access

- [ ] A records: `argocd.freecodecamp.net` → same 3 node public IPs
- [ ] Cloudflare Access application (same pattern)

### 5.4 Get initial admin password

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Phase 6: Zot

### 6.1 Deploy

```
just helm-upgrade gxy-management zot
just deploy gxy-management zot
```

### 6.2 Verify

```
kubectl get pods -n zot
# All Running

kubectl get gateway -n zot
kubectl get httproute -n zot
```

### 6.3 DNS + Access

- [ ] A records: `zot.freecodecamp.net` → same 3 node public IPs
- [ ] Cloudflare Access application (same pattern)

### 6.4 Smoke test

```
curl -s https://zot.freecodecamp.net/v2/ | head
# Should return OCI registry response
```

## Teardown

### Cluster only (preserves VMs)

```
just play k3s--teardown gxy_mgmt_k3s
```

### Full teardown (VMs too)

```
just play k3s--teardown gxy_mgmt_k3s
doctl compute droplet delete gxy-vm-mgmt-k3s-1 gxy-vm-mgmt-k3s-2 gxy-vm-mgmt-k3s-3 --force
```

VPC, firewall, Spaces persist (shared infrastructure).

## Known Issues

| Issue                            | Workaround                               | See                         |
| -------------------------------- | ---------------------------------------- | --------------------------- |
| Pod→nodeVPCIP broken             | `hostNetwork: true` for monitoring       | Field notes Failure 8b      |
| kubeProxyReplacement breaks etcd | Keep `false`                             | Field notes Failure 7       |
| Cilium picks up tailscale0 MTU   | Pin `devices: [eth0, eth1]`, `mtu: 1500` | Field notes Failure 8a      |
| DO native routing blocked        | Use VXLAN tunnel (DO anti-spoofing)      | Field notes Cilium pitfalls |
