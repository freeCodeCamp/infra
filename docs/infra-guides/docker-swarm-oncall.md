# Oncall Stack

Docker Swarm stack configuration for housekeeping and automated maintenance services.

## Overview

The Oncall stack provides automated maintenance and monitoring services including task scheduling, service updates, and system cleanup.

## Components

| Service         | Purpose                                                     |
| --------------- | ----------------------------------------------------------- |
| **svc-cronjob** | Swarm cronjob scheduler (manages scheduled tasks)           |
| **svc-update**  | Gantry service updater (auto-updates tagged services)       |
| **svc-cleanup** | Docker system cleanup (prunes old images/containers weekly) |
| **svc-webhook** | Webhook receiver (triggers instant Gantry updates via HTTP) |

## Architecture

```
Cronjob Scheduler → Scheduled Tasks
Service Updater → Auto-update tagged services
Cleanup Job → Weekly prune on all nodes
Webhook Receiver → On-demand Gantry updates (via GHA)
    ↓
All services → Loki logging
```

## Prerequisites

- Docker Swarm cluster initialized
- Docker credentials at `~/.docker/config.json` on manager node
- Loki instance with push API access (for centralized logging)
- kubectl access to Kubernetes cluster (for retrieving Loki credentials)

## Configuration

### Gantry Auto-Update Service

**Authentication Requirements:**

- Uses host Docker credentials from `/home/freecodecamp/.docker/config.json`
- Requires `--with-registry-auth` (set via `GANTRY_UPDATE_OPTIONS`) to propagate credentials to worker nodes
- Credentials must be valid and updated if expired

**Directory Requirements:**

- Mount `/home/freecodecamp/.docker:/root/.docker` as **writable** (buildx needs write access)
- Ensure `/home/freecodecamp/.docker/buildx/` directory exists on manager node

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

### Webhook Configuration

- Set `WEBHOOK_SECRET` env var to a strong random string (shared with GHA secrets)
- Port 9889 is exposed on the host; reverse proxy with Nginx (out of scope)
- Hook endpoint: `/hooks/run-gantry`

### Logging Configuration

Logs are forwarded to Loki with the following labels for clean separation:

- **Tenant ID**: `fCC-o11y-oncall-v20250113-0001` (separate from other services)
- **Labels**:
  - `stack=oncall` (all services)
  - `service=cronjob|update|cleanup` (per service)
  - `app=swarm-cronjob|gantry|docker` (application name)

## Deployment

```bash
# Ensure correct ownership and permissions
sudo chown -R freecodecamp:freecodecamp /home/freecodecamp/.docker
sudo chmod -R u+w /home/freecodecamp/.docker

# Set Docker context
docker context use <context_name>

# Set environment variables (see Configuration section)
export LOKI_PASSWORD=$(kubectl get secret o11y-secrets -n o11y -o jsonpath='{.data.LOKI_GATEWAY_PASSWORD}' | base64 --decode)
export LOKI_URL="https://loki:${LOKI_PASSWORD}@o11y.freecodecamp.net/loki/api/v1/push"
export LOKI_TENANT_ID="fCC-o11y-oncall-v20250113-0001"

# Deploy stack
docker stack deploy -c docker/swarm/stacks/oncall/stack-oncall.yml oncall
```

**Note:** The update service runs on the manager node via cronjob scheduling (managed by `svc-cronjob`).

## GHA Integration

Trigger an on-demand Gantry update from a GitHub Actions workflow using an ephemeral Tailscale connection:

```yaml
- name: Setup and connect to Tailscale network
  uses: tailscale/github-action@53acf823325fe9ca47f4cdaa951f90b4b0de5bb9 # v4
  with:
    oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
    oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
    hostname: gha-${{ env.STACK_NAME }}-deploy-${{ github.run_id }}
    tags: tag:ci
    version: latest

- name: Wait for Tailscale Network Readiness
  run: |
    echo "Waiting for Tailscale network to be ready..."
    max_wait=60
    elapsed=0
    while [ $elapsed -lt $max_wait ]; do
      if tailscale status --json | jq -e '.BackendState == "Running"' > /dev/null 2>&1; then
        echo "Tailscale network is ready"
        break
      fi
      sleep 2
      elapsed=$((elapsed + 2))
    done
    if [ $elapsed -ge $max_wait ]; then
      echo "Tailscale network not ready after ${max_wait}s"
      exit 1
    fi

- name: Trigger deployment
  run: |
    curl -fsS -X POST https://${{ secrets.WEBHOOK_HOST }}/hooks/run-gantry \
      -H "Content-Type: application/json" \
      -H "X-Webhook-Secret: ${{ secrets.WEBHOOK_SECRET }}" \
      -d '{"GANTRY_SERVICES_FILTERS":"name=${{ env.STACK_NAME }}_${{ env.SERVICE_NAME }}"}'
```

**Required GHA secrets:** `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET`, `WEBHOOK_HOST` (Tailscale hostname), `WEBHOOK_SECRET`

## Testing Webhook

Run from the manager node (`ssh freecodecamp@ops-vm-backoffice`):

```bash
# Trigger update for a specific service
curl -X POST http://localhost:9889/hooks/run-gantry \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: $WEBHOOK_SECRET" \
  -d '{"GANTRY_SERVICES_FILTERS":"name=<stack>_<service>"}'

# Trigger update for all autoupdate-labeled services (no filter)
curl -X POST http://localhost:9889/hooks/run-gantry \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: $WEBHOOK_SECRET" \
  -d '{}'

# Invalid request (no secret — should return "Hook rules were not satisfied")
curl -X POST http://localhost:9889/hooks/run-gantry \
  -H "Content-Type: application/json" \
  -d '{}'

# Check webhook logs
docker service logs oncall_svc-webhook
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

# Webhook receiver logs
{stack="oncall", service="webhook"}
```

## Maintenance

- Docker credentials must be kept current at `~/.docker/config.json`
- Update service runs on manager node (placement constraint enforced)
- Cleanup runs weekly on Monday at 03:30 UTC on all nodes
- Monitor logs in Grafana to verify scheduled tasks are running correctly
