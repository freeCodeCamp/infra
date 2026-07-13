# Runbooks — Index

Single-purpose ops runbooks for the freeCodeCamp Universe platform. Numeric prefix orders by reader path: staff → operator → foundation → demoted-stack. Each file owns one operational concern; larger end-to-end procedures compose from these.

## Active runbooks

| #   | File                                                                       | Audience  | Trigger                                            |
| --- | -------------------------------------------------------------------------- | --------- | -------------------------------------------------- |
| 01  | [01-deploy-new-constellation-site.md](01-deploy-new-constellation-site.md) | Staff dev | Ship a new `<site>.freecode.camp`                  |
| 02  | [02-deploy-artemis-service.md](02-deploy-artemis-service.md)               | Operator  | Bring up / upgrade the artemis svc                 |
| 03  | [03-artemis-postdeploy-check.md](03-artemis-postdeploy-check.md)           | Operator  | E2E gate after any artemis chart change            |
| 04  | [04-secrets-decrypt.md](04-secrets-decrypt.md)                             | Operator  | Inspect / source a sops envelope                   |
| 05  | [05-r2-keys-rotation.md](05-r2-keys-rotation.md)                           | Operator  | Rotate artemis-admin or caddy-ro R2 key            |
| 07  | [07-artemis-registry-restore.md](07-artemis-registry-restore.md)           | Operator  | Rebuild artemis registry after Valkey wipe         |
| 08  | [08-artemis-pg-restore-drill.md](08-artemis-pg-restore-drill.md)           | Operator  | Rehearse artemis-PG restore from R2 backup         |
| 09  | [09-hatchet-engine-deploy.md](09-hatchet-engine-deploy.md)                 | Operator  | Stand up / rebuild the Hatchet durable-exec engine |
| 10  | [10-rotate-cf-origin-cert.md](10-rotate-cf-origin-cert.md)                 | Operator  | Rotate the `freecodecamp.net` CF origin cert       |
| 11  | [11-artemis-pg-outage-drill.md](11-artemis-pg-outage-drill.md)             | Operator  | Rehearse R7 — PG outage, serve plane unaffected    |

## Reading order by scenario

**New staff dev — ship a site:** 01 only.

**New operator — onboard the platform:** 02 → 03 → 04 → 05.

**Rotate an R2 key:** 05 (links to 04 + 03 internally).

**Recover artemis registry (Valkey wipe):** 07 (RDB-restore path or universe-cli replay against R2-derived site list; links to 02 + 04 internally).

**Rehearse artemis-PG restore (durable-exec DR):** 08 (pull newest R2 dump, restore into scratch PG, row-count sanity, RPO/RTO statement; links to 02 + 03 + 04 internally).

**Stand up / rebuild the Hatchet engine (durable-exec stage 2):** 09 (wires into 02 §Staged durable-exec bootstrap; operator-only).

**Rotate the CF origin cert:** 10 (links to 04 internally; consolidated single-copy wildcard per `docs/architecture/rfc-secrets-layout.md` D1).

**Rehearse the artemis PG-outage boundary (R7):** 11 (scale bundled PG to 0, assert serve plane + degraded readyz, restore; links to 03 + 08 internally; operator-only, destructive to control plane).

## Block ordering rationale

| Block | Files | Why grouped                                           |
| ----- | ----- | ----------------------------------------------------- |
| 01    | 01    | Staff-facing primary — most reads                     |
| 02–03 | 02–03 | Artemis lifecycle (deploy + verify)                   |
| 04–05 | 04–05 | Foundations consumed by 02/03 (secrets + R2 keys)     |
| 07    | 07    | Backup / DR for artemis registry (calls 02 + 04)      |
| 08    | 08    | Backup / DR for artemis PG (calls 02 + 03 + 04)       |
| 09    | 09    | Durable-exec engine stand-up (Hatchet); wires into 02 |
| 10    | 10    | CF origin-cert rotation; foundation-adjacent to 04/05 |
| 11    | 11    | Artemis PG-outage drill (R7); DR-adjacent to 08       |

Two-digit prefix gives 99 slots. Promote to three-digit if count grows past 99.

Woodpecker runbooks formerly at `07–09` are archived under [`archive/2026-05-10/`](archive/2026-05-10/) (Woodpecker CI retired 2026-05-03); slot `07` was reclaimed for the artemis registry restore runbook, slot `08` for the artemis-PG restore drill, and slot `09` for the Hatchet engine deploy runbook. The windmill PG-backup runbook (formerly `06`) and the windmill decommission runbook (formerly `12`) are archived under [`archive/2026-07-07/`](archive/2026-07-07/) (Windmill retired 2026-07-07); slots `06` and `12` are left vacant.

## Cross-doc references

- [`../flight-manuals/00-index.md`](../flight-manuals/00-index.md) — per-cluster rebuild manuals
- [`../architecture/`](../architecture/) — RFCs and design docs
