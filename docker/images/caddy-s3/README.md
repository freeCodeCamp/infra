# caddy-s3

Caddy image for the `gxy-cassiopeia` static-serve plane. It serves every
`*.freecode.camp` constellation site straight from the Cloudflare R2 bucket.

Published as `ghcr.io/freecodecamp/caddy-s3`.

## Contents

The image is stock Caddy plus one in-tree plugin. It carries no third-party
Caddy module (ADR D32).

| Module                   | Purpose                                                        |
| ------------------------ | -------------------------------------------------------------- |
| `http.handlers.r2_alias` | Maps a Host header to a deploy, then rewrites the request path |
| `caddy.fs.r2`            | Reads object bytes from R2                                     |

The plugin source is a separate Go module at
[`caddy-r2alias/`](../../../caddy-r2alias) in this repo. This directory holds
only the image.

## How it serves a request

1. `r2_alias` parses the Host header into a site and an alias name. The site
   keeps the root domain. `hello.freecode.camp` gives site
   `hello.freecode.camp` with alias `production`, and
   `hello.preview.freecode.camp` gives the same site with alias `preview`.
2. It reads the alias object `<site>/<alias>` from R2. The body is a deploy ID.
3. It rewrites the request path to `/<site>/deploys/<deployID><cleanedPath>`.
   The visitor path is cleaned first, so a request can never leave the deploy.
4. `file_server` reads that key through `caddy.fs.r2`.

A deploy goes live when artemis writes a new deploy ID into the alias object.
The alias cache holds the result for 15 seconds, so a flip takes effect within
that window.

## Build

```sh
just build-caddy-s3     # tags ghcr.io/freecodecamp/caddy-s3:dev-<sha>
just verify-caddy-s3    # asserts both modules load and no third-party fs
```

The build context is the repository root, because the Dockerfile copies
`caddy-r2alias/`. The root `.dockerignore` sends only that directory.

GitHub Actions builds the canonical tag. The workflow is manual:

```sh
gh workflow run docker--caddy-s3.yml --ref <branch>
```

## Configuration

The chart supplies the Caddyfile. See
`k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/configmap.yaml`.

| Variable                | Purpose             |
| ----------------------- | ------------------- |
| `R2_BUCKET`             | Bucket name         |
| `R2_ENDPOINT`           | R2 S3 endpoint      |
| `AWS_ACCESS_KEY_ID`     | Read-only R2 key    |
| `AWS_SECRET_ACCESS_KEY` | Read-only R2 secret |

The key needs `GetObject` only. The plugin never lists the bucket.

## Demo

`demo/` runs the image against a local S3 mock with fixture sites. Start it
with `docker compose up` from that directory.

## Deploy

Pin the new digest in
`k3s/gxy-cassiopeia/apps/caddy/values.production.yaml`, then roll the chart
with `just release gxy-cassiopeia caddy`.
