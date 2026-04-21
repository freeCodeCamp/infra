# Flight Manuals — Index

Per-cluster doomsday rebuild manuals. One file per galaxy. Rebuild ordering,
cross-cluster notes, and lifecycle pins live in this index; galaxy-specific
phases live in each manual.

Doc conventions: see [GUIDELINES.md](../GUIDELINES.md) §Flight-manual format.

## Galaxies

| Galaxy         | File                                   | Role                                                               | State          | Provider (now → future)   |
| -------------- | -------------------------------------- | ------------------------------------------------------------------ | -------------- | ------------------------- |
| gxy-management | [gxy-management.md](gxy-management.md) | Control plane (ArgoCD + Windmill + Zot + Atlantis)                 | Live           | DO FRA1                   |
| gxy-launchbase | [gxy-launchbase.md](gxy-launchbase.md) | Supply chain (Woodpecker + CNPG preview DBs)                       | Live           | DO FRA1 → Hetzner post-M5 |
| gxy-cassiopeia | [gxy-cassiopeia.md](gxy-cassiopeia.md) | Static hosting (Caddy + R2)                                        | Live           | DO FRA1 → Hetzner post-M5 |
| gxy-static     | [gxy-static.md](gxy-static.md)         | **Legacy** — retires at cassiopeia cutover                         | Live, retiring | DO FRA1                   |
| gxy-backoffice | [gxy-backoffice.md](gxy-backoffice.md) | Backoffice + observability (VM + ClickHouse + HyperDX + GlitchTip) | Planned        | TBD → Hetzner             |
| gxy-triangulum | [gxy-triangulum.md](gxy-triangulum.md) | Dynamic hosting ("Heroku-like" containers)                         | Future         | Hetzner BM                |

## Rebuild order (full platform from zero)

Strict dependency chain. Do not skip ahead.

1. **gxy-management** first — all other galaxies register to ArgoCD, pull
   images from Zot, trigger Windmill flows.
2. **gxy-launchbase** second — CI builds need somewhere to run before any
   other galaxy can receive custom images.
3. **gxy-cassiopeia** third — static serving for freecode.camp + first-party
   constellations.
4. **gxy-backoffice** fourth (planned) — observability lands once there's
   sustained platform traffic worth observing.
5. **gxy-triangulum** fifth (future) — dynamic workloads, prod DBs, Ceph.

Retire `gxy-static` only after cassiopeia cutover validates.

## Common pre-flight (every galaxy)

```
cd ~/DEV/fCC/infra
just ansible-install
just secret-verify-all
```

- All secrets decrypt OK
- age key on local machine (`~/.config/sops/age/keys.txt`)
- Platform-wide secrets in `infra-secrets/global/` (direnv tokens +
  per-zone CF Origin wildcards at `global/tls/<zone>.{crt,key}.enc`)
- Per-cluster secrets in `infra-secrets/k3s/<galaxy>/` (see each manual)
- Per-cluster TLS zone marker at `infra/k3s/<galaxy>/cluster.tls.zone`
  selects which `global/tls/<zone>.*.enc` pair the deploy recipe uses
  when no per-app TLS override is present. See
  [`docs/architecture/rfc-secrets-layout.md`](../architecture/rfc-secrets-layout.md).

## Post-M5 Hetzner migration

`gxy-launchbase` and `gxy-cassiopeia` both run on DO FRA1 today (per ADR-003
for Woodpecker/CNPG and ADR-007 D32 for static v2). Both galaxies migrate to
Hetzner post-M5 — tracked as `gxy-static-k7d.30` (**deferred**).

**Constraint:** the Talos / k0s distro evaluation must close before any
Hetzner provisioning begins. Do not open a Hetzner project, cut DNS, or
rebuild state on Hetzner until `gxy-static-k7d.30` lands. A premature
migration locks the distro choice and strands any etcd state on the source
cluster.

When the evaluation closes, a dedicated migration runbook lands in
`../runbooks/` and gets linked from this section.

## Known issues (cross-cluster)

| Issue                          | Workaround                               | See                         |
| ------------------------------ | ---------------------------------------- | --------------------------- |
| Pod→nodeVPCIP broken           | `hostNetwork: true` for monitoring       | Field notes Failure 8b      |
| Cilium picks up tailscale0 MTU | Pin `devices: [eth0, eth1]`, `mtu: 1500` | Field notes Failure 8a      |
| DO native routing blocked      | Use VXLAN tunnel (DO anti-spoofing)      | Field notes Cilium pitfalls |

**Resolved:** `kubeProxyReplacement: true` works on k3s HA when devices/MTU
are pinned. Failure 7 was a misdiagnosis (root cause: MTU pollution). See
field notes.

## Lifecycle calendar (cross-cluster pins)

Third-party pins with known end-of-life windows. Rolling these forward is an
explicit task in the backlog — not something that happens automatically.

| Component     | Current pin               | EOL / stale-after        | Action window    | Notes                                                                 |
| ------------- | ------------------------- | ------------------------ | ---------------- | --------------------------------------------------------------------- |
| k3s           | `v1.34.5+k3s1`            | 2026-10-27               | by Sept 2026     | All galaxies. Plan 1.35 upgrade. Test on gxy-management first.        |
| Caddy         | `v2.11.2`                 | CVE-driven               | 14 days per D30  | Bump via PR with regression tests. Tracked by Windmill reminder.      |
| Woodpecker    | `v3.13.0`                 | Community-driven         | On minor release | gxy-launchbase. CLI client isolated for quick swap if project stalls. |
| CloudNativePG | chart `0.28` / `1.29` op  | 1.28 EOL 2026-06-30      | During `1.29.x`  | gxy-launchbase. Rolling in place via operator-guided pg_upgrade.      |
| Cilium        | chart default (1.19 line) | 3-minor community window | On minor bump    | All galaxies. Bump behind feature-gate tests.                         |

When a pin crosses its action window, create a beads task in the relevant
epic and announce in the platform-team channel.

## Shared infrastructure (not cluster-scoped)

- **Cloudflare zones:** `freecodecamp.net`, `freecode.camp`
- **CF Origin Certificate:** `*.freecodecamp.net` (reused across all galaxies)
- **DO VPC:** `universe-vpc-fra1` (CIDR `10.110.0.0/20`)
- **DO Cloud Firewall:** `gxy-fw-fra1` (attached to every galaxy tag)
- **DO Spaces bucket:** `net-freecodecamp-universe-backups` (etcd +
  Windmill + CNPG backups)
- **Cloudflare R2 bucket:** `universe-static-apps-01` (cassiopeia static)
- **Secrets repo:** `infra-secrets` (sibling, sops+age)
- **Admin plane:** Tailscale for SSH + kubectl
