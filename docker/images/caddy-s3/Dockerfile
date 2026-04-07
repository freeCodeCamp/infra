FROM caddy:2-builder AS builder

ENV GOTOOLCHAIN=auto
RUN xcaddy build \
    --with github.com/sagikazarmark/caddy-fs-s3

FROM caddy:2-alpine

LABEL org.opencontainers.image.source=https://github.com/freeCodeCamp-Universe/infra
LABEL org.opencontainers.image.description="Caddy with S3 filesystem module for static constellation hosting"
LABEL org.opencontainers.image.licenses=Apache-2.0

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
