# Session 06 — T15: Phase 4 test-site smoke validation runbook + script

**Beads:** `gxy-static-k7d.16` · **Repo:** `fCC/infra`
**Blocks:** universe-cli release (via E2E gate), T29.
**Blocked by:** T11 + T21 + T14.

## Why this matters

This is the gate that proves the full R2 → Caddy → CF chain works. Phase 4
exits only when this smoke passes. It is **infra's own tool** (not
universe-cli) — uses rclone directly so it has no circular dependency on the
CLI we are about to release.

## Start session

```bash
cd /Users/mrugesh/DEV/fCC/infra
claude
```

---

## Dispatch prompt

```
You are implementing beads `gxy-static-k7d.16` — T15: Phase 4 test-site smoke
validation runbook + script. Authoritative spec:

- `docs/rfc/gxy-cassiopeia.md` §6.6 "Phase 4 exit"
- `docs/tasks/gxy-cassiopeia.md` Task 15 (line 2372) — full bash script template in Step 1
- `dp_beads_show gxy-static-k7d.16`

## Environment

- cwd: `/Users/mrugesh/DEV/fCC/infra`
- direnv from `k3s/gxy-cassiopeia/.envrc` loads: `AWS_ACCESS_KEY_ID`,
  `AWS_SECRET_ACCESS_KEY` (R2 rw), `R2_ENDPOINT`, `R2_BUCKET`,
  `GXY_CASSIOPEIA_NODE_IP`, `CF_API_TOKEN`, `CF_ZONE_ID`
- rclone + curl + jq installed (check with `which`)

## Preconditions

1. T11 closed (per-site secrets provisionable)
2. T21 closed (pipeline template exists)
3. T14 closed (origin allow-list live — smoke must hit through CF, not origin directly)
4. gxy-cassiopeia cluster reachable (`kubectl -n caddy get pods`)
5. R2 bucket `gxy-cassiopeia-1` exists (T12 closed)

## Execute in order

1. **Read task doc Task 15 Step 1 verbatim** — the bash script template is
   complete; your job is to finish it (task doc truncated at "[2/8] Upload
   deploy prefix").
2. **Complete `scripts/phase4-test-site-smoke.sh`** with all 8 steps:
   1. Create test payload in `$TMP_DIR/dist/`
   2. Upload to `test.freecode.camp/deploys/$DEPLOY_ID/` via rclone
   3. Write alias files `test.freecode.camp/production` + `preview`
   4. Provision temp CF DNS record `test.freecode.camp → gxy-cassiopeia-node-IP` (proxied)
   5. Wait for DNS propagation (poll `dig +short` with timeout)
   6. Curl `https://test.freecode.camp/` — assert 200 + body contains `phase4-smoke $DEPLOY_ID`
   7. Curl with `Host:` header hitting node IP directly — assert 403/refused (origin restriction works)
   8. Cleanup: delete R2 prefix, delete CF DNS record, remove alias files
3. **Make idempotent + safe**: `trap` for cleanup on exit (success OR failure).
   The DNS record MUST be deleted on failure or we leak `test.freecode.camp`
   pointing nowhere.
4. **`chmod +x scripts/phase4-test-site-smoke.sh`** + shellcheck clean.
5. **justfile recipe** — add `phase4-smoke:` under a `[group('k3s')]` recipe
   that invokes the script. Match existing recipe style.
6. **Runbook** — `docs/runbooks/phase4-smoke.md` with when to run, what it
   means when it fails, manual cleanup steps if trap fails.
7. **Run it** — execute the smoke against the live bucket. Expect green.
8. **Record outcome** — print summary stdout plus ISO timestamp. Operator
   captures for T29 field-notes.

## Acceptance criteria

- `shellcheck scripts/phase4-test-site-smoke.sh` — clean
- `just phase4-smoke` — exits 0 end-to-end against live gxy-cassiopeia
- On forced failure (e.g., inject a bad alias): trap cleans up DNS + R2
  prefix; no drift left behind
- Runbook at `docs/runbooks/phase4-smoke.md` documents failure modes
- Script output includes R2 prefix + CF DNS record ID so manual cleanup is
  possible if automatic cleanup fails

## TDD

Bash scripts are tested by running them. Add a dry-run mode (`--dry-run`) that
prints the intended rclone + curl commands without executing. Assert dry-run
output matches the documented 8 steps.

## Constraints

- Do NOT leave DNS records or R2 prefixes on failure — trap or die.
- Do NOT run this against `freecode.camp` production hosts — `test.freecode.camp`
  is the only permitted FQDN.
- Do NOT push.

## Docs to update (same session)

1. **Field notes — Universe repo** (requires `--add-dir`):
   `/Users/mrugesh/DEV/fCC-U/Universe/spike/field-notes/infra.md` — append
   a terse `### Phase 4 smoke green (2026-04-20)` ENTRY (the rich
   measurements-laden entry is T29's job; this one just records "smoke
   passed + duration + any surprises discovered mid-run").
2. **Flight manual — infra repo**:
   `/Users/mrugesh/DEV/fCC/infra/docs/FLIGHT-MANUAL.md` — add section
   pointing to `docs/runbooks/phase4-smoke.md` + `just phase4-smoke`
   recipe under gxy-cassiopeia Phase 4 validation.
3. **Local docs**:
   - Script: `scripts/phase4-test-site-smoke.sh`
   - Runbook: `docs/runbooks/phase4-smoke.md`
   - justfile recipe: `phase4-smoke`

## Output expected

1. Script + runbook + justfile recipe
2. Live run stdout (with timestamps)
3. `dig +short test.freecode.camp` post-cleanup: empty
4. `rclone lsd r2:gxy-cassiopeia-1/test.freecode.camp/` post-cleanup: empty
5. Field-notes diff + flight-manual diff
6. Proposed commit message
7. "T15 ready to close — rich measurements will land in T29" signal

## Commit policy

Prepare commit; do not push.

## When stuck

- If rclone can't auth against R2 with the ambient creds, the direnv load
  failed. Run `direnv allow k3s/gxy-cassiopeia/` and retry — do not hardcode.
- If CF DNS record creation races with the cleanup from a previous failed run
  (record already exists), adjust the script to DELETE-then-CREATE. Idempotency
  over detection.
- If curl through CF returns 5xx, inspect Caddy logs:
  `kubectl -n caddy logs -l app.kubernetes.io/name=caddy --tail=50`. Surface
  the root cause to operator rather than retrying blindly.
```

---

## Hand-off

When T15 passes, signal universe-cli release session ([09-universe-cli-release.md](09-universe-cli-release.md))
and T29 ([08-universe-T29.md](08-universe-T29.md)).
