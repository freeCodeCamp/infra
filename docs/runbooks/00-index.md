# Runbooks — Index

Single-purpose ops runbooks. Each file owns one operational concern.

## Active runbooks

| #   | File                                                       | Audience | Trigger                                         |
| --- | ---------------------------------------------------------- | -------- | ----------------------------------------------- |
| 04  | [04-secrets-decrypt.md](04-secrets-decrypt.md)             | Operator | Inspect / source a sops envelope                |
| 10  | [10-rotate-cf-origin-cert.md](10-rotate-cf-origin-cert.md) | Operator | Rotate the `freecodecamp.net` CF origin cert    |
| 14  | [14-o11y-node-bringup.md](14-o11y-node-bringup.md)         | Operator | Bring up / grow the ops-o11y mgmt cluster (T58) |

Numbers are not reused. The Universe runbooks (01–03, 05, 07–09, 11–13, 15, 16) moved to [`Architecture/docs/infra/runbooks/`](https://github.com/freeCodeCamp-Universe/Architecture/tree/main/docs/infra/runbooks) at the Universe sunset (October 2026).

## Cross-doc references

- [`../architecture/`](../architecture/) — RFCs and design docs
