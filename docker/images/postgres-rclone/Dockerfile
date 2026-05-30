# postgres-rclone image — multi-stage slim build for the windmill
# backup CronJob. Pairs the upstream rclone binary (sourced verbatim
# from rclone's own official image) with a minimal Debian Bookworm
# rootfs carrying just `postgresql-client-18` from PGDG.
#
# Why this shape:
#  - Image is run-once-and-die inside a CronJob — never interactive.
#    We need pg_dumpall + rclone + bash. Nothing else.
#  - postgres-client-18 matches the live windmill-postgresql server
#    (postgres:18 — verified by kubectl probe). Dump-then-restore
#    round-trip is the actual DR contract; client/server version
#    skew breaks that contract silently.
#  - rclone binary comes from `rclone/rclone:1.74.1` via COPY so we
#    inherit upstream's release engineering (signed builds, no `curl
#    + unzip` in our final image, no apt cache layer for build-only
#    tools).
#  - debian:bookworm-slim base is ~30 MB; final image ~150-200 MB
#    vs ~500 MB for the prior postgres:18-bookworm monolith we
#    abandoned.
#
# Chart contract (k3s/gxy-management/apps/windmill/manifests/base/
# backup-cronjob.yaml): pod runs UID 999, GID 999, non-root,
# readOnlyRootFilesystem, drop:[ALL] caps, seccomp RuntimeDefault.
# This image creates a service-only `backup` user at UID 999 to
# match the chart's runAsUser.

FROM rclone/rclone:1.74.2 AS rclone-bin

FROM debian:bookworm-slim

# Bash + pipefail so the curl|gpg pipe in the next RUN fails closed
# if curl returns a non-2xx (otherwise gpg gets empty stdin and a
# corrupt apt key lands on disk silently). Debian default shell is
# dash; switching to bash is also needed for the `set -o pipefail`
# below.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# PGDG apt repo: bookworm stock apt tops out at PG 15; windmill
# server is PG 18 so we need PGDG to pick up postgresql-client-18.
# apt-key(8) is deprecated — use /etc/apt/keyrings + signed-by per
# Debian wiki. curl + gnupg are build-only and purged at end of
# the RUN. ca-certificates stays — rclone TLS handshake needs it.
# hadolint ignore=DL3008
RUN set -eux \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg \
 && install -d /etc/apt/keyrings \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /etc/apt/keyrings/pgdg.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends postgresql-client-18 \
 && pg_dumpall --version \
 && apt-get purge -y --auto-remove curl gnupg \
 && rm -rf /var/lib/apt/lists/*

# rclone binary copied verbatim from upstream image. Smoke-check
# the binary actually runs under the slim rootfs (no missing
# runtime deps — rclone is statically linked Go).
COPY --from=rclone-bin /usr/local/bin/rclone /usr/local/bin/rclone
RUN rclone --version

# Service-only user matching the chart's runAsUser:999. Name
# `pgback` to dodge Debian's pre-defined `backup` system group at
# GID 34. `-M` skips /home creation (read-only rootfs anyway),
# `nologin` because no interactive session ever happens on this
# pod.
RUN groupadd -g 999 pgback \
 && useradd -u 999 -g 999 -M -s /usr/sbin/nologin pgback

USER pgback
