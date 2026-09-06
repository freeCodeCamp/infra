# shellcheck shell=bash
# The migration hook Job (templates/job-migrate.yaml) waits for the CNPG
# primary in an initContainer (~8 min ceiling); Helm's default 5m hook
# timeout would cut that wait short on a first install.
# shellcheck disable=SC2034 # consumed by `source` in infra/justfile `release` recipe.
EXTRA_HELM_ARGS="--timeout 10m"
