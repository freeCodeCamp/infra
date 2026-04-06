# Docker Swarm Deployment Migration

Migration plan to consolidate all Docker Swarm deployments onto Gantry-based updates.

## Current State

Three distinct deployment patterns exist across the platform:

### Pattern 1: GHA SSH Deploy (API)

Source repo builds and pushes a pinned image tag to DOCR, then SSHs into the swarm manager over Tailscale, decrypts secrets with age, and runs `docker stack deploy`.

- **Stacks**: `prd-api`, `stg-api`
- **Workflow**: `freeCodeCamp/.github/workflows/deploy-api.yml`
- **Image tag**: Pinned (`a72fe073-20260402-1852`), no `:latest`
- **Autoupdate label**: Missing
- **Secrets**: age-encrypted blob decrypted on remote host during deploy

### Pattern 2: Gantry Webhook (Socrates)

Source repo builds and pushes `:latest` to DOCR. GHA triggers a Gantry webhook over Tailscale. Gantry pulls the new image and performs a rolling update.

- **Stacks**: `prd-socrates`, `stg-socrates`
- **Workflow**: `socrates/.github/workflows/deploy.yml`
- **Image tag**: `:latest`
- **Autoupdate label**: Present

### Pattern 3: Gantry Cron Autoupdate (News)

Source repo builds and pushes `:latest` to DOCR on a schedule. Gantry picks up changes on its hourly cron sweep. No GHA deploy step.

- **Stacks**: `prd-news`, `stg-news` (stg excluded from cron sweep)
- **Workflow**: `news/.github/workflows/deploy-eng.yml`, `deploy-i18n.yml` (build-only)
- **Image tag**: `:latest`
- **Autoupdate label**: Present

### Stacks Not Affected

| Stack       | Reason                                           |
| ----------- | ------------------------------------------------ |
| `oncall`    | Infra-managed, third-party images, manual deploy |
| `portainer` | Infra-managed, official images, manual deploy    |

## Target State

All application stacks use Gantry webhook-triggered updates:

1. Source repos build and push images with both a pinned tag and `:latest` to DOCR.
2. GHA triggers the Gantry webhook (`/hooks/run-gantry`) over Tailscale with a service name filter.
3. Gantry pulls the new `:latest` image and performs a rolling update with rollback on failure.
4. Gantry's hourly cron sweep acts as a safety net for any missed webhook triggers.

### Operational Model

- **Initial deploy / redeploy**: Via Portainer UI. Upload the stack YAML from `infra/docker/swarm/stacks/`, configure environment variables in the Portainer stack editor.
- **Ongoing updates**: Source repos push images, GHA triggers Gantry webhook.
- **Secret / env var changes**: Via Portainer UI (update env vars, redeploy stack). Gantry only swaps images — env vars persist in the swarm service definition.
- **Stack definitions**: Live in `infra/docker/swarm/stacks/` as the single source of truth.
- **Portainer**: Stack deployment UI, env var management, and observability dashboard.

## Migration Steps

### API (freeCodeCamp repo + infra repo) -- PARKED

API migration to Gantry webhook is deferred. The SSH-based deploy path remains active.

#### Completed

- [x] PR #66826: add missing required vars (`SES_SMTP_USERNAME`, `SES_SMTP_PASSWORD`, `SOCRATES_API_KEY`, `SOCRATES_ENDPOINT`) to deploy script

#### Future work (Gantry migration)

- [ ] Bake `BUILD_VERSION` into API Docker image (Dockerfile `ARG` → `ENV`)
- [ ] Replace SSH deploy job with Gantry webhook trigger
- [ ] Switch stack image tag to `:latest`
- [ ] Remove age-decrypt and SSH connection steps from GHA workflow

#### Gantry webhook call (reference from socrates)

```yaml
- name: Trigger Gantry via Webhook
  env:
    WEBHOOK_HOST: ${{ secrets.WEBHOOK_HOST }}
    WEBHOOK_SECRET: ${{ secrets.WEBHOOK_SECRET }}
    STACK_NAME: prd-api # or stg-api
  run: |
    curl -fsS -X POST "https://$WEBHOOK_HOST/hooks/run-gantry" \
      -H "Content-Type: application/json" \
      -H "X-Webhook-Secret: $WEBHOOK_SECRET" \
      -d "{\"GANTRY_SERVICES_FILTERS\":\"name=${STACK_NAME}_svc-api\"}"
```

### Socrates (socrates repo + infra repo) -- DONE

#### socrates repo

- [x] Remove the `deploy-full` job entirely
- [x] Remove the `deploy_mode` input and validation (always Gantry)
- [x] Simplify `build.yml` to remove the `deploy_mode` input passthrough
- [x] Bake `BUILD_VERSION` into image via Dockerfile `ARG` → `ENV`
- [x] Pass tagname as build arg in `build.yml`
- [x] Add `/health/version` endpoint returning baked version
- [x] Webhook verified working against `stg-socrates` (2026-04-06)

#### infra repo: `docker/swarm/stacks/socrates/`

- [x] Remove `org.freecodecamp.autoupdate=true` label (webhook-only, no cron watch)
- [x] Switch image tag to `:latest`
- [x] Remove `BUILD_VERSION` from stack YAML and `.env.sample` (baked in image)

#### Deployed

- [x] `stg-socrates` redeployed via Portainer, version endpoint confirmed: `f54cf3c-20260406-1305`
- [x] `prd-socrates` redeployed via Portainer (awaiting org image build for version endpoint)

### News

No changes. Already on the target model (cron autoupdate). Webhook-triggered deploys can be added later if faster propagation is needed.

## Cluster Topology Reference

### Nodes (19 total)

| Group    | prd Nodes                   | stg Nodes               | Labels                                               |
| -------- | --------------------------- | ----------------------- | ---------------------------------------------------- |
| Socrates | api-1/2/3.oldeworld.prd     | api-1/2/3.oldeworld.stg | `socrates.enabled=true`, `socrates.variant=org\|dev` |
| API      | api-4/5/6.oldeworld.prd     | api-4/5/6.oldeworld.stg | `api.enabled=true`, `api.variant=org\|dev`           |
| News     | jms-1/2/3.oldeworld.prd     | jms-1/2/3.oldeworld.stg | `jms.enabled=true`, `jms.variant=org\|dev`           |
| Manager  | backoffice.freecodecamp.net | —                       | `portainer=true`, `monitoring=true`                  |

### Gantry Configuration (oncall stack)

- **Cron**: Hourly at :45, filters on `label=org.freecodecamp.autoupdate`
- **Exclusion**: `name=stg-news` (intentionally frozen)
- **Webhook**: Port 9889, triggers on-demand Gantry runs with caller-specified filters

## Open Items

- [ ] Investigate `env=stg` label present on stg nodes but absent from prd nodes (cosmetic drift, not blocking)
- [ ] Client deployment (PM2 + serve on bare VMs) is out of scope for this migration
- [ ] Decide whether stg-api should also get Gantry updates or remain manually deployed
- [ ] Remote checkout paths on manager node can be cleaned up after SSH deploy paths are fully removed
