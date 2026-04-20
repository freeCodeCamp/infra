# Both stages pinned to 2.11.2 — matches the xcaddy build version below.
# Bumping is a PR with a CVE/changelog read + integration re-run.
FROM caddy:2.11.2-builder AS builder

ENV GOTOOLCHAIN=auto

# The in-tree r2alias package registers BOTH http.handlers.r2_alias and
# caddy.fs.r2 — no third-party Caddy plugins in this build.
COPY modules/r2alias /src/modules/r2alias

RUN xcaddy build v2.11.2 \
    --with github.com/freeCodeCamp-Universe/infra/docker/images/caddy-s3/modules/r2alias=/src/modules/r2alias

FROM caddy:2.11.2-alpine

LABEL org.opencontainers.image.source=https://github.com/freeCodeCamp-Universe/infra
LABEL org.opencontainers.image.description="Caddy with in-tree r2alias module (alias resolver + R2 filesystem) for Universe static constellations"
LABEL org.opencontainers.image.licenses=Apache-2.0

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
