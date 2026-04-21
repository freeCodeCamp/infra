# API Stack

Docker Swarm stack configuration for the freeCodeCamp API backend services.

## Overview

The API stack provides backend services for the freeCodeCamp platform. Service configuration is environment-specific and managed through environment variables.

## Components

| Service | Purpose |
| --- | --- |
| **api** | Backend API services (environment-specific) |

## Configuration

### Environment Setup

Name stacks per environment (e.g., `prd-api`, `stg-api`) and configure via Portainer UI:

1. Copy `.env.sample` to `.env`
2. Set required environment variables in Portainer
3. Update `CADDY_CONFIG_NAME` to match your Caddyfile configuration

### Caddyfile Management

The Caddyfile (located in [`./Caddyfile`](./Caddyfile)) proxies requests to the correct API port.

**For each new Caddyfile version:**

1. Create a new Docker config in Portainer's `configs` section
2. Name it according to your versioning scheme
3. Set the `CADDY_CONFIG_NAME` environment variable to match

## Deployment

```bash
# Set context and deploy
docker context use <context_name>
docker stack deploy -c stack-api.yml prd-api
```

Then configure environment variables in Portainer UI for the deployed stack.

## Notes

- Environment-specific naming helps manage multiple API instances
- Caddyfile updates require creating new Docker configs and redeploying
- All configuration is managed through Portainer for consistency
