# Postgres client + rclone baked in for the windmill backup CronJob.
# Eliminates runtime `apt-get install` foot-gun (apt mirror outage =
# silent backup miss) and standardises on rclone for every S3-API
# upload path across Universe (R2-only target; aws CLI removed).
#
# Base pin: postgres:18-bookworm @ sha256 captured 2026-05-18. CVE
# patches flow via base-image rebuilds — bump the digest when a new
# 18-bookworm rolls. GHA build tags by commit SHA so the deploy-side
# pin can carry an immutable image digest on top.
FROM postgres:18-bookworm@sha256:0b4577caeca90c29e7a9e4de1bff0a6aa90bdaaa1cd229d4f95feec1550fadf7

ARG RCLONE_VERSION=1.74.1

# Install rclone via the upstream static binary — no apt awscli on this
# image. curl + unzip are removed after install so the runtime surface
# is just postgres-client + rclone.
# hadolint ignore=DL3008
RUN set -eux \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && curl -fsSL "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-amd64.zip" -o /tmp/rclone.zip \
 && unzip -j /tmp/rclone.zip "rclone-v${RCLONE_VERSION}-linux-amd64/rclone" -d /usr/local/bin/ \
 && chmod +x /usr/local/bin/rclone \
 && rclone --version \
 && rm -f /tmp/rclone.zip \
 && apt-get purge -y --auto-remove curl unzip \
 && rm -rf /var/lib/apt/lists/*

# Backup CronJob calls /bin/bash + pg_dumpall + rclone; no entrypoint
# override needed. Keep upstream postgres ENTRYPOINT/CMD shape so
# `kubectl exec` against this image still drops you into psql tooling.
USER postgres
