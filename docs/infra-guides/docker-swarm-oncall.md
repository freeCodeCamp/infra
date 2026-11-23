# Oncall Stack

Docker Swarm stack configuration for housekeeping and automated maintenance services.

## Overview

The Oncall stack provides automated maintenance and monitoring services including task scheduling, service updates, and system cleanup.

## Components

| Service                       | Purpose                                                          |
| ----------------------------- | ---------------------------------------------------------------- |
| **svc-cronjob**               | Swarm cronjob scheduler (manages scheduled tasks)                |
| **svc-update**                | Gantry service updater (auto-updates tagged services)            |
| **svc-cleanup**               | Docker system cleanup (prunes old images/containers weekly)      |
| **svc-webhook**               | Webhook receiver (triggers instant Gantry updates via HTTP)      |
| **svc-chat-relay**            | Posts Gantry notices to Google Chat as one standard line         |
| **svc-dispatch-news-eng**     | Starts the news `deploy-eng.yml` workflow every 3 hours          |
| **svc-dispatch-housekeeping** | Starts the infra `ansible--housekeeping.yml` workflow Wed/Sat    |
| **svc-dispatch-docr-gc**      | Starts the infra `docr--garbage-collection.yml` workflow Wed/Sat |
| **svc-watchdog-news**         | Posts to Google Chat when the English news site is stale         |
| **svc-watchdog-swarm**        | Posts to Google Chat when a service or a node is not healthy     |
| **svc-watchdog-swarm-next**   | The next Swarm watchdog logic, posts to the drill space only     |
| **svc-watchdog-vxlan**        | Posts to Google Chat when a node has a stray overlay device      |

## Architecture

```
Cronjob Scheduler → Scheduled Tasks
Service Updater → Auto-update tagged services
Cleanup Job → Weekly prune on all nodes
Webhook Receiver → On-demand Gantry updates (via GHA)
Dispatchers → GitHub workflow_dispatch (news deploys, housekeeping, DOCR garbage collection)
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

Export these 2 variables before `docker stack deploy`. Container logs use the local `json-file` driver (rotated 10m × 3, compressed) — no logging credentials needed.

| Variable                | Used by     | Value                                                                               |
| ----------------------- | ----------- | ----------------------------------------------------------------------------------- |
| `WEBHOOK_SECRET`        | svc-webhook | Shared secret for `/hooks/run-gantry`. Same value as the GHA secret.                |
| `GITHUB_DISPATCH_TOKEN` | dispatchers | Fine-grained PAT of the bot account. Actions read/write on `news` and `infra` only. |

Anyone with Docker access on the manager can read these values with `docker service inspect`. Rotate a value after you remove such access.

### Chat Webhook Secrets

The Google Chat webhooks are external Docker secrets, not variables. Create them before the first deploy, as in [Deployment](#deployment) step 4.

| Secret               | Swarm name                     | Used by                       | Value                                                                             |
| -------------------- | ------------------------------ | ----------------------------- | --------------------------------------------------------------------------------- |
| `chat_webhook`       | `oncall_chat_webhook_v1`       | dispatchers, watchdogs, relay | Google Chat webhook URL. Same space as the housekeeping reports.                  |
| `chat_webhook_drill` | `oncall_chat_webhook_drill_v1` | svc-watchdog-swarm-next       | Webhook URL of the drill space (1Password item `o11y-google-chat-drill-webhook`). |

`scripts/lib.sh` reads the URL from `/run/secrets/chat_webhook`. If the file is missing or empty, the script logs `chat: no webhook in /run/secrets/chat_webhook, message not sent` and posts nothing. `curl` gets the URL on stdin. `svc-watchdog-swarm`, `svc-watchdog-swarm-next` and `svc-chat-relay` have no `curl`, so they post with `wget`, and the URL is a `wget` argument while it runs. Anyone who can see the processes on the manager can see it; such a person can also read the secret.

`docker service inspect` does not show a secret value. A service that had `GOOGLE_CHAT_WEBHOOK` before can still show the old value under `PreviousSpec` until its next update.

A Docker secret cannot change. To change a value, see [Rotate a Chat Webhook](#rotate-a-chat-webhook).

### Swarm Config Names

Swarm configs are immutable. When you change `run_gantry.sh`, `hooks-relay.json` or a file in `scripts/`, increase the version suffix of its `name:` in `stack-oncall.yml` (for example `oncall_scripts_lib_v1` → `oncall_scripts_lib_v2`). If you do not, `docker stack deploy` fails. `hooks_json` has no versioned `name:`, so before you change `hooks.json`, add one to `hooks_json` in `stack-oncall.yml`.

### Dispatchers

GitHub `schedule` triggers start late or do not start at all (observed since 2026-08-26). The dispatchers start the time-critical workflows from this stack. Each dispatcher sends one `POST /repos/<repo>/actions/workflows/<file>/dispatches` request to the GitHub API. It does not retry this request, because a retry can start a second run.

| Service                     | Schedule (UTC)   | Window policy |
| --------------------------- | ---------------- | ------------- |
| `svc-dispatch-news-eng`     | `0 5 */3 * * *`  | `avoid`       |
| `svc-dispatch-housekeeping` | `0 30 1 * * 3,6` | `require`     |
| `svc-dispatch-docr-gc`      | `0 30 3 * * 3,6` | `require`     |

The maintenance window is Wed/Sat 00:00–06:00 UTC. `scripts/lib.sh` defines it once.

- `avoid`: inside the window, the dispatcher starts nothing. If the last completed run on the branch failed or was cancelled, the first skip of the window (00:00–03:00 UTC) posts a warning to Google Chat.
- `require`: outside the window, the dispatcher refuses and posts to Google Chat.

The dispatcher posts to Google Chat when the API refuses the request or when a variable is missing. The housekeeping workflow also checks its own start time. It refuses to run outside the window unless you start it with `window_check=false`.

The DOCR garbage collection workflow makes the registry read-only while it runs. It starts only on Wed/Sat 00:00–05:10 UTC. This leaves at least 55 minutes before the 06:05 news deploy. Past runs took 5–26 minutes. It waits up to 60 minutes for DOCR push and cleanup runs in other repos to finish, then skips. It posts each result to Google Chat. To start it outside the window, use `window_check=false`.

The workflow does not wait for `exam-platform` releases. That repo is private, and the workflow token cannot read its runs. If an `exam-platform` release fails to push during a collection, run the release again after the collection ends.

### Freshness Watchdog

`svc-watchdog-news` runs every hour at minute 50. It reads `<lastBuildDate>` from `https://www.freecodecamp.org/news/rss.xml`.

- Limit: 5 hours. The feed is stale when its build date is older than the limit.
- Posts: the first hour past the limit, then every 6 hours while the feed stays stale.
- Quiet hours: Wed/Sat 00:00–08:00 UTC. The first check after quiet hours posts if the feed is stale.
- The watchdog also posts when it cannot read the feed or the date.

### Swarm Watchdogs

`svc-watchdog-swarm` runs on the manager every 30 minutes. It runs `scripts/swarm-check.sh`, reads again after 60 seconds, and posts each finding that stays.

- It finds services below their target, and nodes with 3 or more rejected tasks in the last 15 minutes.
- It does not check cron services or jobs.
- It posts on each run while the finding stays.
- Quiet hours: Wed/Sat 00:00–06:00 UTC. Housekeeping restarts nodes in this window, and its [Swarm checks](ansible.md#housekeeping-workflow) report on the run.

`svc-watchdog-vxlan` runs on each node at minutes 5 and 35, on the host network. It posts when the node has a [stray overlay device](docker-swarm.md#stray-overlay-device) on two reads, 5 seconds apart. A stray device on `ingress` does not reduce the task count, so `svc-watchdog-swarm` does not find it.

`svc-watchdog-swarm-next` tests the next logic beside `svc-watchdog-swarm`. It runs the same `scripts/watchdog-swarm.sh` on the same schedule, with `scripts/swarm-check-next.sh` mounted as `swarm-check.sh`. It has only the drill secret, mounted as `chat_webhook`, so it posts to the drill space.

- A service below its target is not a finding while its update or rollback is in progress (`updating` or `rollback_started`) and started less than 15 minutes ago. A rollout of a stack thus does not post.
- A service below its target is a finding when its update is paused, rolled back or completed, when it was never updated, or when its update started 15 or more minutes ago.
- A service at its target is not a finding, whatever its update state.
- Each run logs `swarm-check-next: checked <n> services`. See [Querying Logs](#querying-logs).

`ansible/play-swarm--verify.yml` and the housekeeping Swarm checks use `scripts/swarm-check.sh`, not the next logic.

### Google Chat Notifications

Every message from this stack and from the GitHub workflow notifiers is one line:

```text
<icon> *<source>* · <subject> · <summary> · <link|label>
```

- Icon: ✅ ok, ⚠️ warn, 🔴 fail.
- The link is optional. The GitHub workflows always link the run.
- A warn or fail message from a GitHub workflow can add detail lines below the line.
- `scripts/lib.sh` (`chat_notify`) and `.github/actions/notify-chat` make the line. Do not post to Google Chat in a different format.

Gantry sends its notifications to `svc-chat-relay` (`http://svc-chat-relay:9000/hooks/gantry`). The relay makes the standard line and posts it to the webhook in the secret `chat_webhook`. The subject is `hourly` for the cron run and `webhook` for a run from `/hooks/run-gantry`. Gantry posts only when it updates a service or when an update fails (`GANTRY_NOTIFICATION_CONDITION=on-change`).

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
- **Scope**: logs stay on the node running the task; inspect with `docker service logs oncall_<svc>`. Fluent Bit also sends the container logs of the manager to VictoriaLogs; see [Querying Logs](#querying-logs).
- **History**: previously shipped to Loki on the old DOKS o11y cluster (tenant `fCC-o11y-oncall-v20250113-0001`), decommissioned 2026-07-14

## Deployment

**Who:** an operator with the `infra-secrets` age key, 1Password access and Tailscale access to the manager. The commands need `sops` and `op`, so an agent cannot run them.

**When:** after a change to a file in this directory. No workflow deploys this stack, so a push does not change the live stack. A first deploy and an update use the same command.

1. Start Tailscale. The manager names resolve only on the tailnet.
2. On a new machine, create the context once:

   ```bash
   docker context create vultr --docker host=ssh://freecodecamp@ops-vm-swarm-mgr-1
   ```

3. If you changed a config file, increase its version first. See [Swarm Config Names](#swarm-config-names).
4. Create the Chat webhook secrets. From the repository root, run this block. It creates each secret only when it does not exist, so you can run it before each deploy. The values go from `sops` and `op` straight into `docker secret create`, and the block shows no value. `op` reads the drill webhook from the `freecodecamp.1password.com` account and asks you to approve the read in 1Password.

   ```bash
   (
     set -euo pipefail
     if ! docker --context vultr secret inspect oncall_chat_webhook_v1 >/dev/null 2>&1; then
       sops decrypt --input-type dotenv --output-type dotenv \
         ../infra-secrets/docker/oldeworld/oncall.env.enc |
         sed -n 's/^GOOGLE_CHAT_WEBHOOK=//p' |
         docker --context vultr secret create oncall_chat_webhook_v1 -
     fi
     if ! docker --context vultr secret inspect oncall_chat_webhook_drill_v1 >/dev/null 2>&1; then
       op read --account freecodecamp.1password.com \
         op://Infra-IaC-ESO/o11y-google-chat-drill-webhook/credential |
         docker --context vultr secret create oncall_chat_webhook_drill_v1 -
     fi
   )
   ```

5. From the repository root, run this block. The block decrypts the variables into a subshell, so they are not in your shell after the command. `sops exec-env` cannot read this file, so the loop is necessary. See runbook 04, section 3.

   ```bash
   cd docker/swarm/stacks/oncall
   (
     set -eu
     secrets=$(sops decrypt --input-type dotenv --output-type dotenv \
       ../../../../../infra-secrets/docker/oldeworld/oncall.env.enc)
     while IFS= read -r line; do
       case $line in '' | '#'*) continue ;; esac
       export "$line"
     done <<< "$secrets"
     docker --context vultr stack deploy -c stack-oncall.yml oncall
   )
   ```

6. Check the services. `svc-webhook`, `svc-chat-relay` and `svc-cronjob` show `1/1`:

   ```bash
   docker --context vultr service ls --filter name=oncall_
   ```

7. Check the scheduler. Each scheduled service has an `Add cronjob` line: `svc-cleanup`, `svc-dispatch-docr-gc`, `svc-dispatch-housekeeping`, `svc-dispatch-news-eng`, `svc-update`, `svc-watchdog-news`, `svc-watchdog-swarm`, `svc-watchdog-swarm-next` and `svc-watchdog-vxlan`:

   ```bash
   docker --context vultr service logs --raw oncall_svc-cronjob
   ```

`svc-watchdog-vxlan` and `svc-cleanup` are global and each runs once at deploy, on each node. They do not retry, so a rejected task waits for its next scheduled run.

If the manager reports a permission error on `/home/freecodecamp/.docker`, run this on the manager (`ssh freecodecamp@ops-vm-swarm-mgr-1`):

```bash
sudo chown -R freecodecamp:freecodecamp /home/freecodecamp/.docker
sudo chmod -R u+w /home/freecodecamp/.docker
```

**Note:** The update service runs on the manager node via cronjob scheduling (managed by `svc-cronjob`).

### Rotate a Chat Webhook

1. In the Google Chat space, add a new incoming webhook. Keep the old webhook until the last step.
2. Put the new URL in each place that holds the old one:
   - `chat_webhook`: `GOOGLE_CHAT_WEBHOOK` in `oncall.env.enc`, and the GitHub Actions secret `GOOGLE_CHAT_WEBHOOK` of this repository, which posts to the same space. The GitHub workflows stop posting when you delete the old webhook, so change the secret too: run `gh secret set GOOGLE_CHAT_WEBHOOK -R freeCodeCamp/infra` and paste the URL at its prompt.
   - `chat_webhook_drill`: the 1Password item `o11y-google-chat-drill-webhook` (account `freecodecamp.1password.com`, vault `Infra-IaC-ESO`). calert also reads this item. External Secrets gets the new value within 1 hour; then restart calert, as in runbook 19.
3. In `stack-oncall.yml`, increase the version suffix of the secret `name:` (for example `oncall_chat_webhook_v1` → `oncall_chat_webhook_v2`). Use the same name in the block of [Deployment](#deployment) step 4.
4. Run steps 4 and 5 of [Deployment](#deployment).
5. Remove the old secret:

   ```bash
   docker --context vultr secret rm oncall_chat_webhook_v1
   ```

6. In the Google Chat space, delete the old webhook. The old URL stops working.

## GHA Integration

Trigger an on-demand Gantry update from a GitHub Actions workflow using an ephemeral Tailscale connection:

```yaml
- name: Setup and connect to Tailscale network
  uses: tailscale/github-action@d1b6cd204f8dceda5b3eaad7f1f767be390056cd # v4.2.0
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
    curl --fail-with-body -sS --max-time 360 -X POST https://${{ secrets.WEBHOOK_HOST }}/hooks/run-gantry \
      -H "Content-Type: application/json" \
      -H "X-Webhook-Secret: ${{ secrets.WEBHOOK_SECRET }}" \
      -d '{"GANTRY_SERVICES_FILTERS":"name=${{ env.STACK_NAME }}_${{ env.SERVICE_NAME }}"}'
```

The hook waits for Gantry and returns its real result. The Gantry job runs with `--restart-condition none`, and `run_gantry.sh` polls its task state every 5 s (`GANTRY_JOB_POLL`). It answers 200 when the task is `Complete`, and 500 with the Gantry log when the task is `Failed`, `Rejected` or `Shutdown`. After 330 s (`GANTRY_JOB_DEADLINE`) it answers 500 with `Gantry still running after 330 s; result unknown` and leaves the job running; the job name is in the output. A wrong secret gets 403. The curl in the deploy job waits up to 360 s, so the job needs a `timeout-minutes` above 6. Roll out the callers with `--max-time 360` first (they are harmless against the old hook), then redeploy the oncall stack with the new hook; the reverse order makes every deploy job fail with curl exit 28.

**Required GHA secrets:** `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET`, `WEBHOOK_HOST` (Tailscale hostname: `swarm-wh-vultr.<tailnet>.ts.net`), `WEBHOOK_SECRET`

## Testing Webhook

Run from the manager node (`ssh freecodecamp@ops-vm-swarm-mgr-1`). `read -rs` takes the secret without echo, so it stays out of the shell history. The secret goes to `curl` as a header file, not as an argument, and it is not in the shell after the block:

```bash
# Trigger update for a specific service
(
  printf 'Webhook secret: '
  read -rs WEBHOOK_SECRET; echo
  curl -X POST http://localhost:9889/hooks/run-gantry \
    -H "Content-Type: application/json" \
    -H @<(printf 'X-Webhook-Secret: %s\n' "$WEBHOOK_SECRET") \
    -d '{"GANTRY_SERVICES_FILTERS":"name=<stack>_<service>"}'
)

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
docker service logs --since 3h oncall_svc-dispatch-news-eng
docker service logs --since 96h oncall_svc-dispatch-housekeeping
docker service logs --since 96h oncall_svc-dispatch-docr-gc
docker service logs --since 2h oncall_svc-watchdog-news
docker service logs --since 168h oncall_svc-cleanup
docker service logs --since 2h oncall_svc-watchdog-swarm
docker service logs --since 2h oncall_svc-watchdog-swarm-next
```

The container logs of the manager are also in VictoriaLogs. For example, to see each run of `svc-watchdog-swarm-next`, run this query in the VictoriaLogs UI:

```text
_time:24h host:ops-vm-swarm-mgr-1 "swarm-check-next: checked"
```

## Maintenance

- Docker credentials must be kept current at `~/.docker/config.json`
- Update service runs on manager node (placement constraint enforced)
- Cleanup runs weekly on Monday at 03:30 UTC on all nodes
- Read the service logs to make sure that the scheduled tasks run
