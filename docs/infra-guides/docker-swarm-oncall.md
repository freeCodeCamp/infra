# Oncall Stack

Docker Swarm stack configuration for housekeeping and automated maintenance services.

## Overview

The Oncall stack provides automated maintenance and monitoring services including task scheduling, service updates, and system cleanup.

## Components

| Service                       | Purpose                                                       |
| ----------------------------- | ------------------------------------------------------------- |
| **svc-cronjob**               | Swarm cronjob scheduler (manages scheduled tasks)             |
| **svc-update**                | Gantry service updater (auto-updates tagged services)         |
| **svc-cleanup**               | Docker system cleanup (prunes old images/containers weekly)   |
| **svc-webhook**               | Webhook receiver (triggers instant Gantry updates via HTTP)   |
| **svc-chat-relay**            | Posts Gantry notices to Google Chat as one standard line      |
| **svc-dispatch-news-eng**     | Starts the news `deploy-eng.yml` workflow every 3 hours       |
| **svc-dispatch-news-i18n**    | Starts the news `deploy-i18n.yml` workflow every 6 hours      |
| **svc-dispatch-housekeeping** | Starts the infra `ansible--housekeeping.yml` workflow Wed/Sat |
| **svc-watchdog-news**         | Posts to Google Chat when the English news site is stale      |

## Architecture

```
Cronjob Scheduler → Scheduled Tasks
Service Updater → Auto-update tagged services
Cleanup Job → Weekly prune on all nodes
Webhook Receiver → On-demand Gantry updates (via GHA)
Dispatchers → GitHub workflow_dispatch (news deploys, housekeeping)
Watchdog → news RSS lastBuildDate → Google Chat when stale
Gantry (cron and webhook) → Chat relay → Google Chat
    ↓
All services → json-file logging (local, rotated)
```

## Prerequisites

- Docker Swarm cluster initialized
- Docker credentials at `~/.docker/config.json` on manager node

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

Export these 3 variables before `docker stack deploy`. Container logs use the local `json-file` driver (rotated 10m × 3, compressed) — no logging credentials needed.

| Variable                | Used by                      | Value                                                                               |
| ----------------------- | ---------------------------- | ----------------------------------------------------------------------------------- |
| `WEBHOOK_SECRET`        | svc-webhook                  | Shared secret for `/hooks/run-gantry`. Same value as the GHA secret.                |
| `GITHUB_DISPATCH_TOKEN` | dispatchers                  | Fine-grained PAT of the bot account. Actions read/write on `news` and `infra` only. |
| `GOOGLE_CHAT_WEBHOOK`   | dispatchers, watchdog, relay | Google Chat incoming webhook URL. Same space as the housekeeping reports.           |

Anyone with Docker access on the manager can read these values with `docker service inspect`. Rotate a value after you remove such access.

### Swarm Config Names

Swarm configs are immutable. When you change `run_gantry.sh`, `hooks-relay.json` or a file in `scripts/`, increase the version suffix of its `name:` in `stack-oncall.yml` (for example `oncall_scripts_lib_v1` → `oncall_scripts_lib_v2`). If you do not, `docker stack deploy` fails.

### Dispatchers

GitHub `schedule` triggers start late or do not start at all (observed since 2026-08-26). The dispatchers start the time-critical workflows from this stack. Each dispatcher sends one `POST /repos/<repo>/actions/workflows/<file>/dispatches` request to the GitHub API. It does not retry this request, because a retry can start a second run.

| Service                     | Schedule (UTC)   | Window policy |
| --------------------------- | ---------------- | ------------- |
| `svc-dispatch-news-eng`     | `0 5 */3 * * *`  | `avoid`       |
| `svc-dispatch-news-i18n`    | `0 5 */6 * * *`  | `avoid`       |
| `svc-dispatch-housekeeping` | `0 30 1 * * 3,6` | `require`     |

The maintenance window is Wed/Sat 00:00–06:00 UTC. `scripts/lib.sh` defines it once.

- `avoid`: inside the window, the dispatcher does nothing.
- `require`: outside the window, the dispatcher refuses and posts to Google Chat.

The dispatcher posts to Google Chat when the API refuses the request or when a variable is missing. The housekeeping workflow also checks its own start time. It refuses to run outside the window unless you start it with `window_check=false`.

### Freshness Watchdog

`svc-watchdog-news` runs every hour at minute 50. It reads `<lastBuildDate>` from `https://www.freecodecamp.org/news/rss.xml`.

- Limit: 5 hours. The feed is stale when its build date is older than the limit.
- Posts: the first hour past the limit, then every 6 hours while the feed stays stale.
- Quiet hours: Wed/Sat 00:00–08:00 UTC. The first check after quiet hours posts if the feed is stale.
- The watchdog also posts when it cannot read the feed or the date.

### Google Chat Notifications

Every message from this stack and from the GitHub workflow notifiers is one line:

```text
<icon> *<source>* · <subject> · <summary> · <link|label>
```

- Icon: ✅ ok, ⚠️ warn, 🔴 fail.
- The link is optional. The GitHub workflows always link the run.
- A warn or fail message from a GitHub workflow can add detail lines below the line.
- `scripts/lib.sh` (`chat_notify`) and `.github/actions/notify-chat` make the line. Do not post to Google Chat in a different format.

Gantry sends its notifications to `svc-chat-relay` (`http://svc-chat-relay:9000/hooks/gantry`). The relay makes the standard line and posts it to `GOOGLE_CHAT_WEBHOOK`. The subject is `hourly` for the cron run and `webhook` for a run from `/hooks/run-gantry`. Gantry posts only when it updates a service or when an update fails (`GANTRY_NOTIFICATION_CONDITION=on-change`).

```text
✅ *gantry* · webhook · 1 service(s) updated: prd-news_svc-eng
🔴 *gantry* · hourly · 1 service(s) update failed: prd-news_svc-eng; 1 service(s) rollback failed: prd-news_svc-eng
```

`svc-chat-relay` publishes no port. Only services on the `oncall_default` network can reach it.

### Tests

```bash
sh docker/swarm/stacks/oncall/scripts/test.sh
```

### Webhook Configuration

- Set `WEBHOOK_SECRET` env var to a strong random string (shared with GHA secrets)
- Port 9889 is exposed on the host; reverse proxy with Nginx (out of scope)
- Hook endpoint: `/hooks/run-gantry`

### Logging Configuration

All services log to the local Docker `json-file` driver, rotated per node:

- **Rotation**: `max-size=10m`, `max-file=3`, `compress=true`
- **Scope**: logs stay on the node running the task; inspect with `docker service logs oncall_<svc>`
- **History**: previously shipped to Loki on the o11y cluster (tenant `fCC-o11y-oncall-v20250113-0001`); o11y decommissioned 2026-07-14

## Deployment

```bash
# Ensure correct ownership and permissions
sudo chown -R freecodecamp:freecodecamp /home/freecodecamp/.docker
sudo chmod -R u+w /home/freecodecamp/.docker

# Set Docker context
docker context use <context_name>

# Set the stack secrets (logging is local json-file — no logging env needed)
export WEBHOOK_SECRET="<strong-random-string>"
export GITHUB_DISPATCH_TOKEN="<bot fine-grained PAT>"
export GOOGLE_CHAT_WEBHOOK="<google chat webhook url>"

# Deploy stack (run from the stack dir so relative configs resolve)
cd docker/swarm/stacks/oncall
docker stack deploy -c stack-oncall.yml oncall
```

**Note:** The update service runs on the manager node via cronjob scheduling (managed by `svc-cronjob`).

**Cutover order:** Merge the infra changes first, then deploy this stack from `main`. Then, on the same day, merge the news changes that remove the news `schedule` triggers. Do not do the cutover on Wed/Sat before 06:00 UTC. The infra merge removes the housekeeping `schedule`, so deploy this stack before the next Wed/Sat 01:30 UTC. Until the news merge, a news deploy can run twice. This is harmless.

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

# Invalid request (no secret — should return "Hook rules were not satisfied")
curl -X POST http://localhost:9889/hooks/run-gantry \
  -H "Content-Type: application/json" \
  -d '{}'

# Check webhook logs
docker service logs oncall_svc-webhook
```

Do not send an empty `GANTRY_SERVICES_FILTERS`. Gantry reads an empty filter as no filter and updates every service in the swarm, `stg-news` included. Always name the service.

## Querying Logs

Run these commands on the manager node. Each command shows the logs of one service:

```bash
docker service logs --since 2h oncall_svc-cronjob
docker service logs --since 2h oncall_svc-update
docker service logs --since 2h oncall_svc-webhook
docker service logs --since 2h oncall_svc-chat-relay
docker service logs --since 2h oncall_svc-dispatch-news-eng
docker service logs --since 6h oncall_svc-dispatch-news-i18n
docker service logs --since 96h oncall_svc-dispatch-housekeeping
docker service logs --since 2h oncall_svc-watchdog-news
docker service logs --since 168h oncall_svc-cleanup
```

## Maintenance

- Docker credentials must be kept current at `~/.docker/config.json`
- Update service runs on manager node (placement constraint enforced)
- Cleanup runs weekly on Monday at 03:30 UTC on all nodes
- Read the service logs to make sure that the scheduled tasks run
