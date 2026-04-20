# Session 01 — T32: Woodpecker DNS + Cloudflare Access + admin users

**Beads:** `gxy-static-k7d.33` · **Repo:** `fCC/infra` · **Branch:** `feat/k3s-universe`
**Blocks:** T11, T21 (via critical path). Runs Day 0, T+0h.

## Why this is first

Woodpecker is installed (T10 closed) but not exposed. CLI release is blocked
until `woodpecker.freecodecamp.net` resolves, is gated by CF Access, and has a
real admin user. T32 is the last gate before T11 (per-site secrets) can run.

## Start session

```bash
cd /Users/mrugesh/DEV/fCC/infra
claude
```

Then paste the prompt below.

---

## Dispatch prompt

```
You are implementing beads `gxy-static-k7d.33` — T32: Woodpecker DNS +
Cloudflare Access policy + admin users. The authoritative spec is the beads
record DESIGN block:

    bd show gxy-static-k7d.33

Read it in full before acting. The rest of this message is orchestration.

## Environment

- cwd: `/Users/mrugesh/DEV/fCC/infra`
- branch: `feat/k3s-universe` (already checked out)
- direnv-loaded: CF_API_TOKEN, CF_ZONE_ID, DO tokens, sops key (verify with
  `echo $CF_API_TOKEN | head -c 8`; if unset, `direnv allow` and retry)

## Preconditions to verify before any change

1. `bd show gxy-static-k7d.11` — T10 must be CLOSED
2. Woodpecker server pod Ready (via Tailscale or jump host):
   `kubectl -n woodpecker get deploy woodpecker-server`
3. No stale DNS for `woodpecker.freecodecamp.net`:
   `dig +short woodpecker.freecodecamp.net` — either empty OR matches what you
   are about to set

If any precondition fails, STOP and report. Do not patch around it.

## Execute in order

Follow the Agent Prompt section of `bd show gxy-static-k7d.33` exactly:

1. Step 1 — DNS record. Grep for existing CF DNS pattern
   (`grep -rn "cloudflare" ansible/inventory/` and look at how
   `windmill.freecodecamp.net` was provisioned). Add the matching entry for
   `woodpecker.freecodecamp.net`. Do NOT introduce a new mechanism.
2. Step 2 — Write `docs/runbooks/woodpecker-cf-access.md`. ClickOps runbook for
   CF Zero Trust → Access → Applications setup (email OTP, platform-team group,
   24h session, self-hosted). Include verification curl commands.
3. Step 3 — Edit `k3s/gxy-launchbase/apps/woodpecker/values.production.yaml`.
   Set `WOODPECKER_ADMIN` and `WOODPECKER_ORGS`. ASK THE USER for the admin
   GitHub username before editing — do not guess. Then
   `just helm-upgrade gxy-launchbase woodpecker`.
4. Step 4 — Smoke runbook is an operator action. Write the expected output in
   the runbook, then STOP and ask the operator to execute it. Do not attempt
   to authenticate via CF OTP from inside the session.
5. Step 5 — Create `k3s/gxy-launchbase/apps/woodpecker/docs/post-t10-operator.md`
   checklist.

## Acceptance criteria (verbatim from beads)

- T10 closed THEN woodpecker-server Ready=3/3
- DNS step done THEN `dig +short woodpecker.freecodecamp.net` returns CF proxy IP
- CF Access THEN `curl -sI https://woodpecker.freecodecamp.net` returns 302 to
  `*.cloudflareaccess.com`
- Admin env updated THEN `kubectl -n woodpecker get deploy woodpecker-server -o
  yaml | grep WOODPECKER_ADMIN` shows the operator's GH username
- Smoke THEN operator records Phase 2 field-notes entry confirming login works
- Runbook THEN markdownlint passes

## TDD

Not applicable — this is infra/docs work, not code with tests. Verification is
the runbook + `curl -sI`, not a unit test.

## Constraints

- Do NOT modify the Woodpecker Helm chart itself (T10's scope).
- Do NOT create GitHub OAuth apps (T10's scope, already done).
- Do NOT dispatch T11 — the blocks relationship in beads enforces this; let the
  orchestrator pick up T11 after T32 closes.
- Do NOT `git push` — operator controls git writes.

## Output expected back to operator

1. Diffs ready to commit (list the files touched, no raw diffs inline)
2. The runbook path
3. The curl output confirming CF Access 302
4. A one-line proposed commit message (Conventional Commits style)
5. Explicit statement: "T32 ready to close — operator to run `dp_beads_close
   gxy-static-k7d.33` after verifying field-notes entry"

## Commit policy

Prepare the commit; do NOT execute it. Provide the exact `git add` + `git
commit -m ...` the operator should run. The operator will run
`/cmd-git-rules` before any commit.

## When stuck

- If the existing DNS pattern is ambiguous (both `group_vars/cloudflare.yml`
  AND a Windmill flow exist), surface the ambiguity to the operator and ask
  which is canonical. Do not pick one silently.
- If CF Access already has an app named `Woodpecker CI`, do not overwrite —
  diff the policy and ask.
- If `WOODPECKER_ADMIN` is already set to a value, ask before replacing.
```

---

## Verification the operator runs after the session

```bash
cd /Users/mrugesh/DEV/fCC/infra
dig +short woodpecker.freecodecamp.net
curl -sI https://woodpecker.freecodecamp.net | head -5
# Expect: 302 Location: https://<team>.cloudflareaccess.com/cdn-cgi/access/login/...
```

## Hand-off

When T32 closes, unblock:

- [02-windmill-T11.md](02-windmill-T11.md)
- [03-infra-T21.md](03-infra-T21.md)
