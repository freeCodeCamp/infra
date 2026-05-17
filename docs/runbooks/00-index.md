# Runbooks — Index

Single-purpose ops runbooks for the freeCodeCamp Universe platform. Numeric prefix orders by reader path: staff → operator → foundation → demoted-stack. Each file owns one operational concern; larger end-to-end procedures compose from these.

## Active runbooks

| #   | File                                                                       | Audience  | Trigger                                    |
| --- | -------------------------------------------------------------------------- | --------- | ------------------------------------------ |
| 01  | [01-deploy-new-constellation-site.md](01-deploy-new-constellation-site.md) | Staff dev | Ship a new `<site>.freecode.camp`          |
| 02  | [02-deploy-artemis-service.md](02-deploy-artemis-service.md)               | Operator  | Bring up / upgrade the artemis svc         |
| 03  | [03-artemis-postdeploy-check.md](03-artemis-postdeploy-check.md)           | Operator  | E2E gate after any artemis chart change    |
| 04  | [04-secrets-decrypt.md](04-secrets-decrypt.md)                             | Operator  | Inspect / source a sops envelope           |
| 05  | [05-r2-keys-rotation.md](05-r2-keys-rotation.md)                           | Operator  | Rotate artemis-admin or caddy-ro R2 key    |
| 06  | [06-windmill-pg-backup.md](06-windmill-pg-backup.md)                       | Operator  | Verify, take, or restore windmill PG       |
| 07  | [07-artemis-registry-restore.md](07-artemis-registry-restore.md)           | Operator  | Rebuild artemis registry after Valkey wipe |

## Reading order by scenario

**New staff dev — ship a site:** 01 only.

**New operator — onboard the platform:** 02 → 03 → 04 → 05.

**Rotate an R2 key:** 05 (links to 04 + 03 internally).

**Recover windmill PG state:** 06 (links to 04 internally; calls `just inspect-windmill-backup`, `test-windmill-backup-restore`, `backup-windmill`).

**Recover artemis registry (Valkey wipe):** 07 (RDB-restore path or universe-cli replay against R2-derived site list; links to 02 + 04 internally).

## Block ordering rationale

| Block | Files | Why grouped                                       |
| ----- | ----- | ------------------------------------------------- |
| 01    | 01    | Staff-facing primary — most reads                 |
| 02–03 | 02–03 | Artemis lifecycle (deploy + verify)               |
| 04–05 | 04–05 | Foundations consumed by 02/03 (secrets + R2 keys) |
| 06    | 06    | Backup / DR for windmill PG (calls 04 internally) |
| 07    | 07    | Backup / DR for artemis registry (calls 02 + 04)  |

Two-digit prefix gives 99 slots. Promote to three-digit if count grows past 99.

Slots `08`, `09` reserved for future runbooks. Woodpecker runbooks formerly at `07–09` are archived under [`archive/2026-05-10/`](archive/2026-05-10/) (Woodpecker CI retired 2026-05-03); slot `07` was reclaimed for the artemis registry restore runbook.

## Cross-doc references

- [`../flight-manuals/00-index.md`](../flight-manuals/00-index.md) — per-cluster rebuild manuals
- [`../architecture/`](../architecture/) — RFCs and design docs
