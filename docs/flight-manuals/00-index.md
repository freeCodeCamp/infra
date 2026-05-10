# Flight Manuals — Index

Per-cluster doomsday-rebuild manuals for the Universe Platform. Read
order, galaxy state, and cross-cluster gotchas live here; everything
else lives in `UNIVERSE.md` (shared phases) or in the per-galaxy
chapter.

## Read order (rebuilds)

1. **Always start with [`UNIVERSE.md`](UNIVERSE.md)** — §0 prereqs,
   §1 DNS, §2 secrets, §3 shared infra, §4 lifecycle calendar.
   Per-galaxy chapters assume these ran.
2. **gxy-management first** — control plane (Windmill + artemis +
   Valkey). Every other galaxy reads bytes that originate here.
3. **gxy-launchbase** — standby (CNPG operator only post-woodpecker
   retire); brings the database operator before any preview-DB
   constellation lands.
4. **gxy-cassiopeia** — static-apps serve plane. Reads R2 written by
   artemis on gxy-management.
5. **`UNIVERSE.md §99`** — cross-galaxy smoke. Run only after all
   three chapters complete twice idempotently.

## Galaxies (current state)

| Galaxy           | File                                   | Role                                        | State       | Provider (now → future)            |
| ---------------- | -------------------------------------- | ------------------------------------------- | ----------- | ---------------------------------- |
| `gxy-management` | [gxy-management.md](gxy-management.md) | Control plane — Windmill + artemis + Valkey | Live        | DO FRA1                            |
| `gxy-launchbase` | [gxy-launchbase.md](gxy-launchbase.md) | Standby — CNPG operator (workload-free)     | Live (idle) | DO FRA1 → Hetzner post-M5 (parked) |
| `gxy-cassiopeia` | [gxy-cassiopeia.md](gxy-cassiopeia.md) | Static-apps serve plane — Caddy + R2        | Live        | DO FRA1 → Hetzner post-M5 (parked) |

Parked-but-future galaxies (`gxy-backoffice`, `gxy-triangulum`) are
**not** in this manual. When they're provisioned, add a chapter then.
Active state for those galaxies lives in
`Universe/spike/spike-plan.md` and `docs/architecture/adr-drift-2026-05-10.md`.

Retired galaxies:

| Galaxy       | Retired    | What replaced it                                              |
| ------------ | ---------- | ------------------------------------------------------------- |
| `gxy-static` | 2026-04-27 | gxy-cassiopeia (in-tree `caddy.fs.r2` module per ADR-007 D32) |

## Cross-cluster known-issues (quick reference)

Operational gotchas that bite once per rebuild — full notes link out.

| Issue                          | Workaround                                                      | See                                                      |
| ------------------------------ | --------------------------------------------------------------- | -------------------------------------------------------- |
| Pod→nodeVPCIP broken           | `hostNetwork: true` for monitoring                              | ADR-009 §"Tailscale scope" + spike Failure 8b (archived) |
| Cilium picks up tailscale0 MTU | Pin `devices: [eth0, eth1]`, `mtu: 1500` per galaxy values.yaml | ADR-009 §"Cilium" + spike Failure 8a (archived)          |
| DO native routing blocked      | Use VXLAN tunnel (DO anti-spoofing)                             | spike Cilium pitfalls (archived)                         |
| sops `.enc` auto-detect        | Use `--input-type dotenv --output-type dotenv` for `*.env.enc`  | `docs/runbooks/04-secrets-decrypt.md`                    |
| `kubeProxyReplacement: true`   | Works on k3s HA when devices/MTU pinned                         | ADR-009 §"Cilium" 2026-04-06 spike note                  |

## Anchors out (read these before deviating from any step)

| Anchor                                                                                 | Why                                                                      |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `Universe/decisions/00{1..16}-*.md`                                                    | 16 ADRs that govern the platform                                         |
| [`../architecture/adr-drift-2026-05-10.md`](../architecture/adr-drift-2026-05-10.md)   | Audit reconciling each ADR with cluster reality                          |
| [`../architecture/rfc-gxy-cassiopeia-ga.md`](../architecture/rfc-gxy-cassiopeia-ga.md) | GA hardening RFC — Valkey KV decision, artemis trim, ingress/DNS posture |
| [`../architecture/rfc-secrets-layout.md`](../architecture/rfc-secrets-layout.md)       | sops+age envelope contract, two-scope model, sample-twin discipline      |
| `Universe/spike/spike-plan.md`                                                         | Galaxy placement, phase status, post-spike trigger conditions            |

## Operator runbooks (single-purpose)

`docs/runbooks/00-index.md` carries the index; key links:

| Runbook                                                                        | Use when                                                   |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| [`02-deploy-artemis-service.md`](../runbooks/02-deploy-artemis-service.md)     | Deep dive on artemis bring-up; flight-manual §D summarizes |
| [`03-artemis-postdeploy-check.md`](../runbooks/03-artemis-postdeploy-check.md) | Post-deploy smoke for artemis                              |
| [`04-secrets-decrypt.md`](../runbooks/04-secrets-decrypt.md)                   | sops envelope decrypt gotchas                              |
| [`05-r2-keys-rotation.md`](../runbooks/05-r2-keys-rotation.md)                 | R2 read-only / read-write key rotation                     |

## Working-directory rule (HARD)

Repeated from `UNIVERSE.md` because it's the single most-common
footgun:

> Cluster-touching `just` recipes MUST run from `k3s/<galaxy>/`. The
> galaxy `.envrc` loads the right DO token + `KUBECONFIG`. Repo-root
> invocation hits the wrong cluster or fails silently.

Each chapter repeats this above every relevant recipe.
