# Runbooks — Index

Single-purpose ops runbooks for the freeCodeCamp Universe platform.
Numeric prefix orders by reader path: staff → operator → foundation
→ retirement → demoted-stack. Each file owns one operational concern;
larger end-to-end procedures compose from these.

Doc conventions: see [GUIDELINES.md](../GUIDELINES.md) §Runbook format.

## Active runbooks

| #   | File                                                                       | Audience      | Trigger                                       |
| --- | -------------------------------------------------------------------------- | ------------- | --------------------------------------------- |
| 01  | [01-deploy-new-constellation-site.md](01-deploy-new-constellation-site.md) | Staff dev     | Ship a new `<site>.freecode.camp`             |
| 02  | [02-deploy-artemis-service.md](02-deploy-artemis-service.md)               | Operator      | Bring up / upgrade the artemis svc            |
| 03  | [03-artemis-postdeploy-check.md](03-artemis-postdeploy-check.md)           | Operator      | E2E gate after any artemis chart change       |
| 04  | [04-secrets-decrypt.md](04-secrets-decrypt.md)                             | Operator      | Inspect / source a sops envelope              |
| 05  | [05-r2-keys-rotation.md](05-r2-keys-rotation.md)                           | Operator      | Rotate artemis-admin or caddy-ro R2 key       |
| 06  | [06-dns-cutover.md](06-dns-cutover.md)                                     | Operator      | One-shot — gxy-static → cassiopeia DNS flip   |
| 07  | [07-woodpecker-oauth-app.md](07-woodpecker-oauth-app.md)                   | CI maintainer | Provision Woodpecker GitHub OAuth app         |
| 08  | [08-woodpecker-cf-access.md](08-woodpecker-cf-access.md)                   | CI maintainer | Re-enable CF Access on Woodpecker (preserved) |
| 09  | [09-woodpecker-bringup-checklist.md](09-woodpecker-bringup-checklist.md)   | CI maintainer | Post-deploy verification + secrets reference  |

## Reading order by scenario

**New staff dev — ship a site:** 01 only.

**New operator — onboard the platform:** 02 → 03 → 04 → 05.

**Rotate an R2 key:** 05 (links to 04 + 03 internally).

**Decommission gxy-static:** 06 (then file moves to `archive/` after 30-day soak).

**Stand up Woodpecker fresh:** 07 → 09 → (optional 08 if CF Access re-enabled).

## Block ordering rationale

| Block | Files | Why grouped                                                 |
| ----- | ----- | ----------------------------------------------------------- |
| 01    | 01    | Staff-facing primary — most reads                           |
| 02–03 | 02–03 | Artemis lifecycle (deploy + verify)                         |
| 04–05 | 04–05 | Foundations consumed by 02/03 (secrets + R2 keys)           |
| 06    | 06    | One-shot retirement procedure                               |
| 07–09 | 07–09 | Demoted Woodpecker stack (gxy-launchbase off critical path) |

Two-digit prefix gives 99 slots. Promote to three-digit if count grows
past 99.

## Archive

`archive/` holds runbooks whose triggering condition is gone. Kept for
archaeology; not maintained.

| File                                                                                         | Reason archived                                                                          |
| -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [archive/cluster-rename-mgmt-to-management.md](archive/cluster-rename-mgmt-to-management.md) | Rename complete; CLAUDE.md inventory uses `gxy-management`                               |
| [archive/r2-bucket-provision.md](archive/r2-bucket-provision.md)                             | Bucket `universe-static-apps-01` already provisioned; T11 rw key flow superseded by D016 |

## Cross-doc references

- [`../GUIDELINES.md`](../GUIDELINES.md) — runbook format conventions
- [`../flight-manuals/00-index.md`](../flight-manuals/00-index.md) — per-cluster rebuild manuals
- [`../architecture/`](../architecture/) — RFCs and design docs
- [`../sprints/`](../sprints/) — active sprint state + dispatches
