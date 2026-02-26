# Socrates Stack

Docker Swarm stack configuration for the Socrates AI hints API with Redis sidecar for caching and rate limiting.

## Overview

The Socrates stack provides the AI-powered hints API for freeCodeCamp coding challenges. It includes a Redis sidecar for caching and rate limiting. Services are deployed per environment with environment-specific configuration.

## Components

| Service      | Purpose                                    |
| ------------ | ------------------------------------------ |
| **socrates** | AI-powered hints API for coding challenges |
| **redis**    | Cache and rate limiting (sidecar)          |

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

## Notes

- Environment-specific naming allows managing multiple Socrates deployments
- All configuration is managed through Portainer
