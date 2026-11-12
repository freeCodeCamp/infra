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

Both files also read optional variables for the published ports. The defaults are the host-mode ports. The routing mesh values are for each environment after its move to the mesh. Set them only after the live move of that environment: a deploy with them set and the old live ports moves the port in one roll, and NGINX gets refused connections until the proxies change. After the live move of an environment, export its values before each deploy of that environment. A deploy without them publishes the old ports again. Before you deploy one environment, `unset` the values of the other from the same shell. `NEWS_PUBLISH_MODE` applies to both batches of `prd-news`:

| Variable                                                                                                                                                                                    | Default       | Staging (mesh) | Production (mesh) |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- | -------------- | ----------------- |
| `NEWS_PUBLISH_MODE`                                                                                                                                                                         | `host`        | `ingress`      | `ingress`         |
| `NEWS_ENG_PUBLISHED_PORT` (`stack-news.prd.yml`)                                                                                                                                            | `4001`        | none           | `4201`            |
| `NEWS_CHN_PUBLISHED_PORT`, `NEWS_ESP_PUBLISHED_PORT`, `NEWS_ITA_PUBLISHED_PORT`, `NEWS_JPN_PUBLISHED_PORT`, `NEWS_KOR_PUBLISHED_PORT`, `NEWS_POR_PUBLISHED_PORT`, `NEWS_UKR_PUBLISHED_PORT` | `4002`-`4008` | `4102`-`4108`  | `4202`-`4208`     |

The services in both files have a health check (`wget` against port 3000 in the container). With ingress mode, the routing mesh sends traffic to a task only after it passes. With host mode, NGINX can reach a task as soon as its container starts. In both modes, a rolling update goes to the next task only after the new task passes, and Swarm replaces a task that fails the check.
