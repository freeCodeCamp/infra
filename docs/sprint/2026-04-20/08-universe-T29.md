# Session 08c — T29: Field notes, Phase 4 (and Phase 6) readiness

**Beads:** `gxy-static-k7d.30` · **Repo:** `fCC-U/Universe` · Size: **[S]**
**Blocks:** nothing. **Blocked by:** T15 (Phase 4 smoke must have passed).
Phase 6 sub-entry is post-DNS-cutover (not this sprint; leave placeholder).

## Why this matters

Closes the docs stream for Phase 4. Records the measurements that prove the
Caddy + R2 pipeline is production-ready. Feeds the DNS cutover (T25 runbook
already exists) decision.

## Start session

```bash
cd /Users/mrugesh/DEV/fCC-U/Universe
claude
```

---

## Dispatch prompt

```
You are implementing beads `gxy-static-k7d.30` — T29: Update infra field notes,
Phase 4 and Phase 6 readiness. Authoritative spec:

- `spike/field-notes/infra.md` (append only)
- `docs/tasks/gxy-cassiopeia.md` Task 29 (line 5096) — templates
- `dp_beads_show gxy-static-k7d.30`

## Environment

- cwd: `/Users/mrugesh/DEV/fCC-U/Universe`

## Preconditions

1. `dp_beads_show gxy-static-k7d.16` — T15 closed (Phase 4 smoke passed)
2. `cat ../fCC/infra/scripts/phase4-test-site-smoke.sh` present
3. The phase4-smoke run log is accessible (operator should have captured it
   when closing T15)

## Execute in order

### Entry 1: Phase 4 exit

1. **Gather measurements**:
   - Caddy image tag deployed: `kubectl --context gxy-cassiopeia -n caddy get deploy caddy -o jsonpath='{.spec.template.spec.containers[0].image}'`
   - Alias cache TTL + max entries: grep `../fCC/infra/k3s/gxy-cassiopeia/apps/caddy/charts/caddy/values.yaml`
   - Phase 4 smoke outcome + duration: from T15 run log
   - Caddy pod RAM: `kubectl --context gxy-cassiopeia top pod -n caddy`
   - R2 GetObject baseline rate: Cloudflare dashboard → R2 → gxy-cassiopeia-1 → metrics (or CF API)
   - Origin-only latency p95: run a short curl-burst benchmark (task doc gives format)
   - Origin-allowlist first cron run: `wmill history f/ops/refresh_cf_ips | head -1` (or similar)
2. **Append** `### gxy-cassiopeia Caddy + R2 smoke-validated (2026-04-20)` under
   Operational Findings.
3. **Fill template** from task doc Step 1. No placeholders.

### Entry 2: Phase 6 (cutover) — PLACEHOLDER ONLY

Per task doc Step 2 note: if the cutover template from Task 25 already has a
"FILL AT CUTOVER TIME" block in the field notes, leave it alone — it fills
on cutover day, not today. Confirm by grep; if no template block exists yet,
create one with explicit `TODO: fill on cutover day` markers; do NOT fill.

### Finalize

1. markdownlint clean
2. Only `spike/field-notes/infra.md` modified

## Acceptance criteria

- Phase 4 entry appended, dated 2026-04-20, all real measurements
- Phase 6 entry exists as placeholder only (no invented cutover date)
- markdownlint clean
- `git diff` shows append-only changes

## TDD

No tests.

## Constraints

- Append only.
- Phase 6 is OUT of scope for today — do NOT populate it.
- Do not edit ADRs.
- Do not push.

## Output expected

1. `git diff spike/field-notes/infra.md`
2. markdownlint output
3. Proposed commit message
4. "T29 ready to close" signal

## When stuck

- If Phase 4 smoke log is not archived anywhere, reproduce it:
  `cd ../fCC/infra && just phase4-smoke 2>&1 | tee /tmp/phase4-smoke.log`
  Then extract the numbers from the log.
- If kubectl context is not configured for gxy-cassiopeia, ask operator.
```

---

## Hand-off

T29 closing is the docs-stream terminal. Combined with T15 closing,
universe-cli release session ([09-universe-cli-release.md](09-universe-cli-release.md))
has full green signal.
