# Flight Manual — gxy-triangulum

**Future galaxy.** Dynamic hosting — Heroku-like environment for
containerized applications. Production CNPG DBs. Ceph RGW on bare metal.

Activation trigger: first dynamic constellation ready to ship + bare-metal
evaluation (`gxy-static-k7d.30`) closed. Until then this file stays a
placeholder.

## Planned scope (per ADR-001 + ADR-008)

- Container workloads (staff constellations with Dockerfiles or buildpacks)
- Production Postgres via CNPG (prod tier, vs gxy-launchbase preview tier)
- Production MongoDB via Percona
- Shared Valkey instances
- SQLite + Litestream replica → R2
- Ceph RGW (on-cluster object storage; R2 still serves as offsite backup +
  static sites)

## Planned provisioning

- Provider: Hetzner bare metal
- Sizing: 3-5× dedicated nodes (per ADR-001 Phase 2 table; right-size post-spike)
- Substrate: k3s HA embedded etcd OR Talos/k0s (pending distro evaluation)
- Storage: Rook-Ceph (NVMe pool; HDD pool for cold)
- Supply-chain: Zot pull + Kyverno verifyImages + cosign signatures required
  (ADR-003/005/011 chain activates here)

## Write this manual when

- Hetzner project opened + bare-metal nodes online
- Distro decision made (Talos / k0s / k3s)
- Rook-Ceph baselined

Cross-ref: [00-index.md](00-index.md) for shared infrastructure + Post-M5
Hetzner migration constraints, [../GUIDELINES.md](../GUIDELINES.md) for
flight-manual format.
