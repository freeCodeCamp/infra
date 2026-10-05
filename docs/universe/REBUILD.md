# Universe rebuild

The Universe platform was torn down in October 2026. No data was kept: no databases, no buckets, no deploy history. If the team builds Universe again, it builds it from scratch. This page tells you where the code and the instructions are.

## Code

Each repository is archived (read-only) or keeps the commit below in its history.

| Component                                              | Repository                                         | Last commit    |
| ------------------------------------------------------ | -------------------------------------------------- | -------------- |
| Galaxy IaC: k3s apps, Terraform, Ansible, recipes      | `freeCodeCamp/infra`                               | `027d913d6f38` |
| `caddy-s3` image source (`caddy-r2alias/`, Dockerfile) | `freeCodeCamp/infra`                               | `027d913d6f38` |
| artemis (deploy proxy)                                 | `freeCodeCamp/artemis`                             | `9fb3424b1e61` |
| universe-cli                                           | `freeCodeCamp-Universe/universe-cli`               | `bc19f1d79a85` |
| veritas (sign-in)                                      | `freeCodeCamp/veritas`                             | `4b25a83d8206` |
| veritas deploy IaC (not merged)                        | `freeCodeCamp/infra`, branch `feat/veritas`        | `32aa2e547ba9` |
| Constellation apps                                     | `freeCodeCamp-Universe/*`                          | default branch |
| Design decisions (ADRs)                                | `freeCodeCamp-Universe/Architecture`, `decisions/` | default branch |

Check out `freeCodeCamp/infra` at `027d913d6f38` to get the IaC that matches the flight manuals.

## Build order

Use the flight manuals in [`flight-manuals/`](flight-manuals/00-index.md), in this order:

1. [`UNIVERSE.md`](flight-manuals/UNIVERSE.md): prerequisites, DNS, keys, shared infrastructure.
1. [`gxy-management.md`](flight-manuals/gxy-management.md): artemis, Hatchet, Valkey, CNPG.
1. [`gxy-cassiopeia.md`](flight-manuals/gxy-cassiopeia.md): the `caddy-s3` static-site plane.
1. `UNIVERSE.md` §99: the smoke test across galaxies.

`gxy-launchbase` was a standby galaxy with no workload. You do not need it.

## Images

The last deployed pins. Build `artemis` and `caddy-s3` again from the commits above if a pin no longer pulls.

| Image                                         | Pin                                                                                                                    |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `ghcr.io/freecodecamp/artemis`                | `1.13.0@sha256:395e3da3f7b88f75fa01e2a6ed0bcc10530ec793d38ef9058dcc99a5c42a5757`                                       |
| `ghcr.io/freecodecamp/caddy-s3`               | `sha-5c8daf9d049f352b30e961bb621cb997cf8a9944@sha256:9501221230d55df7787c58fe9722b48a99749febfe1d822c9a2f27fdf790e894` |
| `ghcr.io/freecodecamp/postgres-rclone`        | `@sha256:b9da73ecd905b277b2a65d7ebf32369d66dde595f0a2c4155d64d2b5ab7fab23`                                             |
| `postgres` (artemis chart default)            | `16.14-alpine@sha256:16bc17c64a573ef34162af9298258d1aec548232985b33ed7b1eac33ba35c229`                                 |
| `valkey/valkey`                               | `8.1.4-alpine@sha256:e706d1213aaba6896c162bb6a3a9e1894e1a435f28f8f856d14fab2e10aa098b`                                 |
| `ghcr.io/hatchet-dev/hatchet/hatchet-engine`  | `v0.91.2@sha256:d877fb68b55d6986af0dedaf7da0c44a66749a36c15a72e55d7a3d206198a0ac`                                      |
| `ghcr.io/hatchet-dev/hatchet/hatchet-admin`   | `v0.91.2@sha256:01f2604695932ca95e0d3a6e9813952cf3606469334ce268ae72c89176902343`                                      |
| `ghcr.io/hatchet-dev/hatchet/hatchet-migrate` | `v0.91.2@sha256:b31a8358021fbc33b25849dd8fd21d090b3d4e5ff35c6b7a4a03faaa0b0aed5b`                                      |
| `ghcr.io/cloudnative-pg/cloudnative-pg`       | `1.30.0@sha256:a2701eb97cdd2a34b1fdb2cb51987f544b706e40bec72ae7146cd8580efefebb` (chart `0.29.0`)                      |
| `ghcr.io/cloudnative-pg/postgresql`           | `16.14-standard-bookworm@sha256:b459345655ea1a0438a219f599cbae509c3132dc8faad6d729d6957e70a618bb`                      |

## Accounts

| Service      | What Universe used                                                                                       |
| ------------ | -------------------------------------------------------------------------------------------------------- |
| DigitalOcean | Team "No-ClickOps", region FRA1, VPC `gxy-vpc-fra1` (shared, still exists), one Space for etcd snapshots |
| Cloudflare   | Zone `freecode.camp` (DNS, cache rule, certificates); R2 buckets for site content and database backups   |
| GitHub       | Org `freeCodeCamp-Universe`; a GitHub App for repo creation; an OAuth app for artemis sign-in            |
| Sentry       | Org `freecodecamp`, project `artemis`                                                                    |
| npm          | `@freecodecamp/universe-cli` (deprecated)                                                                |

## Keys

Mint every key again. No old key works. The names below are what the code reads.

| Component    | Key names                                                                                                                                                                                                                                                                                                                                    |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Galaxies     | `DO_API_TOKEN`, `DO_SPACES_ACCESS_KEY`, `DO_SPACES_SECRET_KEY`; Terraform state: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL_S3`                                                                                                                                                                                         |
| artemis      | `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `GH_CLIENT_ID`, `GH_ORG`, `GH_APP_ID`, `GH_APP_INSTALLATION_ID`, `GH_APP_PRIVATE_KEY`, `JWT_SIGNING_KEY`, `SENTRY_DSN`, `DATABASE_URL`, `HATCHET_ADDR`, `HATCHET_CLIENT_TOKEN`, `VALKEY_PASSWORD`, `POSTGRES_PASSWORD`, `ARTEMIS_DB_PASSWORD`, `HATCHET_DB_PASSWORD` |
| universe-cli | `RELEASE_PLEASE_APP_ID` (GitHub variable for releases)                                                                                                                                                                                                                                                                                       |
| Hatchet      | `DATABASE_URL`                                                                                                                                                                                                                                                                                                                               |
| Valkey       | `VALKEY_PASSWORD`                                                                                                                                                                                                                                                                                                                            |
| caddy-s3     | `r2.endpoint`, `r2.accessKeyId`, `r2.secretAccessKey`                                                                                                                                                                                                                                                                                        |
| veritas      | `BETTER_AUTH_SECRET`, `GOOGLE_CLIENT_*`, `GITHUB_CLIENT_*`, `APPLE_CLIENT_*`, `INTERNAL_API_TOKEN`, `SMTP_USER`, `SMTP_PASS`, `cnpgR2.*`, `tls.*`                                                                                                                                                                                            |

The envelope layout is in [`rfc-secrets-layout.md`](https://github.com/freeCodeCamp/infra/blob/027d913d6f38/docs/architecture/rfc-secrets-layout.md).
