# Cilium NetworkPolicy — patterns and traps

Operator-runnable reference for writing `CiliumNetworkPolicy` (CNP) manifests on the Universe galaxies. Promotes operational findings that previously lived only in field-notes (now consolidated under `Universe/.archive/infra/`) into canonical guidance.

> **Read first:** [ADR-009 §Cilium](https://github.com/freeCodeCamp-Universe/Architecture/blob/main/decisions/009-networking-domains.md#cni-cilium-without-cluster-mesh) for the CNI choice rationale; [ADR-011 §Within-galaxy CiliumNetworkPolicy](https://github.com/freeCodeCamp-Universe/Architecture/blob/main/decisions/011-security-model.md#within-galaxy-cilium-ciliumnetworkpolicy) for the constellation-isolation posture.

## When to write a CNP at all

Every per-app CNP is opt-in. The default-allow within a galaxy namespace is fine for low-blast-radius constellations. **Do not write a per-app CNP unless one of these is true:**

1. The app holds secret material that a cluster-lateral attacker should not reach (e.g. Valkey holding the registry, future CNPG holding session tokens).
1. The app exposes an admin port that must stay blocked from cluster-lateral traffic (e.g. caddy `:2019` admin API while `:80` is public).
1. The app egresses to specific external FQDNs and a tighter allow-list materially raises the bar against compromised-pod exfiltration (e.g. artemis to R2 + GitHub).

Without one of these, a CNP is friction with no security gain. Future hardening will land at the cluster level via `CiliumClusterwideNetworkPolicy` (CCWNP) — see "Future direction" below.

## The DNS L7 trap

The single most-common pitfall when writing a CNP with `toFQDNs`.

**Cilium's `toFQDNs` selectors are populated only when DNS queries flow through the Cilium DNS proxy.** Engaging the proxy requires an L7 `rules.dns` block on the kube-dns egress rule. Once engaged, the proxy enforces the allow-list on **ALL** queries, including cluster-local (`*.svc.cluster.local`).

If your pod resolves any cluster-local name (cross-namespace service, co-located dependency) and the L7 allow-list does not cover that shape, the lookup returns malformed → Go's `net` resolver surfaces `server misbehaving` (NOT `NXDOMAIN`). The pod typically CrashLoopBackOff's at startup.

### The trap historically

| Date       | Where          | Symptom                                                                                                          | Resolution                                          |
| ---------- | -------------- | ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| 2026-04-07 | gxy-launchbase | Woodpecker forge list: `lookup woodpecker-postgres-rw.woodpecker on 10.16.0.10:53: server misbehaving`.          | Deleted CNP entirely.                               |
| 2026-05-11 | gxy-management | New artemis pod (Valkey cutover): `lookup valkey.valkey.svc.cluster.local on 10.11.0.10:53: server misbehaving`. | Added cluster-local DNS L7 patterns to artemis CNP. |

Both incidents share the same shape: pod adds a cluster-local egress target, existing CNP's L7 DNS rules do not cover that target, queries fail with `server misbehaving`. The 2026-04-07 incident's lesson was captured in field-notes only; not promoted. The 2026-05-11 incident re-discovered it.

### The wildcard semantics gotcha

Cilium `matchPattern` uses `*` → regex `[^.]*` — wildcards do **not** cross dots:

| Pattern                 | Matches                     | Does NOT match                       |
| ----------------------- | --------------------------- | ------------------------------------ |
| `*.example.com`         | `foo.example.com`           | `foo.bar.example.com`                |
| `*.cluster.local`       | `foo.cluster.local`         | `foo.bar.svc.cluster.local`          |
| `*.svc.cluster.local`   | `foo.svc.cluster.local`     | `foo.bar.svc.cluster.local`          |
| `*.*.svc.cluster.local` | `foo.bar.svc.cluster.local` | (this is what k8s service DNS needs) |

Kubernetes service DNS shape is `<svc>.<ns>.svc.cluster.local` — 4 labels. A single-wildcard cluster-local pattern looks plausible but silently fails. Use `*.*.svc.cluster.local` for the wildcard form, or exact `matchName` per target.

## Canonical patterns

### Pattern A — External FQDN egress only (no cluster-local target)

For an app that talks only to external HTTPS services (R2, GitHub, public APIs). Today: `caddy` on gxy-cassiopeia.

```yaml
egress:
  - toEndpoints:
      - matchLabels:
          "k8s:io.kubernetes.pod.namespace": kube-system
          "k8s-app": kube-dns
    toPorts:
      - ports:
          - port: "53"
            protocol: UDP
        rules:
          dns:
            - matchPattern: "*.r2.cloudflarestorage.com"
            # ... add other external FQDN patterns here ...
  - toFQDNs:
      - matchPattern: "*.r2.cloudflarestorage.com"
    toPorts:
      - ports:
          - port: "443"
            protocol: TCP
```

### Pattern B — External FQDN + cluster-local egress

For an app that ALSO needs to reach a cluster-internal service (Valkey, Postgres, future co-located dependency). Today: `artemis` on gxy-management (post-2026-05-11 cutover).

```yaml
egress:
  - toEndpoints:
      - matchLabels:
          "k8s:io.kubernetes.pod.namespace": kube-system
          "k8s-app": kube-dns
    toPorts:
      - ports:
          - port: "53"
            protocol: UDP
        rules:
          dns:
            - matchPattern: "*.r2.cloudflarestorage.com"
            - matchPattern: "api.github.com"
            - matchPattern: "ghcr.io"
            # In-cluster service DNS — required for cluster-local
            # egress targets. Both the exact `matchName` and the
            # wildcard are belt-and-suspenders: matchName documents
            # the specific target, wildcard handles future
            # cross-namespace pillars without re-touching policy.
            - matchName: "<svc>.<ns>.svc.cluster.local"
            - matchPattern: "*.*.svc.cluster.local"
  # ... external toFQDNs ...
  - toEndpoints:
      - matchLabels:
          "k8s:io.kubernetes.pod.namespace": <ns>
          "k8s:app.kubernetes.io/name": <svc>
    toPorts:
      - ports:
          - port: "<port>"
            protocol: TCP
```

**Both halves are required when you add cluster-local egress.** The `toEndpoints` (L3/L4) authorizes the bytes; the `dns.matchPattern` (L7) authorizes the lookup. Either alone leaves the path broken.

### Pattern C — Skip the CNP entirely

For an app where the security gain is small and the operational overhead is real. Field-note recommendation for new apps without existing CNP. gxy-management + gxy-static historically shipped zero per-app CNPs.

Future hardening lands at cluster scope via `CiliumClusterwideNetworkPolicy` (CCWNP) — when that arrives, per-app CNPs become redundant for most constellations.

## Decision rubric

```text
Need L4 ingress restriction (e.g. block lateral access to admin port)?
  ├─ Yes  → write CNP. Use Pattern A or B.
  └─ No  → skip CNP unless one of below.

Need L7 FQDN egress allow-list for compromised-pod exfil hardening?
  ├─ Yes  → write CNP. Use Pattern A.
  └─ No  → skip CNP.

Egresses to cluster-local services?
  └─ Yes (in addition to the above) → MUST upgrade to Pattern B.
                                       Both halves required.

None of the above?
  └─ Skip CNP. Wait for CCWNP global hardening.
```

## Charts in this repo using each pattern

| Chart                                              | Pattern                          | Notes                                                                                                       |
| -------------------------------------------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `k3s/gxy-cassiopeia/apps/caddy/charts/caddy`       | A                                | External: R2 only. Dormant trap if cluster-local egress added — would need Pattern B upgrade.               |
| `k3s/gxy-management/apps/artemis/charts/artemis`   | B                                | External: R2 + GitHub + ghcr. Cluster-local: Valkey. Both halves wired since 2026-05-11.                    |
| `k3s/gxy-management/apps/valkey/charts/valkey`     | (vanilla NetworkPolicy, not CNP) | Ingress-only restriction (artemis namespace pods). No L7 trap — vanilla NP doesn't engage Cilium DNS proxy. |
| `k3s/gxy-management/apps/windmill/charts/windmill` | (none)                           | No CNP. Matches field-note advice for non-secret-holding apps.                                              |

## Future direction (not in scope today)

A `CiliumClusterwideNetworkPolicy` (CCWNP) at cluster scope would provide constellation isolation as a default-deny baseline, on top of which per-app CNPs become exception-only. Until that lands, follow the rubric above and prefer Pattern A / Pattern C over Pattern B unless Pattern B is justified by a cluster-local dependency.

## Cross-refs

- [`docs/infra-guides/cilium-multi-nic.md`](./cilium-multi-nic.md) — sibling guide on multi-NIC MTU + device pinning. Read alongside this one when bringing up a new galaxy.
- ADR-009 §CNI — Cilium choice rationale.
- ADR-011 §Within-galaxy — constellation isolation posture.
- `docs/flight-manuals/gxy-management.md §C.6` — 2026-05-11 cutover smoke transcript including the side-finding write-up.
- `Universe/.archive/infra/2026-04-07-spike-adr-corrections.md` — historical record of the 2026-04-07 woodpecker incident.
- Cilium docs: <https://docs.cilium.io/en/stable/security/policy/language/#dns-policy-and-ip-discovery>
