# veritas-staging

Staging deployment of [veritas](../veritas/) on `gxy-cassiopeia`. Shares the same chart via a directory symlink — no fork, no copy-paste drift.

## Layout

```
apps/veritas-staging/
├── charts/
│   └── veritas-staging -> ../../veritas/charts/veritas   # symlink
├── values.production.yaml                        # staging overlay
└── README.md
```

The `charts/veritas-staging` symlink is followed by `just release` (`find -L`). Any chart change in `apps/veritas/charts/veritas/` flows to both prod and staging on next release.

## Differences from prod

| dimension      | prod (`veritas`)                                      | staging (`veritas-staging`)                                                        |
| -------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------- |
| namespace      | `veritas`                                             | `veritas-staging`                                                                  |
| zone           | `freecodecamp.org`                                    | `freecodecamp.dev`                                                                 |
| hostnames      | `login` / `account` / `auth-console.freecodecamp.org` | `login` / `account` / `auth-console.freecodecamp.dev`                              |
| replicas       | 3                                                     | 1                                                                                  |
| image pin      | `sha-<fullsha>` + sha256 digest                       | `:main` (moving, operator-pushed)                                                  |
| CNPG instances | 2 (primary + sync replica)                            | 1 (no HA)                                                                          |
| CNPG storage   | 10Gi                                                  | 5Gi                                                                                |
| backup         | Barman → R2 + ScheduledBackup nightly                 | disabled                                                                           |
| OAuth apps     | prod Google / GitHub App / Apple                      | staging Google / GitHub App / Apple                                                |
| log level      | `info`                                                | `debug`                                                                            |
| relying party  | none day-0                                            | `test.freecode.camp` (temp constellation): `TRUSTED_ORIGINS` + `relyingPartyFQDNs` |

## Sops overlay

`veritas-staging.values.yaml.enc` holds `secretEnv.{BETTER_AUTH_SECRET, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, INTERNAL_API_TOKEN, SMTP_USER, SMTP_PASS}` + `tls.{crt,key}`. The GitHub and Apple pairs (`GITHUB_CLIENT_ID`/`SECRET`, `APPLE_CLIENT_ID`/`SECRET`, optional `APPLE_APP_BUNDLE_IDENTIFIER`) are live per ADR-004 2026-07-29 and optional — a provider mounts only when both keys are present. `SENTRY_DSN` optional. No `cnpgR2` keys — staging backup is disabled.

## Deploy

```
just release gxy-cassiopeia veritas-staging
```

Layers: chart defaults → `values.production.yaml` (this dir) → sops envelope.
