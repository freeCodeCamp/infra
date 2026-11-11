# API Stack

Docker Swarm stack configuration for the freeCodeCamp API backend services.

## Overview

The API stack provides backend services for the freeCodeCamp platform. Service configuration is environment-specific and managed through environment variables.

## Components

| Service           | Purpose                |
| ----------------- | ---------------------- |
| **svc-api-alpha** | Backend API, port 2345 |
| **svc-api-bravo** | Backend API, port 2346 |

## Deployment

Name stacks per environment (`prd-api`, `stg-api`). Deploy them with the workflow `deploy-api.yml` in `freeCodeCamp/freeCodeCamp`. Run it on the branch `prod-current` for `prd-api`, or `prod-staging` for `stg-api`.

The workflow builds the image, then connects to the manager over Tailscale SSH. On the manager, it runs `docker stack deploy` with `stack-api.yml` in `~/docker-swarm-config/stacks/api`. The variables are in the age-encrypted secret `AGE_ENCRYPTED_ASC_SECRETS` of the GitHub environment `<env>-api`. The secret `TS_MACHINE_NAME` names the manager.

Do not deploy these stacks from the CLI. `docker stack deploy` reads variables only from your shell, and `docker/swarm/stacks/api/.env.sample` lists secrets. `infra-secrets` has no envelope for this stack, so a CLI deploy means typing secrets into the shell. An unset variable becomes an empty string in the live stack.

## Notes

- Environment-specific naming helps manage multiple API instances
