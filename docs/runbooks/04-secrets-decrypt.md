# Runbook — Decrypt sops-encrypted secrets

**Type:** Operator-local · read-only.
**Owners:** Infra team (per `docs/GUIDELINES.md` doc-type matrix).
**Last verified:** 2026-04-27.

Single-purpose: decrypt one of the `*.env.enc` / `*.values.yaml.enc`
envelopes under `../infra-secrets/` for inspection or for sourcing into
a shell. Helm-rendering recipes and ops scripts MUST follow the dotenv
incantation — sops auto-detect on `.enc` falls back to the JSON parser
and silently fails on dotenv content.

## Preconditions

- `../infra-secrets/` checked out at the canonical relative path
  (consumed by root `.envrc`).
- Operator host has the org age key in
  `~/Library/Application Support/sops/age/keys.txt` (macOS) or
  `~/.config/sops/age/keys.txt` (Linux).
- `sops` ≥ 3.8 on `PATH`.

Check: `sops --version && age --version`.

## Steps

### 1. dotenv envelopes (`*.env.enc`)

Required flags. Auto-detect on `.enc` extension routes to JSON;
dotenv content trips
`Error unmarshalling input json: invalid character '#'`.

```bash
sops decrypt --input-type dotenv --output-type dotenv \
  ../infra-secrets/<scope>/<name>.env.enc
```

Justfile recipe equivalent (read-only, prints to stdout):

```bash
just secret-view <name>
```

### 2. Helm value overlays (`*.values.yaml.enc`)

YAML envelopes. Auto-detect works because sops reads `.yaml.enc`
correctly, but explicit flags keep the recipe-side invocation
uniform across types:

```bash
sops decrypt --input-type yaml --output-type yaml \
  ../infra-secrets/<scope>/<app>.values.yaml.enc
```

### 3. Source into a current shell (dotenv only)

```bash
set -a
source <(sops decrypt --input-type dotenv --output-type dotenv \
  ../infra-secrets/<scope>/<name>.env.enc)
set +a
```

Use sparingly — leaks secrets into the shell history if the
operator runs `env` afterwards. Prefer `sops exec-env` for one-off
commands:

```bash
sops exec-env --input-type dotenv --output-type dotenv \
  ../infra-secrets/<scope>/<name>.env.enc \
  '<command-that-reads-the-env>'
```

## Rollback

Read-only operation. Nothing to roll back.

## Exit criteria

- Plaintext content matches expectations (vars / keys present).
- No `invalid character '#'` JSON-parser error in stderr.
- Clipboard / scrollback cleared after inspection.

## Pitfalls

- **No bare `sops decrypt` on `.env.enc`.** Auto-detect routes to JSON
  → cryptic parse error. Always pass `--input-type dotenv
--output-type dotenv`.
- **Helm chart secret-rendering recipes** in the justfile MUST pass
  both flags. Rendering scripts in `scripts/` likewise.
- **Per-glob `input_type: dotenv` pin in `.sops.yaml`** would remove
  the need for explicit flags but is deferred — the current
  `.sops.yaml` rules block has no per-path type config.

## References

- `docs/GUIDELINES.md` §Runbook format
- Field-note origin: `infra/CLAUDE.md` §infra-secrets coupling (now
  pointer-only).
