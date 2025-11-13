# News Stack

Docker Swarm stack configuration for the freeCodeCamp JAMStack news applications.

## Overview

The News stack provides static site hosting for the freeCodeCamp news and curriculum content. Services are deployed per environment with environment-specific configuration.

## Components

| Service | Purpose |
| --- | --- |
| **news** | JAMStack news applications and static content |

## Deployment

Name stacks per environment (e.g., `prd-news`, `stg-news`):

```bash
# Set context and deploy
docker context use <context_name>
docker stack deploy -c stack-news.yml prd-news
```

Then configure environment variables in Portainer UI for the deployed stack.

## Configuration

1. Copy `.env.sample` to `.env`
2. Set required environment variables in Portainer UI
3. Redeploy stack to apply changes

## Notes

- Environment-specific naming allows managing multiple news deployments
- All configuration is managed through Portainer
