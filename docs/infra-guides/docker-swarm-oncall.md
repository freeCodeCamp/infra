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
| **svc-chat-relay**            | Converts Gantry notices to the standard chat line             |
| **svc-chat-proxy**            | Forwards actionable notices and digests successful heartbeats |
| **svc-dispatch-news-eng**     | Starts the news `deploy-eng.yml` workflow every 3 hours       |
| **svc-dispatch-housekeeping** | Starts the infra `ansible--housekeeping.yml` workflow Wed/Sat |
| **svc-watchdog-news**         | Posts to Google Chat when the English news site is stale      |

## Architecture

```
Cronjob Scheduler → Scheduled Tasks
Service Updater → Auto-update tagged services
Cleanup Job → Weekly prune on all nodes
Webhook Receiver → On-demand Gantry updates (via GHA)
Dispatchers → GitHub workflow_dispatch (news deploys, housekeeping) ┐
Watchdog → news RSS lastBuildDate                                   ├→ Chat proxy → Google Chat
Gantry (cron and webhook) → Chat relay                              ┘
                              │
                              ├→ ✅ SQLite → daily digest at 00:00 UTC
                              └→ ⚠️ / 🔴 / unknown → durable delivery queue
All services → json-file logging (local, rotated)
```

## Prerequisites

- Docker Swarm cluster initialized
- Docker credentials at `~/.docker/config.json` on manager node
- The current single-manager placement retained for `chat_proxy_data`. The volume uses Docker's local driver; before adding another eligible manager, migrate the data or constrain the proxy to the labelled node that owns it.

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

Export these two variables before `docker stack deploy`. Container logs use the local `json-file` driver (rotated 10m × 3, compressed) — no logging credentials needed. The Chat destination and GitHub ingress HMAC are external Swarm secrets, not service environment values.

| Variable                | Used by                      | Value                                                                               |
| ----------------------- | ---------------------------- | ----------------------------------------------------------------------------------- |
| `WEBHOOK_SECRET`        | svc-webhook                  | Shared secret for `/hooks/run-gantry`. Same value as the GHA secret.                |
| `GITHUB_DISPATCH_TOKEN` | dispatchers                  | Fine-grained PAT of the bot account. Actions read/write on `news` and `infra` only. |

Anyone with Docker access on the manager can read these environment values. Docker administrators can also read mounted Swarm secrets from a task. Rotate affected credentials after removing such access.

### Swarm Config Names

Swarm configs are immutable. When you change `run_gantry.sh`, `hooks-relay.json`, a file in `scripts/`, or either file in `proxy/`, increase the version suffix of its `name:` in `stack-oncall.yml` (for example `oncall_scripts_lib_v1` → `oncall_scripts_lib_v2`). If you do not, `docker stack deploy` fails.

### Dispatchers

GitHub `schedule` triggers start late or do not start at all (observed since 2026-08-26). The dispatchers start the time-critical workflows from this stack. Each dispatcher sends one `POST /repos/<repo>/actions/workflows/<file>/dispatches` request to the GitHub API. It does not retry this request, because a retry can start a second run.

| Service                     | Schedule (UTC)   | Window policy |
| --------------------------- | ---------------- | ------------- |
| `svc-dispatch-news-eng`     | `0 5 */3 * * *`  | `avoid`       |
| `svc-dispatch-housekeeping` | `0 30 1 * * 3,6` | `require`     |

The maintenance window is Wed/Sat 00:00–06:00 UTC. `scripts/lib.sh` defines it once.

- `avoid`: inside the window, the dispatcher starts nothing. If the last completed run on the branch failed or was cancelled, the first skip of the window (00:00–03:00 UTC) posts a warning to Google Chat.
- `require`: outside the window, the dispatcher refuses and posts to Google Chat.

Every accepted dispatch or intentional maintenance-window skip emits an ok heartbeat. The proxy holds that heartbeat for the daily digest. The dispatcher posts actionable warnings/failures immediately when the API refuses the request, a prior run is bad, or a variable is missing. The housekeeping workflow also checks its own start time. It refuses to run outside the window unless you start it with `window_check=false`.

### Freshness Watchdog

`svc-watchdog-news` runs every hour at minute 50. It reads `<lastBuildDate>` from `https://www.freecodecamp.org/news/rss.xml`.

- Limit: 5 hours. The feed is stale when its build date is older than the limit.
- Posts: the first hour past the limit, then every 6 hours while the feed stays stale.
- Quiet hours: Wed/Sat 00:00–08:00 UTC. The first check after quiet hours posts if the feed is stale.
- The watchdog also posts when it cannot read the feed or the date.
- Every scheduled invocation emits one observable result. Healthy, quiet-hour, and between-reminder heartbeats are held by the proxy; stale/unreadable alerts are forwarded immediately.

### Google Chat Notifications

Every message from this stack and from the GitHub workflow notifiers is one line:

```text
<icon> *<source>* · <subject> · <summary> · <link|label>
```

- Icon: ✅ ok, ⚠️ warn, 🔴 fail.
- The link is optional. The GitHub workflows always link the run.
- A warn or fail message from a GitHub workflow can add detail lines below the line.
- `scripts/lib.sh` (`chat_notify`) and `.github/actions/notify-chat` make the line. Do not post to Google Chat in a different format.

Gantry sends its notifications to `svc-chat-relay` (`http://svc-chat-relay:9000/hooks/gantry`). The relay makes the standard line and posts it to the internal proxy. The subject is `hourly` for the cron run and `webhook` for a run from `/hooks/run-gantry`. Scheduled Gantry uses `GANTRY_NOTIFICATION_CONDITION=all` so even a no-change run supplies its expected heartbeat. Webhook-triggered Gantry remains `on-change`.

```text
✅ *gantry* · webhook · 1 service(s) updated: prd-news_svc-eng
🔴 *gantry* · hourly · 1 service(s) update failed: prd-news_svc-eng; 1 service(s) rollback failed: prd-news_svc-eng
```

`svc-chat-relay` and `svc-chat-proxy` publish no origin ports. The proxy listens on internal port 8080 for `/hooks/chat` and health/status, and separately on port 8081 for approved authenticated external routes. The Cloudflare Tunnel service must join `oncall_default` and target only `http://svc-chat-proxy:8081`; it must never target port 8080.

### Chat proxy behavior

`scripts/lib.sh` posts to `CHAT_PROXY_URL` when it is set and falls back to direct `GOOGLE_CHAT_WEBHOOK` delivery when it is not. The stack sets the internal URL `http://svc-chat-proxy:8080/hooks/chat`; only `svc-chat-proxy` receives the real Google Chat webhook.

The proxy keeps canonical events, delivery state, digests, and heartbeat state in `/data/chat-proxy.sqlite3` on the `chat_proxy_data` volume. It allows 45 seconds for bounded request/delivery shutdown and releases owned in-flight leases after workers stop cleanly:

- A request is accepted only after its event and routing action commit transactionally. A storage failure returns `503`; it is never bypassed with an unrecorded direct send.
- `✅` routine messages remain queued for the prior UTC day's digest. Empty days produce no digest.
- `⚠️`, `🔴`, and unknown text create durable immediate deliveries. The HTTP request returns `202` after commit without waiting for Chat; a separate delivery worker is woken immediately.
- Transient Chat failures retry nine times through 24 hours with jitter. Terminal failures and exhausted retries become retained dead letters for operator replay.
- Delivery is at-least-once: an unlikely crash after Chat accepts a message but before SQLite records success can produce a duplicate rather than silently lose an alert.
- Delivered digest events retain 30 days; delivered immediate events retain 90 days. Pending deliveries and unresolved dead letters do not age out.
- Exact legacy retries are suppressed for five minutes. Distinct states and cron occurrences remain separate.
- The SQLite backup API is used for consistent backups; do not copy a live WAL database as individual files.

The expected cron schedules are copied from `stack-oncall.yml` into `proxy/cron-expectations.json`. The proxy tests fail if those values drift. Dispatch, watchdog, and hourly Gantry have a 15-minute grace period. Any matching ok, warning, or failure proves that the scheduler ran. Consecutive misses form one outage episode: alerts are queued initially, at +1 hour, +6 hours, and +24 hours, then stop until one immediate reporting-recovered message.

`GET /livez` proves that the HTTP process is serving. `GET /readyz` checks that the Chat destination secret is loaded, the schema/migration version, SQLite and foreign-key integrity, writable transactional acceptance, and the 64 MiB free-space floor; the stack health check uses readiness. `GET /statusz` exposes only bounded operational counts, ages, and sizes (queue, retries, dead letters, overdue digest, scheduler, database bytes, and free bytes), never message content or paths. The proxy rejects new immediate deliveries with `503` at 10,000 active deliveries rather than growing that queue without bound; routine digest events remain acceptable so heartbeat evidence is not lost during a Chat outage. `GET /healthz` remains a liveness-compatible alias.

Both listeners cap active request workers at 64. Repeated identical sanitized auth/adapter failure metadata is written at most once per ten seconds; the 10,000-row retention cap remains a storage bound, not a substitute for Cloudflare edge rate controls.

The legacy `/hooks/chat` endpoint remains internal and unauthenticated. GitHub Actions uses `POST /v1/events/github-actions` on the isolated external listener with `X-FCC-Timestamp` and exact-body `X-FCC-Signature` HMAC headers. The route accepts the current and optional previous GitHub-only secret during a bounded rotation and deduplicates repository/run/attempt/logical-key identities for 90 days; conflicting identity reuse returns `409`. Grafana will receive a separate route and credential. Sentry and UptimeRobot remain outside the proxy on their existing direct alert paths.

### Tests

Run from the repository root:

```bash
python3 -m unittest discover -s docker/swarm/stacks/oncall/proxy -p 'test_*.py' -v
sh docker/swarm/stacks/oncall/scripts/test.sh
bash .github/actions/notify-chat/test.sh
WEBHOOK_SECRET=x GITHUB_DISPATCH_TOKEN=x \
  docker stack config -c docker/swarm/stacks/oncall/stack-oncall.yml >/dev/null
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

# Pin the local SQLite volume to the approved manager/data-owner node.
docker node update --label-add chat_proxy_data=true <data-owner-node>

# Set the stack environment (logging is local json-file — no logging env needed).
export WEBHOOK_SECRET="<strong-random-string>"
export GITHUB_DISPATCH_TOKEN="<bot fine-grained PAT>"

# Create the versioned Chat destination secret once through the approved secure input path.
# Do not put the webhook URL in shell history or the Swarm service environment.
read -rsp "Google Chat webhook: " GOOGLE_CHAT_WEBHOOK; echo
printf %s "$GOOGLE_CHAT_WEBHOOK" | docker secret create oncall_google_chat_webhook_v1 -
unset GOOGLE_CHAT_WEBHOOK

# Create a distinct GitHub ingress HMAC through the approved secure input path.
# Install this same value as the non-production GitHub repository secret only
# after the test proxy endpoint exists; never reuse the Chat webhook or Gantry secret.
read -rsp "GitHub Actions proxy HMAC: " GITHUB_ACTIONS_HMAC; echo
printf %s "$GITHUB_ACTIONS_HMAC" | docker secret create oncall_github_actions_hmac_v1 -
unset GITHUB_ACTIONS_HMAC

# The stack always mounts a distinct previous slot so rotation never needs an
# environment secret. For the first deploy, fill it with an unused random value.
read -rsp "Dormant previous-slot HMAC: " GITHUB_ACTIONS_HMAC_PREVIOUS; echo
printf %s "$GITHUB_ACTIONS_HMAC_PREVIOUS" | docker secret create oncall_github_actions_hmac_previous_v1 -
unset GITHUB_ACTIONS_HMAC_PREVIOUS

# Create a distinct Grafana ingress HMAC. Store the same current value as
# DEVOPS_ALERTS_GRAFANA_HMAC in the mgmt-grafana-alerting OnePassword item.
read -rsp "Grafana proxy HMAC: " GRAFANA_HMAC; echo
printf %s "$GRAFANA_HMAC" | docker secret create oncall_grafana_hmac_v1 -
unset GRAFANA_HMAC

# Keep a mounted, distinct, unused previous slot for bounded rotation overlap.
read -rsp "Dormant Grafana previous-slot HMAC: " GRAFANA_HMAC_PREVIOUS; echo
printf %s "$GRAFANA_HMAC_PREVIOUS" | docker secret create oncall_grafana_hmac_previous_v1 -
unset GRAFANA_HMAC_PREVIOUS

# Deploy stack from the repository root
docker stack deploy -c docker/swarm/stacks/oncall/stack-oncall.yml oncall
```

For GitHub credential rotation, create a new versioned Swarm secret, change `chat_proxy_github_actions_hmac.name` to it, and point `chat_proxy_github_actions_hmac_previous.name` to the formerly current secret. Deploy and confirm both old and new signed test requests during the bounded overlap. Then update `DEVOPS_ALERTS_GITHUB_HMAC` in GitHub, exercise all notifier paths, replace the previous slot with a distinct unused random secret, and deploy again.

Grafana rotation uses the same sequence with `chat_proxy_grafana_hmac`, `chat_proxy_grafana_hmac_previous`, and the `DEVOPS_ALERTS_GRAFANA_HMAC` field in `mgmt-grafana-alerting`. Never configure equal current/previous values; startup fails closed.

**Note:** The update service runs on the manager node via cronjob scheduling (managed by `svc-cronjob`).

**Portainer:** Portainer lists this stack, but its stored copy is old and has no config files. Deploy only with `docker stack deploy` from this directory. Do not press Update for this stack in Portainer, because that replaces the live stack with the old copy.

**Cutover order:** Merge the infra changes first, then deploy this stack from `main`. Then, on the same day, merge the news changes that remove the news `schedule` triggers. Do not do the cutover on Wed/Sat before 06:00 UTC. The infra merge removes the housekeeping `schedule`, so deploy this stack before the next Wed/Sat 01:30 UTC. Until the news merge, a news deploy can run twice. This is harmless.

## Coordinated alert-proxy cutover plan

This is a plan, not authorization to deploy. Use one `infra-team` window only after the test ingress, off-host backup, timed restore, independent monitoring, sanitized Grafana fixtures, and full non-production matrix are complete.

| System | Old path | New path | Validate before removing old path | Rollback |
| --- | --- | --- | --- | --- |
| Oncall producers | Direct Chat fallback | Internal `/hooks/chat` on port 8080 | Dispatch/watchdog/Gantry acceptance, immediate alerts, heartbeat state, and digest | Restore the prior stack revision; retain the SQLite volume |
| GitHub Actions | `GOOGLE_CHAT_WEBHOOK` | Signed `/v1/events/github-actions` | ok/warn/fail workflow dispatches, run-scoped dedupe, and no workflow-result coupling | Revert notifier/callers and restore the still-retained Chat secret |
| Grafana | Native `googlechat` contact point | Native HMAC webhook to `/v1/events/grafana` | test, firing, repeat, resolved, `DatasourceNoData`, `DatasourceError`, grouping, and page email | Revert `values-mgmt.yaml` to `googlechat` and reconcile Flux |
| Sentry | Existing direct destination | Unchanged | Approved direct-path test before and after | No proxy action; restore only its external configuration if independently changed |
| UptimeRobot | Existing direct destination | Unchanged | Approved direct-path test and independent proxy monitor/email | No proxy action; restore only its external configuration if independently changed |

Record non-secret preflight evidence from the repository root:

```bash
docker node ls
docker node inspect <data-owner-node> --format '{{ json .Spec.Labels }}'
docker secret ls --filter name=oncall_
WEBHOOK_SECRET=x GITHUB_DISPATCH_TOKEN=x \
  docker stack config -c docker/swarm/stacks/oncall/stack-oncall.yml >/dev/null

gh secret list --repo freeCodeCamp/infra

KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get nodes -o wide
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y get \
  externalsecret/grafana-alerting helmrelease/grafana
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y get \
  secret/grafana-alerting -o json | jq -r '.data | keys[]'
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml helm -n o11y list
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml helm -n o11y get values grafana
```

Do not decode or print Kubernetes, Swarm, GitHub, Cloudflare, Chat, or HMAC secrets. The `grafana-alerting` key list must include `DEVOPS_ALERTS_GRAFANA_URL` and `DEVOPS_ALERTS_GRAFANA_HMAC`; keep `GOOGLE_CHAT_WEBHOOK_URL` through the rollback window.

Execute the approved window in this order:

1. Freeze the reviewed commit and record Swarm, Flux, Grafana Helm, GitHub workflow, Cloudflare, and secret-version rollback references.
2. Complete and verify the SQLite off-host backup. Confirm the selected data-owner node and independent email monitor.
3. Create all external Swarm secrets, deploy the proxy/Cloudflare Tunnel, and verify only port 8081 is a tunnel origin. Verify `/livez`, `/readyz`, `/statusz`, and `/hooks/chat` are not public.
4. Send authenticated GitHub and Grafana smoke events to the test destination, then the production destination only after explicit go/no-go approval. Confirm transactional event/delivery rows and empty auth/adapter-failure counters.
5. Install GitHub endpoint/HMAC secrets. Exercise one low-risk notification, then all three logical notifier paths. Keep `GOOGLE_CHAT_WEBHOOK` available for rollback.
6. Add `DEVOPS_ALERTS_GRAFANA_URL` and `DEVOPS_ALERTS_GRAFANA_HMAC` to `mgmt-grafana-alerting`, wait for ExternalSecret refresh, and reconcile Grafana. Use the contact-point test, then controlled firing/resolved rules. Confirm the `severity=page` email route independently.
7. Verify internal oncall producers, all heartbeat identities, queue state, dead letters, scheduler age, backup age, and the next digest.
8. Verify Sentry and UptimeRobot still use their unchanged direct destinations.
9. Remove old producer access to Chat only after that producer passes, and revoke superseded credentials only after the rollback window.

Grafana verification and rollback commands must always carry the kubeconfig explicitly:

```bash
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y wait \
  --for=condition=Ready externalsecret/grafana-alerting --timeout=5m
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y rollout status \
  deployment/grafana --timeout=10m
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml helm -n o11y status grafana
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml helm -n o11y get values grafana
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y logs \
  deployment/grafana --since=15m | grep -E 'alert|webhook|notify'
```

If Grafana validation fails, revert the cutover commit so `ops-chat-googlechat` is restored, reconcile the `ops-o11y` Flux source/Kustomization using the repository's normal Flux procedure, and repeat the status commands above. Do not delete the proxy's accepted events or SQLite volume during source rollback. If queue age, storage readiness, auth/adapter failures, or dead letters breach the approved abort threshold, stop migrating producers and roll back already migrated sources in reverse order.

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
docker service logs --since 2h oncall_svc-chat-proxy
docker service logs --since 3h oncall_svc-dispatch-news-eng
docker service logs --since 96h oncall_svc-dispatch-housekeeping
docker service logs --since 2h oncall_svc-watchdog-news
docker service logs --since 168h oncall_svc-cleanup
```

## Proxy verification and rollback

After deployment, verify the service and its persistent state on the manager:

```bash
docker node inspect <data-owner-node> --format '{{ index .Spec.Labels "chat_proxy_data" }}'
docker service ps oncall_svc-chat-proxy
docker service logs --since 15m oncall_svc-chat-proxy
docker volume inspect oncall_chat_proxy_data
proxy_container=$(docker ps -q --filter name=oncall_svc-chat-proxy)
docker exec "$proxy_container" python3 -c \
  "import json,urllib.request; print(json.load(urllib.request.urlopen('http://127.0.0.1:8080/readyz')))"
docker exec "$proxy_container" python3 -c \
  "import json,urllib.request; print(json.load(urllib.request.urlopen('http://127.0.0.1:8080/statusz')))"
docker exec "$proxy_container" python3 -c \
  "import sqlite3; db=sqlite3.connect('/data/chat-proxy.sqlite3'); assert db.execute('PRAGMA quick_check').fetchone()[0] == 'ok'"
```

Confirm one dispatch, watchdog, and hourly Gantry heartbeat reaches proxy storage before relying on missed-tick alerts. Success heartbeats must not appear immediately in Chat; warnings and failures must.

### SQLite backup and restore

Use the SQLite backup API; never copy the live database, WAL, and shared-memory files independently. A backup is validated and atomically replaced at its destination. Copy the resulting file to the approved off-host destination before considering the backup complete, then remove the local staging copy.

```bash
proxy_container=$(docker ps -q --filter name=oncall_svc-chat-proxy)
docker exec "$proxy_container" python3 -c \
  "import sys; sys.path.insert(0, '/app'); from chat_proxy import backup_database; backup_database('/data/chat-proxy.sqlite3', '/data/chat-proxy-backup.sqlite3')"
docker cp "$proxy_container:/data/chat-proxy-backup.sqlite3" ./chat-proxy-backup.sqlite3
# Transfer ./chat-proxy-backup.sqlite3 to the approved off-host destination.
rm -f ./chat-proxy-backup.sqlite3
docker exec "$proxy_container" rm -f /data/chat-proxy-backup.sqlite3
```

Restore only while the proxy service is stopped. The restore helper validates schema, migration, full SQLite integrity, and foreign keys; installs atomically; and removes stale WAL sidecars. Run from the repository root on the data-owner node:

```bash
# First retrieve the selected off-host backup to this protected local path.
chmod 600 /tmp/chat-proxy-restore.sqlite3
docker service scale oncall_svc-chat-proxy=0
# Wait until `docker service ps oncall_svc-chat-proxy` shows no running proxy task.
docker run --rm \
  -v oncall_chat_proxy_data:/data \
  -v "$PWD/docker/swarm/stacks/oncall/proxy:/app:ro" \
  -v /tmp/chat-proxy-restore.sqlite3:/restore.sqlite3:ro \
  python:3.12.15-alpine3.24@sha256:1b668429b3511ab407d8e00648891631b0b1a4d7e15e3ca70f38ab5b91ad4ab4 \
  python3 -c "import sys; sys.path.insert(0, '/app'); from chat_proxy import restore_database; restore_database('/restore.sqlite3', '/data/chat-proxy.sqlite3')"
docker service scale oncall_svc-chat-proxy=1
rm -f /tmp/chat-proxy-restore.sqlite3
```

Repeat the readiness, status, and `PRAGMA quick_check` verification above, then confirm queue, dead-letter, digest, and heartbeat counts against the backup record before resuming dependent changes.

To roll notification routing back, deploy the previously recorded good revision. `scripts/lib.sh` retains direct-webhook fallback when `CHAT_PROXY_URL` is absent. Do not delete `oncall_chat_proxy_data` during rollback; it contains the pending digest and cron state.

```bash
# Run from the repository root; replace <known-good-commit> with the revision recorded before deployment.
git worktree add /tmp/infra-oncall-rollback <known-good-commit>
docker stack deploy -c /tmp/infra-oncall-rollback/docker/swarm/stacks/oncall/stack-oncall.yml oncall
git worktree remove /tmp/infra-oncall-rollback
```

## Maintenance

- Docker credentials must be kept current at `~/.docker/config.json`
- Update service runs on manager node (placement constraint enforced)
- Cleanup runs weekly on Monday at 03:30 UTC on all nodes
- Read the service logs to make sure that the scheduled tasks run
- Keep `proxy/cron-expectations.json` synchronized with monitored schedule labels in `stack-oncall.yml`; the unit test enforces exact schedule strings
