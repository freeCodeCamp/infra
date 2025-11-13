# Oncall Stack

Docker Swarm stack configuration for housekeeping and automated maintenance services.

## Overview

The Oncall stack provides automated maintenance and monitoring services including task scheduling, service updates, and system cleanup.

## Components

| Service | Purpose |
| --- | --- |
| **svc-cronjob** | Swarm cronjob scheduler (manages scheduled tasks) |
| **svc-update** | Gantry service updater (auto-updates tagged services) |
| **svc-cleanup** | Docker system cleanup (prunes old images/containers weekly) |

## Architecture

```
Cronjob Scheduler → Scheduled Tasks
Service Updater → Auto-update tagged services
Cleanup Job → Weekly prune on all nodes
    ↓
All services → Loki logging
```

## Prerequisites

- Docker Swarm cluster initialized
- Docker credentials at `~/.docker/config.json` on manager node
- Loki instance with push API access (for centralized logging)
- kubectl access to Kubernetes cluster (for retrieving Loki credentials)

## Configuration

### Environment Variables

Set credentials before deployment:

```bash
# Get Loki gateway password from Kubernetes
export LOKI_PASSWORD=$(kubectl get secret o11y-secrets -n o11y -o jsonpath='{.data.LOKI_GATEWAY_PASSWORD}' | base64 --decode)

# Construct Loki URL with embedded credentials
export LOKI_URL="https://loki:${LOKI_PASSWORD}@o11y.freecodecamp.net/loki/api/v1/push"

# Get tenant ID
export LOKI_TENANT_ID=$(kubectl get secret o11y-secrets -n o11y -o jsonpath='{.data.LOKI_TENANT_ID}' | base64 --decode)
```

### Logging Configuration

Logs are forwarded to Loki with the following labels for clean separation:

- **Tenant ID**: `fCC-o11y-oncall-v20250113-0001` (separate from other services)
- **Labels**:
  - `stack=oncall` (all services)
  - `service=cronjob|update|cleanup` (per service)
  - `app=swarm-cronjob|gantry|docker` (application name)

## Deployment

```bash
# Set Docker context
docker context use <context_name>

# Set environment variables (see Configuration section)
export LOKI_PASSWORD=$(kubectl get secret o11y-secrets -n o11y -o jsonpath='{.data.LOKI_GATEWAY_PASSWORD}' | base64 --decode)
export LOKI_URL="https://loki:${LOKI_PASSWORD}@o11y.freecodecamp.net/loki/api/v1/push"
export LOKI_TENANT_ID="fCC-o11y-oncall-v20250113-0001"

# Deploy the stack
docker stack deploy -c docker/swarm/stacks/oncall/stack-oncall.yml oncall
```

## Querying Logs in Grafana

Use these LogQL queries to view logs by service:

```logql
# All oncall logs
{stack="oncall"}

# Cronjob scheduler logs only
{stack="oncall", service="cronjob"}

# Gantry update logs only
{stack="oncall", service="update"}

# Docker cleanup logs only
{stack="oncall", service="cleanup"}
```

## Maintenance

- Docker credentials must be kept current at `~/.docker/config.json`
- Update service runs on manager node (placement constraint enforced)
- Cleanup runs weekly on Monday at 03:30 UTC on all nodes
- Monitor logs in Grafana to verify scheduled tasks are running correctly
