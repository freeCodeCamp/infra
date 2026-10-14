# Runbook — Decrypt sops-encrypted secrets

**Type:** Operator-local · read-only. **Owners:** Infra team. **Last verified:** 2026-10-14, sops 3.13.3.

Single-purpose: decrypt one of the `*.env.enc` / `*.yaml.enc` envelopes under `../infra-secrets/` for inspection or for use in the environment of a command. sops selects the format from the last file extension. For `.enc` it uses the JSON parser, which fails on these envelopes. Always pass the type flags.

## Preconditions

- `../infra-secrets/` checked out at the canonical relative path (consumed by root `.envrc`).
- Operator host has the org age key in `$XDG_CONFIG_HOME/sops/age/keys.txt` when `XDG_CONFIG_HOME` is set, otherwise `~/Library/Application Support/sops/age/keys.txt` (macOS) or `~/.config/sops/age/keys.txt` (Linux).
- `sops` ≥ 3.9 on `PATH`. The `decrypt` subcommand starts at 3.9.0.

Check: `sops --version && age --version`.

## Steps

### 1. dotenv envelopes (`*.env.enc`)

```bash
sops decrypt --input-type dotenv --output-type dotenv \
  ../infra-secrets/<scope>/<name>.env.enc
```

### 2. YAML envelopes (`*.yaml.enc`)

Examples: `docker/oldeworld/pxy-upstreams-prd.yaml.enc`, `k3s/ops-backoffice-tools/kubeconfig.yaml.enc`.

```bash
sops decrypt --input-type yaml --output-type yaml \
  ../infra-secrets/<scope>/<name>.yaml.enc
```

### 3. Run commands with the secrets in the environment (dotenv only)

```bash
(
  set -eu
  secrets=$(sops decrypt --input-type dotenv --output-type dotenv \
    ../infra-secrets/<scope>/<name>.env.enc)
  while IFS= read -r line; do
    case $line in '' | '#'*) continue ;; esac
    export "$line"
  done <<< "$secrets"
  <command-that-reads-the-env>
)
```

- The parentheses run a subshell. The secrets are not in your shell after the command.
- `set -eu` stops the subshell before the command if the decrypt fails.
- `export "$line"` keeps each value as it is. A value with `&`, `$`, a space or a quote is safe.
- This works in zsh and bash.

## Rollback

Read-only operation. Nothing to roll back.

## Exit criteria

- Plaintext content matches expectations (vars / keys present).
- No `Could not unmarshal input data` error in stderr.
- Clipboard / scrollback cleared after inspection.

## Pitfalls

- **No `sops decrypt` without the type flags on an `.enc` file.** sops uses the JSON parser and fails with `Could not unmarshal input data`.
- **Do not `source` the decrypted output.** The shell parses each value, so a value with `&`, `$` or a space breaks the parse. The command after it runs with missing values.
- **Do not use `sops exec-env` on `.env.enc`.** In sops 3.13.3, `exec-env` has no `--input-type` flag, so it cannot read a dotenv envelope.
- **`.sops.yaml` cannot set the type.** sops 3.13.3 creation rules have no `input_type` key, so the flags stay required.

## References

- `infra/CLAUDE.md` §infra-secrets coupling.
