# Postgres client + awscli baked in for the windmill backup CronJob.
# Eliminates the runtime `apt-get install awscli` foot-gun (apt mirror
# outage = silent backup miss).
#
# Pin postgres:18-bookworm by tag here; GHA build tags by commit SHA so
# the deploy-side pin can carry the immutable digest.
FROM postgres:18-bookworm

# awscli arrives via debian apt — we deliberately do NOT use pip to
# avoid a Python runtime on top of the postgres client image. Pin no
# version; bookworm ships a known-good (v1.x) line, and CVE patches
# flow through base-image rebuilds.
RUN apt-get update \
    && apt-get install -y --no-install-recommends awscli ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && aws --version

# Backup CronJob calls /bin/bash + pg_dumpall + aws s3 cp; no entrypoint
# override needed. Keep the upstream postgres ENTRYPOINT/CMD shape so
# `kubectl exec` against this image still drops you into psql tooling.
