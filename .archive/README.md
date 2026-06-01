# infra `.archive/`

Tracked infra-local archives. Catalogued in the master Universe federation index, **§3** (federated in-repo — kept here, NOT relocated): `~/DEV/fCC-U/Universe/.archive/INDEX.md`.

## Bundles here

- `2026-03-observability-teardown/` — self-hosted observability stack teardown (2026-03-31). 3 design docs (`teardown-runbook.md`, `nginx-logs-schema.md`, `grafana-nginx-dashboard.md`) + ~44 IaC manifests (ClickHouse / Grafana / Prometheus / Vector kustomize, values, dashboards, schemas, ansible playbooks). **Manifests stay co-located** — infra-specific resurrection artifacts, never cross-repo moved (scanner risk). Observability returns on `gxy-backoffice` per ADR-015.

## Other infra archive surfaces (catalogued in INDEX §3, living elsewhere in the tree)

- `docs/flight-manuals/archive/2026-05-10/` — parked-galaxy flight-manual stubs (`gxy-backoffice`, `gxy-triangulum`); re-author fresh when those galaxies land.
- `docs/runbooks/archive/2026-05-10/` — retired Woodpecker CI runbooks (`07-woodpecker-oauth-app`, `08-woodpecker-cf-access`, `09-woodpecker-bringup-checklist`); Woodpecker retired 2026-05-03.
