# T15 Phase 4 smoke — pre-flight report (2026-04-25)

**Status:** working doc, NOT a sprint deliverable. Captures pre-flight
findings before any `just phase4-smoke` invocation. Promote to runbook
amendment / dispatch closure once operator-bootstrap gap closed.

**Context:** operator asked to run all read-only verifications before
mutating commands. Halt + handover. This file records the halt state.

---

## Cluster + edge state — GREEN

| Check                                          | Result | Evidence                                                                                                                            |
| ---------------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| Cassiopeia droplets active                     | 3/3    | `doctl compute droplet list --tag-name gxy-cassiopeia-k3s`: k3s-1 `165.227.149.249`, k3s-2 `46.101.179.141`, k3s-3 `188.166.165.62` |
| Caddy alive on every node                      | 3/3    | `curl -H "Host: test.freecode.camp" http://<node-ip>/` → `404 server=Caddy` (expected pre-smoke — alias not yet written)            |
| DNS resolves                                   | 2/2    | `dig +short test.freecode.camp` + `test.preview.freecode.camp` → CF anycast `104.21.17.127`, `172.67.176.196`                       |
| CF edge serves                                 | 2/2    | `curl https://test.freecode.camp/` → `404 cloudflare cf-cache=DYNAMIC` (Caddy-origin, not CF cache)                                 |
| Static-contract suite                          | green  | `just phase4-smoke-test` → `OK: phase4-test-site-smoke.sh contract satisfied`                                                       |
| `shellcheck scripts/phase4-test-site-smoke.sh` | clean  | exit 0                                                                                                                              |
| `bash -n scripts/phase4-test-site-smoke.sh`    | clean  | exit 0                                                                                                                              |
| `just --unstable --fmt --check`                | clean  | exit 0                                                                                                                              |

Origin chain healthy. CF DNS already in place (likely added during
prior bootstrap; not a fresh add for this run).

---

## Operator-environment state — RED (5 unmet prereqs)

### B1. `infra-secrets/k3s/gxy-cassiopeia/.env.enc` — file does not exist

Runbook §Required-environment maps R2 r/w creds (`AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `R2_ENDPOINT`) to this path. Directory listing:

```
infra-secrets/k3s/gxy-cassiopeia/
├── caddy.values.yaml.enc
└── caddy.values.yaml.sample
```

Only Caddy Helm values seeded. No dotenv-encrypted file with R2
operator creds. Smoke script will fail at first env guard (`R2_ENDPOINT`).

### B2. `k3s/gxy-cassiopeia/.envrc` does not export `R2_BUCKET`

Current content:

```bash
source_env ../../.envrc
if [ -d "$SECRETS_DIR" ]; then
  use_sops "$SECRETS_DIR/do-universe/.env.enc"
fi
export KUBECONFIG="$(expand_path .kubeconfig.yaml)"
dotenv_if_exists .env
```

No `export R2_BUCKET=universe-static-apps-01`. No `use_sops` call for
cassiopeia-scoped secrets. Runbook claims this var lives here.

### B3. `CF_API_TOKEN` + `CF_ZONE_ID` — name + presence drift

Runbook says: read `CF_API_TOKEN` + `CF_ZONE_ID` from `infra-secrets/global/.env.enc`.

Reality (`infra-secrets/global/.env.sample`):

```
CLOUDFLARE_API_TOKEN=
LINODE_API_TOKEN=
```

`CF_API_TOKEN` not present (name is `CLOUDFLARE_API_TOKEN`).
`CF_ZONE_ID` absent entirely.

### B4. rclone `r2:` remote not configured

```
2026/04/25 23:02:00 CRITICAL: Failed to create file system for
"r2:universe-static-apps-01/": didn't find section in config file ("r2")
```

`~/.config/rclone/rclone.conf` lacks an `[r2]` section. Smoke script
calls `rclone copy`, `rclone purge`, `rclone lsf` — all fail without
it. No bootstrap step or recipe creates this remote.

### B5. kubectl context absent (informational)

`kubectl config get-contexts` returns header-only — no gxy-cassiopeia
entry. Smoke script does not invoke kubectl, so not strictly blocking,
but failure-path diagnosis (`kubectl -n caddy logs ...`) requires it.

---

## Verification commands run (read-only)

```bash
doctl compute droplet list --tag-name gxy-cassiopeia-k3s --format Name,PublicIPv4,Status
kubectl config get-contexts
dig +short test.freecode.camp
dig +short test.preview.freecode.camp
just phase4-smoke-test
shellcheck scripts/phase4-test-site-smoke.sh
bash -n scripts/phase4-test-site-smoke.sh
just --unstable --fmt --check
curl -sS -H "Host: test.freecode.camp" "http://<each-node-ip>/"
curl -sS https://test.freecode.camp/ ; curl -sS https://test.preview.freecode.camp/
direnv exec k3s/gxy-cassiopeia sh -c '<env-var presence checks>'
direnv exec k3s/gxy-cassiopeia rclone lsf "r2:universe-static-apps-01/" --max-depth 1
direnv exec k3s/gxy-cassiopeia sh -c 'curl -sS -H "Authorization: Bearer ${CF_API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=test.freecode.camp"'
test -f infra-secrets/k3s/gxy-cassiopeia/.env.enc
test -f k3s/gxy-cassiopeia/.envrc
cat infra-secrets/global/.env.sample
cat infra-secrets/do-universe/.env.sample
```

No mutations. No rclone `copy` / `purge`. No alias writes. No CF DNS
edits. No commit besides the sprint-doc roll already pushed in
`73d4d19`.

---

## Operator action queue (handover)

1. Seed `infra-secrets/k3s/gxy-cassiopeia/.env.enc` with R2 r/w API
   creds + endpoint (mint a scoped CF R2 token via
   `r2-bucket-verify` recipe + sops-encrypt under platform age recipient).
2. Patch `k3s/gxy-cassiopeia/.envrc`:
   - add `use_sops "$SECRETS_DIR/k3s/gxy-cassiopeia/.env.enc"`
   - add `export R2_BUCKET=universe-static-apps-01`
3. Resolve CF token name drift: rename in global to `CF_API_TOKEN` +
   add `CF_ZONE_ID`, OR patch smoke script + runbook to use existing
   `CLOUDFLARE_API_TOKEN`. Decision belongs in DECISIONS.md amendment.
4. Configure rclone `r2:` remote — either user-scope `rclone.conf`
   provider entry, OR justfile recipe that injects inline `--s3-*`
   flags from env vars (preferred — keeps secret out of dotfile).
5. Pull cassiopeia kubeconfig into `~/.kube/config` (optional, for
   failure diagnosis).
6. Re-run pre-flight verifications post-fix (re-execute commands above).
7. Then `just phase4-smoke`.

---

## Runbook amendment owed

`docs/runbooks/phase4-test-site-smoke.md` §Required-environment table
misrepresents reality:

- `CF_API_TOKEN` source name doesn't match global samples
- `CF_ZONE_ID` source not provisioned anywhere
- `R2_BUCKET` not actually exported by referenced `.envrc`
- `infra-secrets/k3s/gxy-cassiopeia/.env.enc` referenced as if seeded;
  doesn't exist

Once operator closes B1–B4, runbook needs a single amendment commit
reflecting actual var locations + names. Cross-update T15 dispatch
closure with "post-bootstrap reality" delta.

---

## Open questions for root-cause audit (separate doc / discussion)

- Was a "Task 12: R2 bucket provision + cassiopeia operator-cred
  seed" ever scoped? Not in `#24 sub-task matrix` (PLAN.md L119–131).
  Runbook prerequisites section references "Task 12" — phantom citation?
- Where in the sprint should the **operator-environment-readiness**
  step have lived? G1.0 covered Windmill admin token; no equivalent
  G1.x exists for cassiopeia R2 rw.
- Why didn't T15 acceptance criteria exercise the live invocation
  path? (Answer: explicitly punted by closure — but punt was never
  re-collected as a follow-up dispatch.)
