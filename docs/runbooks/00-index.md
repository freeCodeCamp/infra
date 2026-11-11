# Runbooks — Index

Single-purpose ops runbooks. Each file owns one operational concern.

## Active runbooks

| #   | File                                                                                                                        | Audience | Trigger                                           |
| --- | --------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------- |
| 04  | [04-secrets-decrypt.md](04-secrets-decrypt.md)                                                                              | Operator | Inspect / source a sops envelope; envelope layout |
| 18  | [18-swarm-manager-rebuild.md](18-swarm-manager-rebuild.md)                                                                  | Operator | Rebuild the Vultr Swarm after a manager loss      |
| 19  | [19-o11y-alerts.md](19-o11y-alerts.md)                                                                                      | Operator | An ops-o11y-vultr alert fires                     |
| 20  | [traffic runbook](https://github.com/freeCodeCamp/terraform-cloudflare/blob/main/cf-origin-records/README.md), private repo | Operator | A Vultr NGINX VM must get no traffic              |
| 21  | [21-o11y-backup-restore.md](21-o11y-backup-restore.md)                                                                      | Operator | Restore o11y data, or a nightly backup fails      |

Archived in [`archive/2026-11-11/`](archive/2026-11-11/):

- Runbook 22 (roll back the Vultr move, or deploy to both fleets). Linode is shut down.

Runbooks 10 and 17 were deleted in November 2026. Numbers are not reused from here on. The Universe runbooks (01–03, 05, 07–09, 11–13, 15, 16) moved to [`Architecture/docs/infra/runbooks/`](https://github.com/freeCodeCamp-Universe/Architecture/tree/main/docs/infra/runbooks) at the Universe sunset (October 2026).
