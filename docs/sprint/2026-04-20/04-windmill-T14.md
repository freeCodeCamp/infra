# Session 04 — T14: Origin IP allow-list + CF IP refresh cron

**Beads:** `gxy-static-k7d.15` · **Repos:** `fCC/infra` + `fCC-U/windmill`
**Blocks:** T15 (smoke). **Blocked by:** nothing — can run parallel to T32.

## Why this matters

Per D29, Caddy on gxy-cassiopeia only accepts traffic from Cloudflare IP
ranges. CF publishes those at `https://www.cloudflare.com/ips-v4/` and changes
them occasionally. T14 has two halves:

- **Static**: bake current CF IP list into a `CiliumNetworkPolicy` (infra).
- **Dynamic**: weekly Windmill cron that refreshes the policy (windmill).

## Start session

```bash
cd /Users/mrugesh/DEV/fCC-U/windmill
claude
```

(The flow primarily lives in windmill; the one-time manifest is in infra.
Dispatch from the repo the agent will touch most.)

---

## Dispatch prompt

```
You are implementing beads `gxy-static-k7d.15` — T14: Origin IP allow-list +
CF IP refresh cron. Authoritative spec:

- `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md` §4.5.8 "Origin
  access restriction" (D29)
- `/Users/mrugesh/DEV/fCC/infra/docs/tasks/gxy-cassiopeia.md` Task 14 (line 2127)
- `dp_beads_show gxy-static-k7d.15`

Read §4.5.8 first.

## Environment

- Two repos in play:
  - `/Users/mrugesh/DEV/fCC/infra` (CiliumNetworkPolicy manifest)
  - `/Users/mrugesh/DEV/fCC-U/windmill` (refresh cron flow)
- Toolchain: Bun, vitest, wmill CLI (from windmill-claude-plugin)

## Execute in order

### Part A — infra repo

1. Create `k3s/gxy-cassiopeia/apps/caddy/manifests/origin-allowlist-netpol.yaml`
   with Cilium v2 CiliumNetworkPolicy. Bake in current CF IPv4 ranges (list
   from task doc Step 1). Note that port 80 is allowed (TLS terminates at CF;
   origin is plain HTTP). Include node-internal CIDR for health checks
   (`10.7.0.0/16` from `gxy_cassiopeia_k3s.yml`).
2. Also add CF IPv6 ranges per https://www.cloudflare.com/ips-v6/.
3. Reconcile with existing Caddy chart `networkpolicy.yaml` from T13 — this
   new manifest SUPERSEDES any permissive ingress there. Confirm no conflict;
   if conflict, document and recommend deleting the permissive rule.
4. Apply via `just helm-upgrade gxy-cassiopeia caddy` if it's in the chart
   path, OR `kubectl apply -f` if standalone. Task doc says "manifests/"
   (standalone) — follow that.

### Part B — windmill repo

1. **RED tests** — create `workspaces/platform/f/ops/refresh_cf_ips.test.ts`
   asserting:
   - fetches from `https://www.cloudflare.com/ips-v4/` and `/ips-v6/`
   - filters empty lines and comments
   - emits a valid CiliumNetworkPolicy YAML via `kubectl patch`
   - no-op if IP list unchanged since last run (idempotent)
   - logs via Windmill `setProgress` for observability
2. **GREEN** — write `workspaces/platform/f/ops/refresh_cf_ips.ts`. Inject
   `fetchFn` + `kubectlExecFn` for testability.
3. **Flow metadata** — `wmill generate-metadata` produces
   `refresh_cf_ips.yaml`. Add schedule metadata: weekly at 04:17 UTC
   Mondays (off-peak, avoids cron midnight-storm).
4. **Resources** — a `kubeconfig_gxy_cassiopeia` Windmill Resource. Follow
   existing resource pattern (reference an existing kubeconfig resource if
   one already exists).
5. **vitest green, oxlint clean, oxfmt clean.**
6. **Preview run** via Windmill MCP `runScriptPreviewAndWaitResult` against a
   dry-run mode (the flow should take a `dryRun: bool` param).
7. **`just drift`** — assert only new file set, no deletions. If deletions,
   STOP (memory: `feedback_wmill_sync_no_op_deletions.md`).

## Acceptance criteria

- CiliumNetworkPolicy applied; `kubectl get cnp -n caddy caddy-origin-allowlist`
  returns without error
- Fresh CF IPv4 + IPv6 lists baked in (ship date noted in-file comment)
- Health check from gxy-cassiopeia nodes to Caddy works post-policy
  (`kubectl exec -n caddy ... -- curl -sI http://<pod-ip>:80`)
- Flow: vitest all green, preview dry-run succeeds, schedule metadata correct
- External test: `curl --resolve '<site>.freecode.camp:80:<gxy-cassiopeia-node-ip>' http://<site>.freecode.camp/` (NOT via CF) returns connection refused or 403 — proves allow-list works

## TDD

Write failing tests first for the windmill flow (Part B). Part A is a YAML
manifest, validated by `kubectl apply --dry-run=server`.

## Constraints

- Do NOT open Caddy to all origins "temporarily for debugging".
- Do NOT hardcode the kubeconfig path — Windmill Resource only.
- Do NOT push.

## Output expected back

1. Infra files + windmill files created
2. `kubectl apply --dry-run=server` output
3. vitest output
4. Preview-run output
5. Two proposed commit messages (one per repo)
6. "T14 ready to close" signal

## Commit policy

Prepare commits in each repo; do not push either.

## When stuck

- If CF IP list endpoint changes format (they do, occasionally), prefer the
  documented format at https://developers.cloudflare.com/fundamentals/reference/cloudflare-ip-addresses/
- If kubectl patch fails with "resource version conflict", add retry with
  `kubectl get cnp ... -o yaml | ... | kubectl replace -f -` pattern.
```

---

## Hand-off

T14 closing partially unblocks T15 (origin restriction must be live before
smoke can assert "CF-only").
