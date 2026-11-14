# News Stack

Docker Swarm stack configuration for the freeCodeCamp JAMStack news applications.

## Overview

The News stack provides static site hosting for the freeCodeCamp news and curriculum content. Services are deployed per environment with environment-specific configuration.

## Components

| Service                                                                                   | Purpose                                                 |
| ----------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| **svc-chn**, **svc-esp**, **svc-ita**, **svc-jpn**, **svc-kor**, **svc-por**, **svc-ukr** | News sites, one service per language                    |
| **svc-eng**                                                                               | English news. Production only, in `stack-news.prd.yml`. |

## Deployment

Name stacks per environment (`prd-news`, `stg-news`). Deploy from the CLI. Run each block from the repository root.

`docker stack deploy` reads variables only from your shell. It does not read a `.env` file. Before a CLI deploy, export every variable that `docker/swarm/stacks/news/.env.sample` lists. An unset variable becomes an empty string, for example in the image name.

Deploy `prd-news` in two batches. The first batch deploys the services in `stack-news.yml`. The second batch deploys `svc-eng` from `stack-news.prd.yml`. A batch changes only the services in its file.

```bash
docker --context vultr stack deploy -c docker/swarm/stacks/news/stack-news.yml prd-news
docker --context vultr stack deploy -c docker/swarm/stacks/news/stack-news.prd.yml prd-news
```

Deploy `stg-news` with the first batch only:

```bash
docker --context vultr stack deploy -c docker/swarm/stacks/news/stack-news.yml stg-news
```

Do not add `--prune` to a batch. It removes the services of the other batch.

The services have a health check (`wget` against port 3000 in the container). The services publish their ports in host mode, so NGINX can reach a task as soon as its container starts. A rolling update goes to the next task only after the new task passes, and Swarm replaces a task that fails the check.
