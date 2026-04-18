# Pin both stages to Caddy 2.11 — current CVE-patched stable (§5.28 D30).
# Bumping is a PR with a CVE/changelog read + T04 integration re-run.
FROM caddy:2.11-builder AS builder

ENV GOTOOLCHAIN=auto

# Copy the in-tree r2alias module. Per RFC D32 (§5.30), this single Go
# package registers BOTH http.handlers.r2_alias (alias resolver +
# path rewrite) and caddy.fs.r2 (R2 filesystem backend). No third-party
# Caddy plugins — the 2026-04-18 audit dropped sagikazarmark/caddy-fs-s3
# after 14-month upstream silence.
COPY modules/r2alias /src/modules/r2alias

RUN xcaddy build v2.11.2 \
    --with github.com/freeCodeCamp-Universe/infra/docker/images/caddy-s3/modules/r2alias=/src/modules/r2alias

FROM caddy:2.11-alpine

LABEL org.opencontainers.image.source=https://github.com/freeCodeCamp-Universe/infra
LABEL org.opencontainers.image.description="Caddy with in-tree r2alias module (alias resolver + R2 filesystem) for Universe static constellations"
LABEL org.opencontainers.image.licenses=Apache-2.0

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
