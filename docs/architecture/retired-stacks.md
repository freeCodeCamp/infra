# Retired stacks

Tracks Universe-platform apps whose chart trees have been weeded from `k3s/<galaxy>/apps/`. Each entry carries the park rationale, ADR anchors, last live commit SHA for archeology, and the resurrection path.

When adding a new entry: drop a row + section. When un-retiring a stack: keep the section as historical record and add a "Reactivated" subsection with the commit reintroducing the chart tree.

| Stack      | Galaxy         | Status             | Retired    | Last live commit | ADR anchors                    |
| ---------- | -------------- | ------------------ | ---------- | ---------------- | ------------------------------ |
| argocd     | gxy-management | parked, never-live | 2026-05-17 | `eb1102ea`       | ADR-005, ADR-017, ADR-018 §P-2 |
| zot        | gxy-management | parked, never-live | 2026-05-17 | `64fe71a2`       | ADR-017, ADR-018 §P-2          |
| woodpecker | gxy-launchbase | retired, was-live  | 2026-05-03 | `ef939b44`       | ADR-018 §P-2                   |

## argocd (gxy-management)

ADR-005 (GitOps Tooling) parks ArgoCD + Kargo + Atlantis. ADR-018 (Early Access Baseline) §Parked-Phase-2 keeps the entire gitops-controller pipeline behind "new CI carrier identified (Woodpecker retired 2026-05-03)". Build-residency rule from ADR-017 also forbids running pillar images through cluster-side OCI infrastructure, so the chicken-and-egg with `zot.management` is closed by design.

Chart, kustomize base (namespace, gateway, httproutes, sample TLS) all present at `eb1102ea`. Never deployed live.

Resurrection: walk `git log eb1102ea -- k3s/gxy-management/apps/argocd/` to recover the tree. ADR-005 needs an explicit reactivation amendment before any redeploy.

## zot (gxy-management)

ADR-017 (Build/Run Residency) explicitly forbids running Universe-platform pillars (artemis, caddy-s3, …) through `zot.management` — chicken-and-egg on cluster wipe is the killer. Pillar images publish to `ghcr.io/freecodecamp/*` and the cluster pulls direct. The Zot OCI registry stays out of the live platform until tenant-scoped consumer apps need an in-cluster mirror; ADR-018 §Parked-Phase-2 keeps that work parked.

Chart, kustomize base (namespace, gateway, httproutes, sample TLS) all present at `64fe71a2`. Never deployed live.

Resurrection: walk `git log 64fe71a2 -- k3s/gxy-management/apps/zot/` to recover the tree. Reactivation requires an ADR-017 amendment reclassifying Zot from "pillar build" to "tenant-image cache".

## woodpecker (gxy-launchbase)

Woodpecker CI was the original Phase-1 carrier for the Universe build pipeline; it was retired in favour of a TBD replacement after multiple operational pains (GitHub OAuth maintenance, agent autoscaling on a small galaxy, CF Access seam). ADR-018 §Parked-Phase-2 keeps the entire supply-chain pipeline (cosign + Grype + Trivy + Syft + Kyverno verifyImages) parked until a new CI carrier is identified. The CNPG operator on gxy-launchbase persists for future workloads; no postgres cluster CR for woodpecker remains in tree.

Chart, kustomize base (namespace, gateway, httproutes, scheduled backup, postgres-cluster CR, sample secrets) all present at `ef939b44`. Helm-uninstalled from cluster 2026-05-11 (verified `dig +short` empty for the two retired DNS records on 2026-05-11). Archived runbooks at `docs/runbooks/archive/2026-05-10/{07,08,09}-woodpecker-*.md` retain operational history.

Resurrection: walk `git log ef939b44 -- k3s/gxy-launchbase/apps/woodpecker/` to recover the tree. Any redeploy needs a fresh ADR amendment selecting Woodpecker (or successor) as the CI carrier — ADR-018 currently parks the slot.
