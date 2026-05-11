# Traefik on k3s with hostNetwork — pitfalls and patterns

Operator-runnable reference for the Traefik DaemonSet that every
Universe galaxy uses for `:80`/`:443` ingress. Promotes operational
findings from the archived field-notes
(`Universe/spike/field-notes/archive/2026-05-10/infra.md`) into
canonical guidance — the WHY behind values that already live in
chart code.

> **Read first:** [ADR-009 §Ingress](https://github.com/freeCodeCamp-Universe/Universe/blob/main/decisions/009-networking-domains.md)
> for the Traefik-DaemonSet-over-cloud-LB rationale.

## Why hostNetwork?

ADR-009 chose Traefik DaemonSet on host network ports `:80`/`:443`
over a cloud LoadBalancer. The trade-off: no DO LB cost (~$12/mo per
galaxy), DNS round-robin via Cloudflare. Cost: every Traefik gotcha
below.

## Pitfall 1 — `HelmChartConfig` must land BEFORE k3s starts

k3s reads `/var/lib/rancher/k3s/server/manifests/` on startup. If
`traefik-config.yaml` (HelmChartConfig) is copied **after** k3s
starts, Traefik installs with defaults and silently runs with the
wrong config. Restart is not enough — the HelmChartConfig is consumed
on the install pass.

**Pattern.** The bootstrap play copies the Traefik config in Play 2
`pre_tasks`, BEFORE the k3s_server role runs in Play 3.

## Pitfall 2 — `updateStrategy`, not `rollingUpdate`

The Traefik chart renamed the top-level update key. Using the legacy
`rollingUpdate` key is silently ignored; the chart's default
`maxUnavailable: 0` then triggers a render error:

```
maxUnavailable should be greater than 0 when using hostNetwork
```

DaemonSets with `hostNetwork: true` cannot have `maxUnavailable: 0`
(no overlap possible on host ports).

**Pattern.** Set both keys to their non-zero variants — DaemonSet
cannot have both non-zero:

```yaml
deployment:
  kind: DaemonSet
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 0
```

## Pitfall 3 — `runAsUser: 0` required for `:80`/`:443`

containerd does not (yet) ship ambient capabilities ([KEP-2763](https://github.com/kubernetes/enhancements/issues/2763));
`sysctl net.ipv4.ip_unprivileged_port_start` is forbidden when
`hostNetwork: true`. The only way to bind `:80`/`:443` from inside a
Traefik DaemonSet pod today is `runAsUser: 0`.

**Pattern.** Keep capabilities tight despite running as root:

```yaml
podSecurityContext:
  runAsUser: 0
  runAsGroup: 0
  fsGroup: 0

securityContext:
  capabilities:
    drop:
      - ALL
    add:
      - NET_BIND_SERVICE
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
```

Universe galaxies maintain PSS `baseline` (not `restricted`) on
`kube-system` for this reason — `restricted` rejects `runAsUser: 0`.

## Pitfall 4 — Gateway listener port MUST match Traefik entrypoint

When charts use Gateway API (HTTPRoute / Gateway resources) **against
the same Traefik DaemonSet**, the `Gateway.spec.listeners[].port`
must equal Traefik's entrypoint port — i.e. `80` for the `web`
entrypoint, `443` for `websecure`. Mismatch causes silent routing
failure: the Gateway accepts the listener, the HTTPRoute attaches,
no requests reach the backend.

**Pattern.** Mirror Traefik's hostNetwork ports verbatim:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: <app>
spec:
  gatewayClassName: traefik
  listeners:
    - name: web
      port: 80
      protocol: HTTP
      hostname: <app>.<root>
      allowedRoutes:
        namespaces:
          from: Same
```

Adding `:443` requires CF zone in `Full (Strict)`, an origin certificate,
and a chart-owned `Secret` carrying the cert. The
`docs/architecture/adr-drift-2026-05-10.md` row covering this is the
authoritative source on which galaxies are on which SSL mode today.

## Pitfall 5 — Gateway parentRef must point at an in-namespace Gateway

`HTTPRoute.spec.parentRefs` referencing `traefik/kube-system` does
NOT work — k3s' Traefik DaemonSet is an **Ingress provider**, not a
Gateway. The reference goes nowhere; the HTTPRoute is dangling, and
Traefik 404s every request.

**Pattern.** Each chart owns its own `Gateway` resource in the chart's
release namespace, and `HTTPRoute.parentRefs` points at that Gateway
(same namespace).

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>
  namespace: <ns>
spec:
  parentRefs:
    - name: <app> # the chart-owned Gateway above
      kind: Gateway # default, but explicit is clearer
      sectionName: web
```

Reference charts:

- `k3s/gxy-cassiopeia/apps/caddy/charts/caddy` — Flexible-zone (HTTP-only) shape.
- `k3s/gxy-management/apps/artemis/charts/artemis` — Full-Strict-zone (HTTPS) shape.

## Pitfall 6 — Gateway API CRDs are bundled by k3s

The k3s-bundled `traefik-crd` Helm chart **ships standard Gateway API
CRDs**. Do NOT `kubectl apply -f gateway-api/...` manually:

```
helm-install-traefik-crd CrashLoopBackOff:
  invalid ownership metadata; label validation error:
  missing key "app.kubernetes.io/managed-by": must be set to "Helm"
```

Helm refuses to adopt CRDs without its labels.

**Pattern.** Trust the bundle. If experimental CRDs are needed,
annotate the existing chart as unmanaged first; never `kubectl apply`
unowned CRDs over Helm-owned ones.

Source: [k3s discussion #13463](https://github.com/k3s-io/k3s/discussions/13463).

## Decision rubric

```text
Bringing up a new galaxy?
  ├─ Use `k3s/gxy-<existing>/cluster/traefik-config.yaml` as the template.
  └─ Verify the four Pitfalls 2/3 keys before first bootstrap:
     - updateStrategy.rollingUpdate.maxUnavailable: 1
     - updateStrategy.rollingUpdate.maxSurge: 0
     - podSecurityContext.runAsUser: 0
     - securityContext.capabilities.add: [NET_BIND_SERVICE]

Adding a Gateway/HTTPRoute to an existing chart?
  ├─ Match the entrypoint port (Pitfall 4)
  ├─ parentRef the in-namespace Gateway (Pitfall 5)
  └─ Confirm CF zone SSL mode matches the listener protocol
     (Flexible → :80 only; Full Strict → :80 + :443).

Hitting "missing managed-by" on a CRD?
  └─ Pitfall 6 — do not manually apply Gateway API CRDs.
```

## Configured galaxies

| Galaxy           | Traefik config path                              | Entrypoints               | Zone SSL mode |
| ---------------- | ------------------------------------------------ | ------------------------- | ------------- |
| `gxy-management` | `k3s/gxy-management/cluster/traefik-config.yaml` | `web:80`, `websecure:443` | Full (Strict) |
| `gxy-launchbase` | `k3s/gxy-launchbase/cluster/traefik-config.yaml` | `web:80`                  | n/a (no DNS)  |
| `gxy-cassiopeia` | `k3s/gxy-cassiopeia/cluster/traefik-config.yaml` | `web:80`                  | Flexible      |

## Cross-refs

- [`docs/infra-guides/chart-pre-merge-checklist.md`](./chart-pre-merge-checklist.md)
  point 5 — CF zone SSL mode gate.
- [`docs/infra-guides/cilium-cnp.md`](./cilium-cnp.md) — when adding a
  CNP to a chart that uses Traefik hostNetwork, ingress must allow
  `fromEntities: [host]` (Cilium identifies hostNetwork pods as the
  `host` entity).
- [`docs/flight-manuals/UNIVERSE.md`](../flight-manuals/UNIVERSE.md) §3.2
  — new-galaxy pre-flight file list.
- ADR-009 §Ingress — DaemonSet-over-LB rationale.
- `Universe/spike/field-notes/archive/2026-05-10/infra.md` lines 444-448 +
  800-815 — historical record of the four hostNetwork gotchas (T32
  Woodpecker stamp 2, 2026-04-20).
