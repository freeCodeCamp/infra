# News Stack

Docker Swarm stack configuration for the freeCodeCamp JAMStack news applications.

## Overview

The News stack provides static site hosting for the freeCodeCamp news and curriculum content. Services are deployed per environment with environment-specific configuration.

## Components

| Service | Purpose |
| --- | --- |
| **svc-chn**, **svc-esp**, **svc-ita**, **svc-jpn**, **svc-kor**, **svc-por**, **svc-ukr** | News sites, one service per language |
| **svc-eng** | English news. Commented out in `stack-news.yml`. |

## Deployment

Name stacks per environment (`prd-news`, `stg-news`). Deploy from Portainer, or from the CLI as below. After a CLI deploy, the copy that Portainer stores is old. Do not press Update for the stack in Portainer after a CLI deploy. Run the CLI block from the repository root.

`docker stack deploy` reads variables only from your shell. It does not read a `.env` file. Before a CLI deploy, export every variable that `docker/swarm/stacks/news/.env.sample` lists. An unset variable becomes an empty string, for example in the image name.

For `prd-news`, uncomment `svc-eng` in `stack-news.yml` first (`stack-news.yml:28-33`). The live `prd-news` stack runs `svc-eng`. A deploy without it does not remove the live service, but the file does not describe it.

```bash
cd docker/swarm/stacks/news
docker --context <context_name> stack deploy -c stack-news.yml <stack-name>
```

## Notes

- Environment-specific naming allows managing multiple news deployments
- All configuration is managed through Portainer
