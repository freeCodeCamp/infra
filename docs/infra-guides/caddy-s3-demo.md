# r2_alias demo

Self-contained demo of the `caddy.fs.r2` + `r2_alias` stack that powers `gxy-cassiopeia`. No cluster, no Cloudflare, no Go toolchain — just Docker.

## What it proves

1. Caddy reads an alias file from an S3-compatible bucket, rewrites the request path to the pinned deploy ID, and streams the object body back.
1. Flipping the alias is a single `PutObject` — the same mechanic the artemis deploy proxy uses for atomic promote / rollback in production.
1. Preview subdomains (`{site}--preview.test.camp`) route to a separate alias file while sharing the same deploy storage.

## Stand up

```bash
cd docker/images/caddy-s3/demo
docker compose up --build
```

Wait for `caddy-1 | ... server running`, then from another terminal:

```bash
curl -H 'Host: demo.test.camp' http://localhost:8080/
```

You should see the **v1** page.

## Flip the alias (atomic promote)

```bash
docker compose run --rm seed -alias v2
```

After the 2 s cache TTL expires:

```bash
curl -H 'Host: demo.test.camp' http://localhost:8080/
```

Now shows the **v2** page. Flip back with `-alias v1`.

## Other scenarios

- Missing site (nothing in the bucket for this host):

  ```bash
  curl -i -H 'Host: ghost.test.camp' http://localhost:8080/
  ```

  → `404`

- Preview routing — set a preview alias and request the preview host:

  ```bash
  docker compose run --rm seed -alias v2   # make sure v2 is the active alias
  # (preview uses the same deploy storage; this demo does not set a separate
  # preview alias, so the preview host returns 404 unless you extend seed to
  # write demo.test.camp/preview)
  ```

## Tear down

```bash
docker compose down -v
```

## Layout

- `docker-compose.yaml` — wires S3Mock + seed + the `caddy-s3` image
- `Caddyfile` — the same module layout the production chart uses, minus TLS
- `fixtures/v1,v2/index.html` — two deploys that the seeder uploads
- `seed/` — tiny Go binary that uses AWS SDK v2 (same SDK as the Caddy module) to seed the bucket and flip the alias

## Production parity

| Concern           | Demo                      | Prod                                 |
| ----------------- | ------------------------- | ------------------------------------ |
| Object storage    | Adobe S3Mock container    | Cloudflare R2                        |
| Alias write       | seed container PutObject  | artemis PutObject                    |
| Caddy credentials | `demo`/`demo` (any value) | org-scoped RO key from infra-secrets |
| Alias cache TTL   | 2 s                       | 15 s                                 |
| Root domain       | `test.camp`               | `freecode.camp`                      |
| Front-door TLS    | off                       | Cloudflare CDN in front              |
