# Runbooks — Index

Single-purpose ops runbooks. Each file owns one operational concern.

## Active runbooks

| #   | File                                                                                                                        | Audience | Trigger                                             |
| --- | --------------------------------------------------------------------------------------------------------------------------- | -------- | --------------------------------------------------- |
| 04  | [04-secrets-decrypt.md](04-secrets-decrypt.md)                                                                              | Operator | Inspect / source a sops envelope; envelope layout   |
| 14  | [14-o11y-node-bringup.md](14-o11y-node-bringup.md)                                                                          | Operator | Bring up / grow the ops-o11y cluster (target state) |
| 18  | [18-swarm-manager-rebuild.md](18-swarm-manager-rebuild.md)                                                                  | Operator | Rebuild the Vultr Swarm after a manager loss        |
| 19  | [19-o11y-alerts.md](19-o11y-alerts.md)                                                                                      | Operator | An ops-o11y-vultr alert fires                       |
| 20  | [traffic runbook](https://github.com/freeCodeCamp/terraform-cloudflare/blob/main/cf-origin-records/README.md), private repo | Operator | Move traffic between Linode and Vultr               |
| 21  | [21-o11y-backup-restore.md](21-o11y-backup-restore.md)                                                                      | Operator | Restore o11y data, or a nightly backup fails        |
| 22  | [22-migration-rollback.md](22-migration-rollback.md)                                                                        | Operator | Roll back the move, or deploy during a freeze       |

Archived in [`archive/2026-10-15/`](archive/2026-10-15/):

- Runbook 10 (rotate the `freecodecamp.net` origin cert). No live service uses that certificate, and its steps call the deleted `justfile`.
- Runbook 17 (decommission the i18n Ghost VMs and MySQL). The decommission is complete.

Numbers are not reused from here on. The Universe runbooks (01–03, 05, 07–09, 11–13, 15, 16) moved to [`Architecture/docs/infra/runbooks/`](https://github.com/freeCodeCamp-Universe/Architecture/tree/main/docs/infra/runbooks) at the Universe sunset (October 2026).

## Cross-doc references

- [`../architecture/`](../architecture/) — RFCs and design docs
