# Migration Plan: Docker Swarm to K3s

## Overview

This document outlines the strategy for migrating Docker Swarm-based stacks (API and News) to a K3s-based setup.

---

## Migration Audit Summary

### Docker Swarm Assets to Migrate

| Stack | Services | Ports | Complexity |
|-------|----------|-------|------------|
| **API** | 2 (alpha, bravo) | 2345, 2346 | High - 20+ secrets, health checks, Loki logging |
| **News** | 7-8 (multi-lang) | 4001-4008 | Low - minimal config, static JAMStack sites |

### Existing K3s Patterns to Follow

The codebase already has well-established K3s patterns in `ops-backoffice-tools` and `ops-logs-clickhouse` clusters:

- **Directory structure**: `k3s/{cluster}/apps/{app}/manifests/base/`
- **Manifest organization**: Kustomize with `secretGenerator`
- **Ingress**: Gateway API with Traefik (not legacy Ingress)
- **Storage**: Longhorn with S3 backups
- **TLS**: Cloudflare origin certificates
- **Networking**: Tailscale for private communication

---

## Migration Strategy

### Phase 1: Infrastructure Provisioning

**New Cluster: `prd-api-news`**

#### Cluster Topology

| Node Type | Count | Spec | Purpose |
|-----------|-------|------|---------|
| **Control Plane** | 3 | 2 vCPU, TBD RAM | HA control plane (cost-optimized) |
| **API Workers** | 4 | TBD (right-size) | Dedicated to API stack (stg + prd) |
| **News Workers** | 4-5 | TBD (right-size) | Dedicated to News stack (stg + prd) |

#### Worker Pool Strategy

- **Dedicated pools**: Workers assigned to specific stacks via node labels/taints
- **Sticky workloads**: Pods remain on their designated pool
- **Movement trigger**: Only when node is removed from pool
- **Environment separation**: Staging and Production in same cluster, namespace-isolated

#### Pod Distribution

| Stack | Environments | Variants | Replicas | Total Pods |
|-------|--------------|----------|----------|------------|
| API Alpha | 2 (stg, prd) | 1 | 2 | 4 |
| API Bravo | 2 (stg, prd) | 1 | 2 | 4 |
| **API Total** | | | | **8 pods** |
| News | 2 (stg, prd) | 7-8 langs | 2 | 28-32 |
| **News Total** | | | | **28-32 pods** |

#### Other Infrastructure

| Aspect | Recommendation | Notes |
|--------|----------------|-------|
| **Region** | Same as Swarm (likely DigitalOcean NYC3) | Minimize latency during cutover |
| **Storage** | local-path (stateless apps) | API/News don't need persistent storage |
| **Load Balancer** | DigitalOcean LB → NodePort 30080/30443 | Follow existing pattern |
| **Networking** | VPC + Tailscale | Secure internal communication |

**Provisioning approach**: Follow the existing 4-phase pattern in `k3s/README.md`:

1. Create VPC and droplets manually
2. Harden with Ansible
3. Deploy K3s HA cluster with Ansible
4. Configure node labels/taints for worker pools

---

### Phase 2: API Stack Migration

**Proposed directory structure:**

```
k3s/prd-api-news/
├── cluster/
│   ├── tailscale/
│   └── charts/
│       └── longhorn/values.yaml
└── apps/
    └── api/
        ├── manifests/
        │   ├── base/
        │   │   ├── kustomization.yaml
        │   │   ├── namespace.yaml
        │   │   ├── deployment-alpha.yaml
        │   │   ├── deployment-bravo.yaml
        │   │   ├── service-alpha.yaml
        │   │   ├── service-bravo.yaml
        │   │   ├── gateway.yaml
        │   │   ├── httproutes.yaml
        │   │   ├── middleware.yaml
        │   │   └── secrets/
        │   │       ├── .secrets.env.sample
        │   │       └── .secrets.env (gitignored)
        │   └── overlays/
        │       ├── staging/
        │       └── production/
        └── README.md
```

**Key migration mappings:**

| Docker Swarm | K3s Equivalent |
|--------------|----------------|
| `deploy.replicas: 3` | `spec.replicas: 2` + PodAntiAffinity |
| `node.labels.api.enabled` | `nodeSelector` or `nodeAffinity` |
| `max_replicas_per_node: 1` | `podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution` |
| `update_config.parallelism: 1` | `strategy.rollingUpdate.maxUnavailable: 1` |
| `healthcheck` | `livenessProbe` + `readinessProbe` |
| `resources.limits` | `resources.limits` (identical) |
| Environment variables | `secretGenerator` with `envFrom` |
| Loki logging driver | Vector sidecar or Promtail DaemonSet |

**Secrets to migrate (20+ values):**

```
# Auth0 OAuth
AUTH0_CLIENT_ID, AUTH0_CLIENT_SECRET, AUTH0_DOMAIN

# Session/Security
JWT_SECRET, COOKIE_SECRET, COOKIE_DOMAIN

# Database
MONGOHQ_URL

# Email (AWS SES)
SES_ID, SES_SECRET, SES_REGION

# Payments
STRIPE_SECRET_KEY

# Monitoring
SENTRY_DSN, SENTRY_ENVIRONMENT

# Analytics
GROWTHBOOK_FASTIFY_API_HOST, GROWTHBOOK_FASTIFY_CLIENT_KEY

# Observability
LOKI_URL, LOKI_TENANT_ID
```

**Health check translation:**

```yaml
# Docker Swarm
healthcheck:
  test: curl -f http://localhost:3000/status/ping
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s

# K3s equivalent
livenessProbe:
  httpGet:
    path: /status/ping
    port: 3000
  initialDelaySeconds: 40
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /status/ping
    port: 3000
  initialDelaySeconds: 10
  periodSeconds: 5
```

---

### Phase 3: News Stack Migration

**Proposed directory structure:**

```
k3s/prd-api-news/
└── apps/
    └── news/
        ├── manifests/
        │   ├── base/
        │   │   ├── kustomization.yaml
        │   │   ├── namespace.yaml
        │   │   ├── deployment-eng.yaml
        │   │   ├── deployment-chn.yaml
        │   │   ├── deployment-esp.yaml
        │   │   ├── ... (7-8 language files)
        │   │   ├── services.yaml
        │   │   ├── gateway.yaml
        │   │   └── httproutes.yaml
        │   └── overlays/
        │       ├── staging/
        │       └── production/
        └── README.md
```

**Alternative: Consolidated multi-lang deployment**

Given all 7-8 services are identical except for the image tag, consider:

- Single `Deployment` template with Kustomize overlays per language
- Or a Helm chart with values per language

**Simplified config** (News has minimal secrets):

```yaml
# Only needs:
DOCKER_REGISTRY: registry.freecodecamp.org
DEPLOYMENT_ENV: org|dev|stg
```

---

### Phase 4: Logging & Observability

**Current Swarm approach:**

- Loki logging driver embedded in each container
- External labels for service identification

**K3s approach (3 options):**

| Option | Pros | Cons |
|--------|------|------|
| **Promtail DaemonSet** | Cluster-wide, no sidecar overhead | Less granular control |
| **Vector sidecar** | Per-pod configuration | Resource overhead |
| **Fluentbit** | Lightweight, widely used | Another tool to manage |

**Recommendation:** Use existing observability stack in `k8s/apps/o11y/` (Loki/Grafana). Deploy Promtail as DaemonSet in the new cluster, configured to ship logs to the central Loki.

---

### Phase 5: Auto-Update Replacement

**Current Swarm:** Gantry service with `org.freecodecamp.autoupdate=true` label

**K3s options:**

| Option | Description |
|--------|-------------|
| **Flux Image Automation** | GitOps-based, updates manifests in git |
| **ArgoCD Image Updater** | Similar to Flux, ArgoCD ecosystem |
| **Keel** | Lightweight, watches registries |
| **Renovate** | Already in use (per `renovate.json5`), can update image tags |

**Recommendation:** Since Renovate is already in the codebase, extend it to handle container image updates in K3s manifests. This provides:

- PR-based updates with review
- Changelog visibility
- Rollback via git revert

---

### Phase 6: Cutover Strategy

**Blue-Green Deployment:**

```
Timeline:
─────────────────────────────────────────────────
│ T-0: Both Swarm and K3s running (K3s in shadow)
│ T-1: Route 10% traffic to K3s (canary)
│ T-2: Monitor metrics, logs, errors
│ T-3: Route 50% traffic to K3s
│ T-4: Route 100% traffic to K3s
│ T-5: Decommission Swarm (keep 7 days for rollback)
─────────────────────────────────────────────────
```

**DNS/Load Balancer approach:**

- Cloudflare (likely in use) for weighted routing
- Or DigitalOcean LB with backend switching

---

## Key Decisions

### Decided

| Decision | Choice |
|----------|--------|
| **Cluster naming** | `prd-api-news` (single cluster) |
| **Environment strategy** | Single cluster, namespace separation (`api-stg`, `api-prd`, `news-stg`, `news-prd`) |
| **Replicas** | 2 per deployment (down from 3) |
| **Worker pools** | Dedicated pools per stack with node labels/taints |

### Pending

1. **News deployment architecture**:
   - 7-8 separate Deployments (mirrors Swarm)?
   - Or templated approach (Helm/Kustomize generators)?

2. **Auto-update mechanism**:
   - Renovate PRs?
   - Flux/ArgoCD image automation?
   - Manual updates?

3. **Logging approach**:
   - Promtail DaemonSet?
   - Vector sidecars?
   - Direct Loki integration?

4. **Secrets management**:
   - Kustomize secretGenerator (current pattern)?
   - External Secrets Operator (for Vault/cloud secrets)?
   - Sealed Secrets?

5. **Gateway API hostnames**:
   - Keep same hostnames (`api.freecodecamp.org`)?
   - New hostnames during migration (`api-k3s.freecodecamp.org`)?

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Secret misconfiguration | Medium | High | Template from `.env.sample`, verify all 20+ secrets |
| MongoDB connection issues | Low | Critical | Test connectivity from new cluster via Tailscale |
| Traffic routing errors | Medium | High | Canary deployment, instant rollback capability |
| Resource exhaustion | Low | Medium | Set resource limits, monitor during shadow period |
| Loki logging gaps | Medium | Low | Verify log shipping before cutover |
| TLS certificate errors | Low | High | Pre-provision Cloudflare origin certs |

---

## Estimated Effort Breakdown

| Phase | Tasks | Complexity |
|-------|-------|------------|
| **Phase 1** | Cluster provisioning | Medium (follow existing playbooks) |
| **Phase 2** | API manifests | High (20+ secrets, health checks) |
| **Phase 3** | News manifests | Low (minimal config) |
| **Phase 4** | Logging setup | Medium |
| **Phase 5** | Auto-update setup | Low-Medium |
| **Phase 6** | Cutover | Medium (coordination) |

---

## Changelog

| Date | Change |
|------|--------|
| 2025-12-26 | Initial plan created |
| 2025-12-26 | Updated: 2 replicas (down from 3), dedicated worker pools, dual environments (stg+prd), cluster topology refined |
