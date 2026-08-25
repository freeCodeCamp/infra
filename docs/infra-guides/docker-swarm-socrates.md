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

`svc-redis` is deployed `mode: global` behind the `socrates.enabled` and `socrates.variant`
placement constraints, so every node that carries both labels runs its own instance and the
rate-limit bucket is per node rather than shared. nginx spreads a caller across all six containers
with `least_conn` and no session affinity (`upstream socrates` in the `nginx-config` repository),
so the effective per-user ceiling is `PER_USER_LIMIT` multiplied by the node count.

With three nodes, `PER_USER_LIMIT=10` allows about 30 requests per minute per user, and
`GLOBAL_LIMIT=1000` allows about 3000. Divide the configured values by the node count if the intent
is a hard number, and re-check them whenever a node is added or removed.

Redis backs only the rate limiter and the extended health check. It holds no cache, no sessions and
no queue.

## Redis is a hard boot dependency

Losing a node's Redis costs more than that node's rate-limit state. A container that is already
running survives the outage, but a container that restarts during one never comes back.

`@fastify/redis` releases plugin registration only once the client reaches `ready`, so registration
blocks until the client connects. It swallows an ordinary connection error, and the client's
`retryStrategy` always returns a delay, so ioredis retries forever and never emits `end`.

Fastify's 60-second `pluginTimeout` then fails the registration, `app.listen()` rejects, the
process exits 1, and the stack's `restart_policy: condition: any` starts it again into the same
wait. Any roll during an outage — an autoupdate, a Swarm reschedule, a manual redeploy — turns one
degraded node into a crash loop.

The healthcheck does not show this. `GET /health` answers HTTP 200 with `status: ok` even when the
extended check reports `redis: error`, so Swarm keeps a Redis-blind container in rotation and never
restarts one by itself. Read the container logs for `redis reconnecting`; do not trust the health
state.

Before you restart or redeploy a Socrates node, confirm that node's `svc-redis` task is running.

## Behaviour during a Redis outage

The deployed service allows every request through. It logs `rate limiter error, allowing request
through (fail-open)` and applies no ceiling, so an outage removes the only bound on Groq spend. Shed
load at the edge, because nothing below the edge will.

A bounded in-process fallback is written but not deployed. It is on the socrates
`fix/rate-limiter-fallback` branch. Rewrite this section when that branch ships.

The ceiling is soft even when Redis is healthy. `svc-redis` runs `--maxmemory 200mb
--maxmemory-policy allkeys-lru`, so it evicts rate-limit keys under memory pressure and a caller's
bucket can reset early.

## Notes

- Environment-specific naming allows managing multiple Socrates deployments
- All configuration is managed through Portainer
