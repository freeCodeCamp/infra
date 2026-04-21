# Session 02 — T11: Per-site R2 secret provisioning Windmill flow

**Beads:** `gxy-static-k7d.12` · **Repo:** `fCC-U/windmill` · **Branch:** new feature branch
**Blocks:** T21 (pipeline template depends on per-site secrets existing), T15 (smoke).
**Blocked by:** T32.

## Why this matters

Pipelines run with **repo-scoped** R2 tokens path-restricted to
`gxy-cassiopeia-1/{site}/*`. D22 explicitly rejects org-scoped tokens — a
compromised dep in one constellation must not write to another. This flow is
the only way creds enter Woodpecker. Without it, T21 pipelines have nothing to
auth with and T15 smoke cannot pass.

## Start session

```bash
cd /Users/mrugesh/DEV/fCC-U/windmill
claude
```

Then paste the prompt below.

---

## Dispatch prompt

````
You are implementing beads `gxy-static-k7d.12` — T11: Per-site R2 secret
provisioning Windmill flow. The authoritative spec is in:

1. Infra RFC `§4.2.4`: `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md`
2. Infra task doc `Task 11`: `/Users/mrugesh/DEV/fCC/infra/docs/tasks/gxy-cassiopeia.md` (line 1465)
3. Beads record DESIGN block: `dp_beads_show gxy-static-k7d.12`

Read §4.2.4 + §5.20 (D22 rationale against org-scope) before writing any code.

## Environment

- cwd: `/Users/mrugesh/DEV/fCC-U/windmill`
- Toolchain: Bun, pnpm, vitest, oxfmt, oxlint, husky (mandated by Universe
  toolchain 2026-04-08 — see `docs/` in this repo and memory feedback
  `feedback_windmill_toolchain.md`).
- Windmill client + mocks: use existing `__mocks__/windmill-client.ts` pattern.
- Testing: vitest + mocked windmill-client. Preview-run via Windmill MCP
  `runScriptPreviewAndWaitResult` before `just plan`.

## Preconditions — shell only, do NOT call bd

1. Woodpecker reachable + CF Access live:
   ```sh
   curl -sI https://woodpecker.freecodecamp.net | head -3
   # MUST show 302 Location: https://<team>.cloudflareaccess.com/...
````

2. Local wmill CLI works:
   ```sh
   cd /Users/mrugesh/DEV/fCC-U/windmill && just drift 2>&1 | head -5
   # MUST exit 0 with no auth error
   ```
3. CF R2 admin creds present:
   ```sh
   test -f /Users/mrugesh/DEV/fCC/infra-secrets/do-primary/cloudflare.secrets.env.enc && echo OK
   ```

If any check fails, STOP and surface to operator. Do not work around.

## Execute in order — TDD mandated (RED-GREEN-REFACTOR)

Follow the Agent Prompt section of the beads DESIGN block verbatim. Summary:

1. **Read existing conventions** — `f/github/create_repo.ts`,
   `__mocks__/windmill-client.ts`. Identify: Resource pattern, error-handling
   convention, logging convention.
2. **Step 2 — RED tests first.** Create
   `workspaces/platform/f/static/provision_site_r2_credentials.test.ts`. Test
   cases per beads DESIGN + RFC §4.2.4:
   - mints R2 token with path condition `gxy-cassiopeia-1/<site>.freecode.camp/*`
   - stores creds as **repo-scope** Woodpecker secret (not org-scope — assert
     endpoint URL)
   - rejects site names with `--` (D19)
   - idempotent: rotating existing token works without duplicate
   - CF API failure → no partial Woodpecker write (atomicity)
3. **Step 3 — GREEN.** Write
   `workspaces/platform/f/static/provision_site_r2_credentials.ts`. Inject
   `fetchFn` to enable testing without real CF/Woodpecker calls.
4. **Step 4 — Flow metadata.** Generate `provision_site_r2_credentials.yaml`
   via `wmill generate-metadata`. Do NOT hand-write.
5. **Step 5 — Resources wiring.** Register the
   `woodpecker_admin_token_launchbase` + `cf_api_r2_provision` resources in
   `workspaces/platform/resources/` (follow existing resource pattern, do not
   invent new).
6. **Step 6 — Sops integration.** Write R2 creds into
   `../infra-secrets/cassiopeia/sites/<site>.secrets.env.enc` via sops. The
   sops write path is new — reference RFC §309. Use subprocess argv, NOT shell
   interpolation (memory: feedback_wrapper_argv_not_shell.md).
7. **Step 7 — Preview run.** Use Windmill MCP
   `runScriptPreviewAndWaitResult` against a test site name (e.g.,
   `hello-world`). Verify Woodpecker secret appears under
   `https://woodpecker.freecodecamp.net/repos/<repo>/settings/secrets` (via CLI
   or API, not UI).
8. **Step 8 — vitest green, oxlint clean, oxfmt clean.**
9. **Step 9 — `just drift` shows only the new file set, no deletions.** If
   deletions appear, STOP — memory feedback `feedback_wmill_sync_no_op_deletions.md`
   applies. Trust drift, not push log.

## Acceptance criteria (verbatim from beads)

- GIVEN site name `foo` WHEN flow runs THEN CF R2 token minted with
  `allowed_paths: ["gxy-cassiopeia-1/foo.freecode.camp/*"]`
- Woodpecker secret endpoint ends with `/repos/<id>/secrets`, NOT `/orgs/<id>/secrets`
- Flow is idempotent — running twice yields the same final state
- Site name with `--` is rejected before any CF/Woodpecker calls
- vitest all green
- Preview-run produces the expected R2 + Woodpecker state visible via CLI

## TDD — write tests first

No implementation commits without a failing test first. If you catch yourself
writing `.ts` (not `.test.ts`) without a preceding failing assertion, STOP and
go back. (feedback: `feedback_local_test_first.md`.)

## Constraints

- Do NOT use shell string interpolation to pass user data; argv only.
- Do NOT read `.env` files — all secrets via existing resource patterns.
- Do NOT push to origin; prepare commit only.
- Do NOT dismiss `just drift` deletion warnings. If you see deletions, stop
  and surface them.
- Test file extension `.test.ts`, not `.spec.ts` (repo convention).
- Vitest + mocked windmill-client only; no live CF/Woodpecker calls in tests.

## Docs to update (same session, after code green)

1. **Field notes — Universe repo** (cross-repo write; requires `--add-dir`):
   `/Users/mrugesh/DEV/fCC-U/Universe/spike/field-notes/windmill.md`
   Append a `### Per-site R2 secret flow landed (2026-04-20)` subsection
   with: flow path, test coverage %, preview-run outcome, CF R2 API
   surprises, sops write-path pattern learned, anything non-obvious.
2. **Flight manual — windmill repo**:
   `/Users/mrugesh/DEV/fCC-U/windmill/docs/FLIGHT-MANUAL.md` (create if
   absent). Add or update the "Per-site R2 provisioning" section with the
   wmill CLI recipe to invoke the flow for a new site.
3. **Local project docs**:
   - `workspaces/platform/README.md` — link to the new flow if a flow index
     exists there.
   - windmill-side field notes if the repo carries its own (most work now
     lives in Universe's windmill.md per ownership).

## Output expected back to operator

1. Files created + modified (by repo)
2. `vitest run` output (paste short summary)
3. `just drift` output
4. Preview-run result (Woodpecker secret URL + timestamp)
5. Proposed Conventional Commits message per repo (windmill + Universe)
6. "T11 ready to close" signal

## Commit policy

Prepare commits; do NOT push. Operator runs `/cmd-git-rules` before commit.

## When stuck

- If R2 token schema differs from the RFC (CF deprecates `allowed_paths`), flag
  and ask — do not invent. Check Cloudflare docs via
  `mcp__plugin_context7_context7__resolve-library-id` + `query-docs`.
- If `runScriptPreviewAndWaitResult` returns a schema-mismatch error, the flow
  metadata is stale — regenerate via `wmill generate-metadata` and retry.
- Path `/Users/mrugesh/DEV/fCC/windmill` is WRONG (cross-repo drift finding).
  Canonical is `/Users/mrugesh/DEV/fCC-U/windmill` (current cwd). If any
  reference uses the wrong path, flag it.

```

---

## Hand-off

When T11 closes, unblock:

- [06-infra-T15.md](06-infra-T15.md) (can now also start via T21 track)
- [08-universe-T28.md](08-universe-T28.md) (Phase 1-2 field notes)
```
