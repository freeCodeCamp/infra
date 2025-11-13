## Oncall Stack

This stack defines all the services for housekeeping and automated maintenance:

- **svc-cronjob**: Swarm cronjob scheduler (manages scheduled tasks)
- **svc-update**: Gantry service updater (auto-updates tagged services)
- **svc-cleanup**: Docker system cleanup (prunes old images/containers weekly)

## Prerequisites

1. Docker credentials at `~/.docker/config.json` on manager node
2. Loki instance with push API access (for centralized logging)

## Configuration

### Environment Variables

Copy `.env.sample` to `.env` and configure:

```bash
# Loki Push API URL
LOKI_URL=https://o11y.freecodecamp.net/loki/api/v1/push

# Oncall-specific tenant ID (keeps logs separated from other stacks)
LOKI_TENANT_ID=fCC-o11y-oncall-v20250113-0001
```

### Log Separation

Logs are forwarded to Loki with:
- **Tenant ID**: `fCC-o11y-oncall-v20250113-0001` (separate from API/other services)
- **Labels**:
  - `stack=oncall` (all services)
  - `service=cronjob|update|cleanup` (per service)
  - `app=swarm-cronjob|gantry|docker` (application name)

This provides clean separation in Grafana while using shared storage.

## Deployment

```bash
# Set context to your swarm manager
docker context use <context_name>

# Deploy with environment variables
export LOKI_URL="https://o11y.freecodecamp.net/loki/api/v1/push"
export LOKI_TENANT_ID="fCC-o11y-oncall-v20250113-0001"

docker stack deploy -c docker/swarm/stacks/oncall/stack-oncall.yml oncall
```

## Querying Logs in Grafana

Create separate views using LogQL queries:

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
