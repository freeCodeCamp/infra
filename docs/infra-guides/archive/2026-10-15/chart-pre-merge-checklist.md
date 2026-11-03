# Chart pre-merge checklist

> **Historical.** Archived 2026-10-15. This checklist describes the Universe charts, which were torn down in October 2026. Its paths exist only at commit `027d913d6f38`. No chart on `main` has templates.

Operator-runnable five-point checklist for every new Helm chart landing under `k3s/<cluster>/apps/<app>/charts/<chart>/`. Promotes operational findings from the 2026-04-27 T34 chart-side pattern study (archived in `Universe/.archive/artemis/2026-04-27-chart-side-pattern.md`) into canonical guidance.

> **Read first:** the chart you are about to merge end-to-end, plus the closest existing chart in the same cluster. Prior art catches most of this list before review.

## Why this exists

T34 (artemis chart, 2026-04-27) shipped with `helm template` rendering all resources cleanly and `helm lint` passing — then surfaced **five preventable bugs** on live deploy before phase-5 smoke went green. Every bug was findable at dispatch time by reading adjacent apps. This checklist is the post-mortem turned into a pre-merge gate.

Run it before requesting review; the reviewer runs it again before merge.

## The five points

### 1. Middleware references resolve in chart namespace

Traefik `Middleware` resources are namespace-scoped. A chart that references a Middleware by name (`secure-headers`, `redirect-https`, `compress`, …) MUST also create it in the chart's namespace — or the HTTPRoute fails with Traefik 404 on every request.

**Check:**

```bash
# In the chart's helm template output, list every Middleware reference
helm template <release> <chart-path> | grep -E 'kind: Middleware|middlewares:' -A 2

# Confirm each name has a sibling `kind: Middleware` resource
# rendered into the same namespace.
```

**Reviewer rule.** Reject if the HTTPRoute references a Middleware not rendered by the same chart in the same namespace.

### 2. Cluster CNI dictates NetworkPolicy CRD

Check the cluster CNI first. `ops-o11y` runs flannel (`ansible/play-k3s--servers.yml:70`), and no live cluster runs Cilium. The Cilium rules below come from the Universe platform (historical, commit `027d913d6f38`). Apply them only to a Cilium cluster. On Cilium, vanilla `networking.k8s.io/v1 NetworkPolicy` does **not** correctly match Traefik on hostNetwork because `namespaceSelector: kube-system` matches by pod namespace, not host namespace. T34 originally shipped vanilla NP → Traefik blocked on 2 of 3 nodes.

Use `cilium.io/v2 CiliumNetworkPolicy` with `fromEntities: [cluster, host]` per the cassiopeia `caddy` precedent.

**Check:**

```bash
# Reject any vanilla NetworkPolicy in a Cilium cluster chart
grep -rE 'apiVersion: networking\.k8s\.io/v1$' <chart-path>/templates/

# Confirm CNP shape includes the host entity when ingress is hostNetwork
grep -A 5 'fromEntities' <chart-path>/templates/*.yaml
```

**Reviewer rule.** On a Cilium cluster, vanilla NP under `k3s/<cluster>/apps/` is a reject. The single non-CNP exception on Universe was `valkey` (vanilla NP, ingress plus DNS-only egress, no L7).

Read [`cilium-cnp.md`](../2026-10-14/cilium-cnp.md) before adding **any** CNP — the DNS L7 trap is a separate gate.

### 3. Service env contract = read source + sample

Chart `env:` values must match the consumer service's config-loader keys **AND** validation rules character-for-character. Inference from ADR / RFC prose is unsafe.

**Sources to read in this order:**

1. `<service>/.env.sample` — name source of truth.
1. `<service>/internal/config/config.go` (or language-equivalent loader) — validation rules (regex, length, format).
1. Any token-format helpers (`jwt.go`, `crypto.go`, etc.) — placeholder syntax (`{site}/{deployId}` vs `<site>/<ts>-<sha>`, etc.).

**Check:**

```bash
# Diff the chart's env keys against the service's .env.sample
helm template <release> <chart-path> | yq '.spec.template.spec.containers[].env[].name' \
  | sort -u > /tmp/chart-env.txt
grep -E '^[A-Z][A-Z0-9_]*=' <service-repo>/.env.sample | cut -d= -f1 | sort -u > /tmp/sample-env.txt
diff /tmp/sample-env.txt /tmp/chart-env.txt
```

Missing required keys, or extra unrecognised keys, both fail review. T34 originally used wrong key suffixes (`*_KEY_FORMAT` missing) AND wrong placeholder syntax → pod `CrashLoopBackOff` at startup.

### 4. Producer/consumer shared-store key format round-trips

When two services share a backing store (R2 bucket, Valkey hash, S3-compat key space), the **writer's** key format MUST match the **reader's** template — byte-exact. Read the **reader's** source first; pin the contract there; configure the writer to emit it.

Example surface (Universe, historical): artemis writes alias keys to R2 that caddy `r2_alias` reads. T34 originally wrote `<site>/preview`; caddy reads `<site>.<root>/preview` (FQDN form). Both formats were configurable on the writer side; reading the writer-side ADR alone produced the wrong contract.

**Check:**

```bash
# Find the reader. Find the key template it consumes.
grep -rnE 'Bucket\.GetObject|R2\.Get|valkey\.Get|HGET' <reader-repo>/

# Confirm the writer emits exactly that template.
grep -rnE 'PutObject|R2\.Put|HSET' <writer-repo>/
```

**Reviewer rule.** If two charts touch the same R2 prefix or Valkey keyspace, the PR description must cite the reader source line and the writer source line and show they agree.

### 5. CF zone SSL mode is a deployment-time precondition

Cloudflare zone-level SSL mode is **Flexible** today (HTTP edge → HTTP origin). Chart Gateway listeners must NOT terminate HTTPS; the origin pattern is plain `:80` behind Traefik `web` entrypoint.

A `:443` listener in the chart with the zone on Flexible produces 502 or 504 at the edge with no origin-side error — extremely hard to diagnose without reading this rule.

**Check:**

Export `CF_API_TOKEN` and `ZONE_ID` first. The repository does not provide them.

```bash
# Read the CF zone SSL mode for the target domain BEFORE writing
# chart Gateway listeners.
curl -fsS -H "Authorization: Bearer $CF_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/ssl" \
  | jq -r '.result.value'   # → "flexible"
```

The chart should emit one Gateway listener on `:80` (Traefik `web` entrypoint) and route via `HTTPRoute`. Reference (historical, commit `027d913d6f38`): the cassiopeia `caddy` chart (`k3s/gxy-cassiopeia/apps/caddy/charts/caddy`) is the canonical Flexible-zone shape.

**Reviewer rule.** Any chart shipping `port: 443` listeners requires prior CF zone migration to `Full (Strict)` — a separate PR. Do not bundle SSL-mode flips with chart introduction.

## Reviewer reject reasons (short list)

Use these verbatim in PR review when rejecting:

1. `Middleware ref but no sibling Middleware resource in chart`
1. `Vanilla NetworkPolicy in a Cilium cluster — convert to CiliumNetworkPolicy`
1. `Chart env diverges from <service>/.env.sample (see diff)`
1. `Shared-store key format does not round-trip with <reader>`
1. `Gateway HTTPS listener with zone on Flexible — flip zone first`

## Cross-refs

- [`docs/GUIDELINES.md`](../../../GUIDELINES.md) — broader doc/format conventions; this checklist is the §Chart pre-merge specialisation.
- [`docs/infra-guides/archive/2026-10-14/cilium-cnp.md`](../2026-10-14/cilium-cnp.md) — CNP patterns and the DNS L7 trap (point 2 dovetails with this).
- `Universe/.archive/artemis/2026-04-27-chart-side-pattern.md` — source incident (T34 chart-side pattern study, 2026-04-27).
- Reference charts (historical, commit `027d913d6f38`):
  - `k3s/gxy-cassiopeia/apps/caddy/charts/caddy` — CNP Pattern A + Flexible-SSL Gateway shape.
  - `k3s/gxy-management/apps/artemis/charts/artemis` — CNP Pattern B
    - Middleware-in-chart shape.
