# TODO Park — Deferred Items

Items deferred from the Universe static-apps MVP (sprint 2026-04-21). Each
entry lists activation trigger, owner, and linked ADR / decision.

Not a backlog — a graveyard of "not now, but when _X_". Revisit during
sprint planning when an activation trigger fires.

## Supply chain + image security

### Zot push + image registry as source of truth

- **Activation trigger:** first containerized constellation lands on
  `gxy-triangulum`. Until then, no images are built for this platform.
- **Owner:** infra team.
- **Ref:** ADR-003 (platform controller chain), ADR-005 (image registry),
  ADR-011 §Image provenance.

### cosign keyless signing (Sigstore)

- **Activation trigger:** same as Zot push. Signs the first image built by
  Woodpecker before Zot push.
- **Owner:** infra team.
- **Ref:** ADR-003 §Hardened CI pipeline, ADR-011 §Supply Chain Security.

### Grype + Trivy dual vulnerability scan

- **Activation trigger:** same as Zot push. Adds scan step between build
  and push.
- **Owner:** infra team.
- **Ref:** ADR-011 §Non-negotiable guardrails.

### Kyverno `verifyImages` admission policy

- **Activation trigger:** same as Zot push. Deploys Kyverno to every galaxy
  running containerized workloads (gxy-triangulum first).
- **Owner:** infra team.
- **Ref:** ADR-011 §Image provenance.

### Syft SBOM generation + OCI attestation

- **Activation trigger:** same as Zot push.
- **Owner:** infra team.
- **Ref:** ADR-003 §Hardened CI pipeline.

## Automation

### Atlantis for OpenTofu PR automation

- **Activation trigger:** first IaC PR pain point — when manual
  `tofu plan` / `tofu apply` cycles block delivery. Likely after 3–5 active
  OpenTofu workspaces.
- **Owner:** infra team. Lands on `gxy-management`.
- **Ref:** ADR-001 §Component placement, ADR-002 §IaC Tooling.

## Auth + identity

### BetterAuth + Account Service

- **Activation trigger:** first 10 constellations live. Per spike defers.
- **Owner:** Universe team (builds Account Service).
- **Ref:** ADR-004 §Auth and Identity, ADR-006 §Email Delivery (auth emails
  via SES from BetterAuth).

## Galaxies

### gxy-triangulum provisioning

- **Activation trigger:** first dynamic constellation ready to ship + bare
  metal evaluation (`gxy-static-k7d.30`) closed.
- **Owner:** infra team.
- **Ref:** ADR-001 §Galaxy Topology (production galaxy, Hetzner BM).
- **Placeholder manual:** `docs/flight-manuals/gxy-triangulum.md`.

### gxy-backoffice provisioning + observability stack

- **Activation trigger:** static-apps MVP shipped + staff team onboarded.
  Second wave of platform maturity.
- **Owner:** infra team.
- **Ref:** ADR-001 §Component placement, ADR-015 §Observability (phased
  adoption: VM → ClickHouse+Vector → HyperDX → GlitchTip).
- **Placeholder manual:** `docs/flight-manuals/gxy-backoffice.md`.

## Migration

### Hetzner bare metal migration (launchbase + cassiopeia + backoffice)

- **Activation trigger:** Talos / k0s distro evaluation closes
  (`gxy-static-k7d.30`). Per D13 revised 2026-04-17, post-M5.
- **Owner:** infra team. Rebuild cluster on Hetzner, migrate state, cut
  DNS.
- **Ref:** ADR-001 §Hosting roadmap, ADR-013 §Cost Model.
- **Constraint:** do NOT open a Hetzner project or cut DNS until the distro
  evaluation lands. Early migration locks distro choice + strands etcd
  state on source cluster.

## Storage + data

### Rook-Ceph on bare metal

- **Activation trigger:** gxy-triangulum provisioned on Hetzner. Ceph
  serves production DB volumes + RGW object storage.
- **Owner:** infra team.
- **Ref:** ADR-008 §Storage Platform.

### CNPG barman-cloud plugin

- **Activation trigger:** first production DB lands on gxy-triangulum. Until
  then gxy-launchbase runs preview tier DBs where base-backup-only is fine.
- **Owner:** infra team.
- **Ref:** ADR-008 §Databases, CNPG release notes
  (native `barmanObjectStore` deprecated ≥ 1.26).

### ArgoCD multi-cluster wiring

- **Activation trigger:** gxy-launchbase or gxy-cassiopeia needs GitOps
  sync for app manifests managed centrally. Currently single-cluster on
  gxy-management is sufficient.
- **Owner:** infra team.
- **Ref:** ADR-001 §Component placement (ArgoCD multi-cluster on mgmt).

## Reliability

### DR runbook with tested RTO / RPO targets

- **Activation trigger:** post-M1 (after first constellation in production).
  Need measurable failure scenarios + operator rehearsal.
- **Owner:** infra team.
- **Ref:** ADR-012 §Disaster Recovery and Backups (currently Proposed /
  TBD).

## Legacy

### `ops-mgmt` teardown (legacy fCC)

- **Activation trigger:** post-Universe launch + confirmed no legacy
  dependencies remain.
- **Owner:** infra team.
- **Ref:** `fCC/infra/CLAUDE.md` §Clusters (Legacy section).

### `ops-backoffice-tools` teardown (legacy fCC)

- **Activation trigger:** same as `ops-mgmt`.
- **Owner:** infra team.
- **Ref:** `fCC/infra/CLAUDE.md` §Clusters (Legacy section).

## Reactivation workflow

When a trigger fires:

1. Remove the entry from this file.
2. Add a new epic / task in beads with the trigger summary as the spec
   rationale.
3. Amend the related ADR with a dated resolution note if applicable (see
   `GUIDELINES.md` §ADR lifecycle).
4. Link the new work back to this archive via the commit that removes the
   entry — `git log --follow docs/TODO-park.md` is the audit trail.

Do not let entries rot silently. Monthly trim reviews this file for
entries whose triggers may have fired without anyone noticing.
