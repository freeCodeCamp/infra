# Socrates Stack

Docker Swarm stack configuration for the Socrates AI hints API with a Redis sidecar for rate limiting.

## Overview

The Socrates stack provides the AI-powered hints API for freeCodeCamp coding challenges. It includes a Redis sidecar for rate limiting. Services are deployed per environment with environment-specific configuration.

## Components

| Service      | Purpose                                    |
| ------------ | ------------------------------------------ |
| **socrates** | AI-powered hints API for coding challenges |
| **redis**    | Rate limiting (sidecar)                    |

## Deployment

Name stacks per environment (e.g., `prd-socrates`, `stg-socrates`):

```bash
# Set context and deploy
docker context use <context_name>
docker stack deploy -c stack-socrates.yml stg-socrates
docker stack deploy -c stack-socrates.yml prd-socrates
```

Then configure environment variables in Portainer UI for the deployed stack.

## Configuration

1. Copy `.env.sample` to `.env`
2. Set required environment variables in Portainer UI
3. Redeploy stack to apply changes

## Node Labels

Nodes running Socrates services require specific labels:

```shell
docker node update --label-add "socrates.enabled=true" <node id>
docker node update --label-add "socrates.variant=dev" <node id>
# or
docker node update --label-add "socrates.variant=org" <node id>
```

## Rate limit ceilings

`svc-redis` is deployed `mode: global`, so every node runs its own instance and the rate-limit
bucket is per node rather than shared. nginx spreads a caller across all six containers with
`least_conn` and no session affinity (`upstream socrates` in the `nginx-config` repository), so the
effective per-user ceiling is `PER_USER_LIMIT` multiplied by the node count.

With three nodes, `PER_USER_LIMIT=10` allows about 30 requests per minute per user, and
`GLOBAL_LIMIT=1000` allows about 3000. Divide the configured values by the node count if the intent
is a hard number, and re-check them whenever a node is added or removed.

Redis backs only the rate limiter and the extended health check. It holds no cache, no sessions and
no queue, so losing a node's Redis costs only that node's rate-limit state. The service falls back
to an in-process bucket rather than allowing every request through.

## Notes

- Environment-specific naming allows managing multiple Socrates deployments
- All configuration is managed through Portainer
