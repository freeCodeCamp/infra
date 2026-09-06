# shellcheck shell=bash
# Pin CloudNativePG chart to 0.28.0 — matches gxy-launchbase install
# (helm list cnpg-system on launchbase: cloudnative-pg-0.28.0, deployed 2026-04-20).
# Launchbase itself has no .deploy-flags.sh — relies on install-time helm latest.
# Drift candidate: backfill same file on launchbase in a future hygiene pass.
# shellcheck disable=SC2034 # consumed by `source` in infra/justfile `release` recipe.
EXTRA_HELM_ARGS="--version 0.28.0"
