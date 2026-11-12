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

`stack-api.yml` also reads optional variables for the published ports. The defaults are the host-mode ports. The routing mesh values are for each environment after its move to the mesh:

| Variable                   | Default | Staging (mesh) | Production (mesh) |
| -------------------------- | ------- | -------------- | ----------------- |
| `API_PUBLISH_MODE`         | `host`  | `ingress`      | `ingress`         |
| `API_ALPHA_PUBLISHED_PORT` | `2345`  | `2445`         | `2545`            |
| `API_BRAVO_PUBLISHED_PORT` | `2346`  | `2446`         | `2546`            |

Add these lines to `AGE_ENCRYPTED_ASC_SECRETS` of an environment only after the live move of that environment. A deploy with the lines set and the old live ports moves the port in one roll, and NGINX gets refused connections until the proxies change.

Before the live move, make sure that the manager checkout `~/infra` has these variables: run `play-vultr--manager.yml` again. The workflow does not update the checkout, and an old checkout ignores the variables. From the live move until the secret has the lines, do not run `deploy-api.yml` for that environment. A deploy in that window publishes the old ports again, and NGINX gets refused connections.

## Notes

- Environment-specific naming helps manage multiple API instances
