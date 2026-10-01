# r2_alias demo

Self-contained demo of the `caddy.fs.r2` + `r2_alias` stack that powers
`gxy-cassiopeia`. No cluster, no Cloudflare, no third-party image — just Docker.

## What it proves

1. Caddy reads an alias file from an S3-compatible bucket, rewrites the request
   path to the pinned deploy ID, and streams the object body back.
2. A promote or a rollback is one alias write. Nothing else moves.
3. A preview host resolves through a second alias while it shares the same
   deploy storage.
4. A visitor cannot read outside the deploy the alias selected.

## Stand up

```bash
cd docker/images/caddy-s3/demo
docker compose up --build
```

Wait for `caddy-1 | ... server running`, then from another terminal:

```bash
curl -H 'Host: demo.test.camp' http://localhost:8080/
```

You get the **v1** page.

## Flip the alias

The bucket is the `fixtures/` directory, so an alias write is a file write:

```bash
echo -n v2 > fixtures/demo.test.camp/production
```

After the 2 s cache TTL:

```bash
curl -H 'Host: demo.test.camp' http://localhost:8080/
```

You get the **v2** page. Write `v1` back to roll back.

## Other scenarios

Preview routing. The `preview` alias already points at v2:

```bash
curl -H 'Host: demo.preview.test.camp' http://localhost:8080/
```

Missing site:

```bash
curl -i -H 'Host: ghost.test.camp' http://localhost:8080/    # 404
```

Deploy containment. The visitor path is cleaned before it is joined to the
deploy prefix, so no request escapes:

```bash
curl -i --path-as-is -H 'Host: demo.test.camp' \
  'http://localhost:8080/../../production'                   # 404
```

Watch the object operations while you do any of the above:

```bash
docker compose logs -f s3
```

## Tear down

```bash
docker compose down
```

## Layout

- `docker-compose.yaml` — wires the local S3 server to the `caddy-s3` image
- `Caddyfile` — the module layout the production chart uses, minus TLS
- `s3/` — a stdlib-only Go server that serves `fixtures/` as a read-only
  bucket. It answers GET, HEAD, and a `NoSuchKey` 404, which is every
  operation the Caddy modules issue
- `fixtures/demo.test.camp/` — the bucket contents: two deploys under
  `deploys/`, plus the `production` and `preview` alias files

## Production parity

| Concern           | Demo                      | Prod                                 |
| ----------------- | ------------------------- | ------------------------------------ |
| Object storage    | Local Go server over disk | Cloudflare R2                        |
| Alias write       | Edit the alias file       | artemis PutObject                    |
| Caddy credentials | `demo`/`demo` (unchecked) | org-scoped RO key from infra-secrets |
| Alias cache TTL   | 2 s                       | 15 s                                 |
| Root domain       | `test.camp`               | `freecode.camp`                      |
| Front-door TLS    | off                       | Cloudflare CDN in front              |

The demo server does not check the request signature. Everything else in the
request path is the production code.
