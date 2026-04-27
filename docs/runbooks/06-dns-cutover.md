# DNS Cutover Runbook — gxy-static → gxy-cassiopeia

**Task:** T25 (`gxy-static-k7d.26`)
**Spec:** `docs/rfc/gxy-cassiopeia.md` §6.8 (execution) + §6.9 (soak + rollback) + §6.9.1 (content-parity caveat)
**Scope:** Phase 6 cutover of `*.freecode.camp` from gxy-static to gxy-cassiopeia.

> **Lifecycle note.** Move this file to [`archive/`](archive/) after gxy-static
> decommission completes (post-cutover #26 + 30-day soak). Procedure is
> single-use and only relevant during the active cutover window; once
> gxy-static is gone, the playbook is historical.

This runbook is the **only** supported cutover procedure. Deviating from the sequence risks either silent site 404s or a multi-hour outage.

---

## 1. Pre-cutover announcement (T-1 hour)

1. Open a 1-hour quiet window on the platform-team channel:
   > "gxy-cassiopeia DNS cutover starting at HH:MM UTC. During the window (starting T-0, ending T+15m): **no promotes, no rollbacks, no new deploys.** Pipeline triggers WILL be paused. Report anything serving freecode.camp breaking in the thread."
2. Announce in `#general` 30 minutes before T-0 with the same language plus the incident-response channel link.
3. Pause all Woodpecker pipelines in the relevant constellation repos for the duration:
   ```bash
   # Operator action — optional but recommended for the first production cutover:
   # In each constellation repo, disable the repo in Woodpecker UI OR
   # temporarily rotate WOODPECKER_AGENT_SECRET to force all pipelines into error state.
   # Re-enable at T+15m after exit criterion is green.
   ```

---

## 2. Preflight gate (MUST be green before proceeding)

```bash
cd ~/DEV/fCC/infra
just cutover-preflight
```

The script (T23) enumerates sites in `gxy-static-1`, runs 8 checks per site against `universe-static-apps-01`, and exits:

| Exit code | Meaning                                              | Action                                           |
| --------- | ---------------------------------------------------- | ------------------------------------------------ |
| 0         | All green                                            | Proceed to §3                                    |
| 2         | Infra setup wrong (rclone remote / env vars missing) | Fix env, re-run                                  |
| 3         | Any site fails any check                             | **Halt. Fix the failing sites. Do not proceed.** |

**Hard gate:** if exit ≠ 0, **do NOT cut over**. The script prints a per-site matrix so the specific failures are visible.

Common fixes:

- `fail:no-deploys-in-cassiopeia` → site owner must deploy to the new galaxy via `universe deploy`.
- `fail:no-production-alias` → re-run the deploy with `--alias production`.
- `fail:origin-returned-5xx` → investigate gxy-cassiopeia Caddy logs before proceeding.

---

## 3. Snapshot (rollback substrate)

Export current DNS state so the rollback script can restore it verbatim:

```bash
just cf-dns-export freecode.camp > /tmp/cutover-dns-pre-$(date +%Y%m%d-%H%M%S).json
ls -la /tmp/cutover-dns-pre-*.json   # confirm file exists and is non-empty
```

**Save the filename.** Rollback (§6) is useless without it.

---

## 4. Cutover

### 4.1 Dry-run first (ALWAYS)

```bash
just cf-dns-cutover freecode.camp <CASSIOPEIA_IP_1>,<CASSIOPEIA_IP_2>,<CASSIOPEIA_IP_3>
# Defaults to --dry-run. Prints the intended deletes + creates for @, www, *.
```

Verify the dry-run output:

- Lists the 3 existing gxy-static A records for each of `@`, `www`, `*` (expecting 3 records × 3 names = 9).
- Shows 3 new A records per name pointing to gxy-cassiopeia IPs.
- No 5xx in the output stream.

### 4.2 Apply

```bash
just cf-dns-cutover freecode.camp <CASSIOPEIA_IP_1>,<CASSIOPEIA_IP_2>,<CASSIOPEIA_IP_3> --apply
```

Expected runtime: ~5–10 seconds (9 deletes + 9 creates). TTL on all records is 60s.

Immediately after apply, start §5 monitoring — **do not leave the terminal.**

---

## 5. Watch (T+0 to T+15)

Run these four streams in parallel panes. If any surfaces a problem, jump to §6 rollback.

### 5.1 Caddy on gxy-cassiopeia (inbound traffic)

```bash
cd ~/DEV/fCC/infra/k3s/gxy-cassiopeia
export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
kubectl -n caddy logs -l app.kubernetes.io/name=caddy -f --max-log-requests=3
```

Expected: JSON request logs start flowing within 60s. Status codes should be ~99% 200/302/304.

### 5.2 Caddy on gxy-static (traffic fall-off)

```bash
cd ~/DEV/fCC/infra/k3s/gxy-static
export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
kubectl -n caddy logs -l app.kubernetes.io/name=caddy -f --max-log-requests=3 --since=60s
```

Expected: request rate visibly drops as CDN edges re-resolve DNS (5–60s per edge). gxy-static should be near-zero by T+5m.

### 5.3 Cloudflare dashboard

Open `dash.cloudflare.com/<account>/freecode.camp` → **Analytics & Logs** → **Traffic**:

- Cached vs uncached requests graph — no sudden origin-side spike.
- Status codes → 5xx line should stay below 0.5%.
- Origin response time — should be within 1.5× of gxy-static baseline.

### 5.4 Uptime Robot (T24) + CF Notifications

Monitor `status.<internal>` and the platform-team email inbox for:

- Any uptime alert firing on a `*.freecode.camp` monitor → immediate signal to investigate.
- `gxy-cassiopeia-origin-response-time` (W4 canary) → tripping means the LRU is thrashing.

---

## 6. Rollback

**Trigger conditions (any one of these within T+15):**

- 5xx rate on the zone > 1% sustained for 2 minutes
- Origin error rate > 5% for 2 minutes
- Any Uptime Robot monitor critical for > 1 cycle
- Manual operator decision based on log stream anomalies

### 6.1 Rollback content-parity caveat (READ FIRST — per RFC §6.9.1)

**DNS revert restores availability, NOT content parity.** During the soak window, all new deploys flow exclusively to `universe-static-apps-01`; `gxy-static` is frozen at cutover-day state.

A day-N rollback (N > 1) serves the cutover-day snapshot. Every constellation that shipped between cutover and rollback silently regresses to older content.

**Before executing the DNS revert, the operator MUST:**

1. Announce the rollback window AND the content regression to platform-team + every constellation owner in scope.
2. Enumerate sites that deployed between cutover and now:
   ```bash
   CUTOVER_DATE=<YYYY-MM-DDTHH:MM:SSZ of your cutover apply step>
   for repo in $(ls ~/DEV/fCC-U/Universe/spike/constellations/); do
     woodpecker pipeline list --after "$CUTOVER_DATE" --status success --repo "freeCodeCamp-Universe/$repo" 2>/dev/null \
       | grep -q . && echo "REGRESSED: $repo"
   done
   ```
3. Require each regressed site owner to re-deploy to gxy-static using the pre-Phase-2 legacy path (requires old universe-cli `<0.4`) OR accept the regression until DNS re-flips to a repaired gxy-cassiopeia.
4. Dual-target writes (RFC §5.24.1) are deferred — the caveat stands for M1.

### 6.2 Execute rollback

```bash
just cf-dns-restore /tmp/cutover-dns-pre-<timestamp>.json            # dry-run first
just cf-dns-restore /tmp/cutover-dns-pre-<timestamp>.json --apply    # commit
```

Expected DNS re-resolution: < 60s for proxied records, but **not guaranteed**. Set staff communication to "expect 1–5 min revert window."

### 6.3 Preserve forensics

Before remediating on gxy-cassiopeia:

```bash
cd ~/DEV/fCC/infra/k3s/gxy-cassiopeia
export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
mkdir -p /tmp/cutover-forensics-$(date +%Y%m%d-%H%M%S)
cd $_
kubectl -n caddy get pods -o yaml > pods.yaml
kubectl -n caddy describe pods > describe.txt
kubectl -n caddy logs -l app.kubernetes.io/name=caddy --tail=10000 --previous > logs.txt
kubectl -n caddy events > events.txt
tar czf ../forensics-$(basename $PWD).tgz .
```

Upload the tarball to a safe location before touching the cluster.

---

## 7. Exit criterion (T+15 to T+15m)

**All MUST hold for 15 consecutive minutes:**

| Metric                | Threshold                    | Where to check                                                                       |
| --------------------- | ---------------------------- | ------------------------------------------------------------------------------------ |
| CF zone 5xx rate      | < 0.5%                       | Cloudflare dashboard → Analytics → Status codes                                      |
| Apex / www redirects  | 302 → `www.freecodecamp.org` | `curl -sI https://freecode.camp/` and `https://www.freecode.camp/`                   |
| All preflight sites   | 200 on canonical host        | `just cutover-preflight` (re-run post-cutover, this time against cassiopeia traffic) |
| Caddy pod memory      | < 50% of limit               | `kubectl -n caddy top pods`                                                          |
| Uptime Robot monitors | All Up                       | status.uptimerobot.com or dashboard                                                  |
| CF Notifications      | No active alerts             | Notifications tab                                                                    |

If all six hold for 15 minutes, declare success in the platform-team channel and close the quiet window.

---

## 8. Post-cutover

1. Re-enable Woodpecker pipelines (if disabled in §1.3).
2. Record actual values in the field-notes template (§9).
3. Enter the **30-day soak** (RFC §6.9):
   - gxy-static stays live as the limited rollback substrate (D26).
   - Daily: `just cutover-preflight` against cassiopeia to detect alias drift.
   - No promotes to gxy-static for the window.
   - User-led decommission after day 30.

---

## 9. Field-notes template

After the soak completes OR after any rollback, append to `~/DEV/fCC-U/Universe/spike/field-notes/infra.md` under the `## Cutover log` heading (create if absent, placed **after** "Static stack drift from ADR-007"):

```markdown
### gxy-cassiopeia cutover — YYYY-MM-DD HH:MM UTC

**Operator:** <name>
**Cutover SHA (infra repo HEAD):** <short SHA>
**Preflight output:** paste or link
**Cutover command:** `just cf-dns-cutover freecode.camp <ips> --apply`

**Observed metrics:**

| Metric                                           | Actual |
| ------------------------------------------------ | ------ |
| DNS propagation time (first edge → last edge)    | FILL   |
| Peak 5xx rate during window                      | FILL   |
| Peak origin response time p95                    | FILL   |
| Time to 15-min steady state (from cutover apply) | FILL   |
| Any issues surfaced                              | FILL   |

**Rollback?** no | yes → reason: FILL
**Regressed sites (if rollback):** FILL (from §6.1 enumeration)

**Notes for next time:** FILL
```

---

## 10. Decommission checklist (post-M5)

Per RFC §6.9, after the 30-day soak completes:

- [ ] Export `gxy-static-1` R2 bucket manifest for historical reference
- [ ] Tear down gxy-static droplets; remove from OpenTofu state
- [ ] CF DNS: remove any lingering references to gxy-static IPs
- [ ] Append final decommission entry to `spike/field-notes/infra.md`

This is out of scope for T25 — documented here so the operator knows the runbook does NOT include the decommission itself.

---

## Exit criteria for closing T25

- [ ] This runbook committed at `docs/runbooks/dns-cutover.md`
- [ ] All sections present: announcement, preflight gate, snapshot, cutover, watch, rollback (with §6.1 caveat verbatim), exit criterion, post-cutover, field-notes template, decommission checklist
- [ ] §6.1 rollback content-parity caveat is verbatim from RFC §6.9.1
- [ ] `markdownlint` (if available) returns no errors
- [ ] Field-notes template section 9 is ready for operator fill-in during actual cutover

When all hold:

```bash
bash -c 'source /Users/mrugesh/.claude/plugins/cache/dotplugins/dp-cto/8.0.4/lib/dp-beads.sh && dp_beads_close gxy-static-k7d.26 "completed: cutover runbook + field-notes template"'
```
