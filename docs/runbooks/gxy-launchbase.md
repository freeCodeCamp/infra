# Woodpecker CF Access
# Woodpecker CI — DNS + Cloudflare Access Runbook

**Task:** T32 (`gxy-static-k7d.33`)
**Paired with:** `docs/runbooks/woodpecker-oauth-app.md` (T10 — OAuth provisioning)
**Type:** ClickOps (Cloudflare dashboard) — one-time per Woodpecker deployment.
**Prerequisites closed:** T10 (OAuth app + chart) — this runbook only exposes the service.

---

## Current posture (2026-04-20)

**Cloudflare Access is OFF for this deployment.** Login is gated by the
GitHub-org membership check (`WOODPECKER_ORGS=freeCodeCamp-Universe`,
`WOODPECKER_OPEN=true` for self-register) — that is considered sufficient
for letting staff in without an extra OTP layer. The DNS + Origin TLS
sections below are already reflected in the live cluster.

This runbook is preserved as the authoritative procedure for re-enabling
CF Access (e.g. if the gate needs to narrow below the org — team-level or
email-domain — which Woodpecker alone cannot express). Follow the Access
application section when you re-enable it.

---

## Blast radius (CRITICAL — read first)

Two things this runbook does are each hard to reverse on the fly:

1. **DNS publication.** Once `woodpecker.freecodecamp.net` resolves, every
   request to that hostname lands on the gxy-launchbase Traefik ingress.
   Access gating MUST be in place _before_ the A records propagate — the
   order in this runbook is DNS last.
2. **Access policy.** Misconfiguring the policy (wrong group, wrong
   identity provider) can either lock out every operator OR leave the app
   open to anyone with an email address. Double-check the identity provider
   binding and the group/email allow-list against the T10 runbook.

The Woodpecker admin surface is broad: push to private repos via GitHub
OAuth, trigger arbitrary pipelines, exfiltrate pipeline secrets. CF Access
is the primary control. If you are not 100% sure of the policy, STOP and
ask the platform-team lead.

---

## Prerequisites

- T10 closed — OAuth app provisioned, chart deployed, server + agent Ready.
- Cloudflare account on `freecodecamp.net` zone with `Zero Trust` → `Access`
  enabled.
- Launchbase node public IPs on hand. Get them with:

  ```
  doctl compute droplet list --tag-name gxy-launchbase-k3s \
    --format Name,PublicIPv4
  ```

  As of 2026-04-20: `68.183.215.167 / 68.183.221.232 / 165.245.220.145`.

- `WOODPECKER_HOST` already set to `https://woodpecker.freecodecamp.net`
  in the chart env (pre-set so that OAuth callbacks match the final hostname).

---

## Steps

### 1. Cloudflare Access application (do this FIRST, before DNS)

1. <https://one.dash.cloudflare.com> → select the freeCodeCamp account →
   **Access** → **Applications** → **Add an application**.
2. Type: **Self-hosted**.
3. Basic config:

   | Field              | Value                         |
   | ------------------ | ----------------------------- |
   | Application name   | `Woodpecker CI`               |
   | Session duration   | `24 hours`                    |
   | Application domain | `woodpecker.freecodecamp.net` |
   | Identity providers | One-time PIN (email OTP)      |
   | App launcher URL   | (leave default)               |

4. Policy — **Add a policy**:

   | Field            | Value                            |
   | ---------------- | -------------------------------- |
   | Policy name      | `platform-team allowed`          |
   | Action           | `Allow`                          |
   | Session duration | Same as application (24 h)       |
   | Include          | Emails in group: `platform-team` |
   | Require          | (none)                           |
   | Exclude          | (none)                           |

   If the `platform-team` group does not yet exist under **Access → Groups**,
   create it with the operator emails BEFORE saving the policy. Do NOT use
   an "Everyone" allow — the OAuth app behind this grants broad repo access.

5. Leave HTTP settings, advanced settings, and CORS at defaults.
6. Save.

### 2. Cloudflare DNS (AFTER step 1 is saved)

Under zone `freecodecamp.net`:

- [ ] A record: `woodpecker.freecodecamp.net` → `68.183.215.167` — Proxy ON
- [ ] A record: `woodpecker.freecodecamp.net` → `68.183.221.232` — Proxy ON
- [ ] A record: `woodpecker.freecodecamp.net` → `165.245.220.145` — Proxy ON
- [ ] TTL: Auto
- [ ] Proxy: Proxied (orange cloud) on all three
- [ ] SSL / TLS mode for zone: Full (Strict) — already set zone-wide; verify

Cloudflare will round-robin across the three A records at the edge.

### 3. Verify DNS (may take 60–120 s to propagate)

```
dig +short woodpecker.freecodecamp.net
# Expect: two CF anycast IPs (usually 104.x.x.x or 172.64.x.x).
# CF masks the origin A records; you will NOT see the droplet IPs here.
```

### 4. Verify Access gate

```
curl -sI https://woodpecker.freecodecamp.net | head -5
```

Expected:

```
HTTP/2 302
location: https://<team>.cloudflareaccess.com/cdn-cgi/access/login/...
set-cookie: CF_Authorization=...
cf-ray: ...
```

The `302` to `cloudflareaccess.com` is the whole point — it proves Access
is in front of the origin. If you instead see the Woodpecker login page,
the Access application domain is misconfigured — revisit step 1.

### 5. End-to-end smoke (operator, browser)

1. In a private window: <https://woodpecker.freecodecamp.net>.
2. Expect CF Access email OTP challenge.
3. Enter an allowed email → enter the code.
4. Expect redirect to Woodpecker + GitHub OAuth prompt.
5. Authorize with an admin GitHub account listed in `WOODPECKER_ADMIN`.
6. Expect the Woodpecker dashboard with admin menu visible.

Record the outcome in the field-notes entry described in
`docs/sprint/2026-04-20/01-infra-T32.md` §Docs.

---

## Exit criteria

- [ ] CF Access app `Woodpecker CI` live, scoped to `platform-team`.
- [ ] Three A records published, proxied, SSL Full (Strict).
- [ ] `curl -sI` returns 302 to `*.cloudflareaccess.com`.
- [ ] Admin completes the email-OTP + GitHub-OAuth login.
- [ ] Admin sees the admin menu (confirms `WOODPECKER_ADMIN` matches).

When all five hold, close T32 via beads.

---

## Rollback

If the gate is misconfigured and you need to pull the domain fast:

1. CF dashboard → zone `freecodecamp.net` → DNS → delete all three A
   records for `woodpecker`. Propagation is near-immediate on CF.
2. Do NOT disable the Access app first — that would drop the gate while
   DNS still resolves, briefly exposing the origin.
3. After DNS is gone, you may delete or reconfigure the Access app.

---

## Admin list

`WOODPECKER_ADMIN` and `WOODPECKER_ORGS` live in
`infra-secrets/k3s/gxy-launchbase/woodpecker.values.yaml.enc` and are read
into the chart via the sops overlay (see justfile `helm-upgrade` recipe).

Change the admin list:

```
cd ../infra-secrets
sops k3s/gxy-launchbase/woodpecker.values.yaml.enc
# edit server.env.WOODPECKER_ADMIN (comma-separated GitHub usernames)
git add k3s/gxy-launchbase/woodpecker.values.yaml.enc
git commit -m "chore(gxy-launchbase/woodpecker): update admin list"
cd -
just helm-upgrade gxy-launchbase woodpecker
kubectl -n woodpecker rollout restart statefulset/woodpecker-server
```


# Woodpecker OAuth App
# Woodpecker CI — GitHub OAuth App Provisioning Runbook

**Task:** T10 (`gxy-static-k7d.11`)
**Spec:** `docs/rfc/gxy-cassiopeia.md` §4.2.3
**Type:** ClickOps (GitHub UI) — one-time per Woodpecker deployment.

**Prerequisite for:** T32 (DNS + CF Access) — the OAuth app's Callback URL
requires the DNS record to resolve before end-to-end login flow works. The
OAuth app can be _provisioned_ independently; it only exercises the flow
after T32.

---

## Blast radius (CRITICAL — read first)

The OAuth app grants the `repo`, `read:org`, and `user:email` scopes. `repo`
is broad — full r/w to every private repo the authorizing user can access in
the `freeCodeCamp-Universe` org. Compensating controls per RFC §4.2.3:

1. Cloudflare Access on `woodpecker.freecodecamp.net` with email OTP
   restricted to the platform-team group (enforced by T32 before the OAuth
   flow is exposed to the general operator population).
2. Woodpecker server runs in a namespace with a restrictive CiliumNetworkPolicy
   (T10 `manifests/base/cilium-netpol.yaml`) — egress only to api.github.com,
   \*.r2.cloudflarestorage.com, api.cloudflare.com, DNS.
3. Admin OAuth sessions must use 2FA at the GitHub org level (enforced in
   `freeCodeCamp-Universe` org settings; verify in the M1 exit checklist).
4. Target end state: migrate to a GitHub App with fine-grained per-repo
   permissions (post-M5, RFC §14 Q8).

Authorize this app ONLY after T32 has gated the domain behind CF Access.

---

## Prerequisites

- GitHub organization owner on `freeCodeCamp-Universe`.
- sops+age configured locally; `infra-secrets/` repo checked out as a sibling
  of `infra/`.
- Decided Woodpecker server URL: `https://woodpecker.freecodecamp.net`.

---

## Steps

### 1. Create the OAuth App

1. Navigate to <https://github.com/organizations/freeCodeCamp-Universe/settings/applications>.
2. Click **New OAuth App**.
3. Fill in the fields:

   | Field                          | Value                                                                                                        |
   | ------------------------------ | ------------------------------------------------------------------------------------------------------------ |
   | **Application name**           | `Woodpecker CI — gxy-launchbase`                                                                             |
   | **Homepage URL**               | `https://woodpecker.freecodecamp.net`                                                                        |
   | **Application description**    | `Woodpecker CI for Universe constellations. Platform-team access only; see runbook woodpecker-oauth-app.md.` |
   | **Authorization callback URL** | `https://woodpecker.freecodecamp.net/authorize`                                                              |
   | **Enable Device Flow**         | Unchecked                                                                                                    |

4. Click **Register application**.

### 2. Generate the client secret

1. On the application page, click **Generate a new client secret**.
2. Copy both values — they are shown once.

| Secret        | Format                 |
| ------------- | ---------------------- |
| Client ID     | `Iv1.xxxxxxxxxxxxxxxx` |
| Client Secret | 40-char hex            |

### 3. Store in `infra-secrets`

```bash
cd ../infra-secrets/k3s/gxy-launchbase
cat > woodpecker.secrets.env <<EOF
WOODPECKER_AGENT_SECRET=$(openssl rand -hex 32)
WOODPECKER_SERVER_SECRET=$(openssl rand -hex 32)
WOODPECKER_GITHUB_CLIENT=<paste-client-id>
WOODPECKER_GITHUB_SECRET=<paste-client-secret>
EOF

sops -e -i --input-type dotenv --output-type dotenv woodpecker.secrets.env
mv woodpecker.secrets.env woodpecker.secrets.env.enc

git add woodpecker.secrets.env.enc
git commit -m "feat(gxy-launchbase): add Woodpecker OAuth + server secrets"
```

Never commit the unencrypted `.env` file. Verify via `just secret-verify-all`.

### 4. Apply to the cluster

Only after T09 (CNPG + postgres Cluster) has been applied and is healthy:

```bash
# Chart install / upgrade (creates the woodpecker-env Secret via kustomize + sops)
just deploy gxy-launchbase woodpecker       # applies namespace + Cluster + HTTPRoute + NP + Secret
just helm-upgrade gxy-launchbase woodpecker  # installs the server + agent

kubectl -n woodpecker rollout status statefulset/woodpecker-server --timeout=5m
kubectl -n woodpecker rollout status deploy/woodpecker-agent       --timeout=3m
```

Verification:

```bash
kubectl -n woodpecker get pods
kubectl -n woodpecker logs -l app.kubernetes.io/name=woodpecker-server --tail=50
# Expect: "Server is running on :8000" or equivalent; no OAuth errors.
```

### 5. Smoke test (deferred — requires T32)

End-to-end GitHub OAuth login requires:

- DNS A record for `woodpecker.freecodecamp.net` (T32)
- Cloudflare Access application gating the domain (T32)

Until T32 lands, the OAuth app is provisioned but the login flow is not
exercisable externally. An operator CAN verify internal reachability:

```bash
kubectl -n woodpecker port-forward svc/woodpecker-server 8000:8000
# In another terminal:
curl -s http://localhost:8000/healthz
# Expect: HTTP 200
```

### 6. Rotation (every 90 days)

1. GitHub OAuth app settings → Generate a new client secret.
2. Update `woodpecker.secrets.env.enc` in `infra-secrets` (sops).
3. `just deploy gxy-launchbase woodpecker` to regenerate the `woodpecker-env`
   Secret.
4. `kubectl -n woodpecker rollout restart statefulset/woodpecker-server
deploy/woodpecker-agent` — pods pick up the new credential on restart.
5. Revoke the old client secret on GitHub only AFTER rollout is Ready and a
   test OAuth login succeeds.

---

## Exit criteria

- [ ] OAuth app exists under `freeCodeCamp-Universe`.
- [ ] Client ID + secret stored sops-encrypted in `infra-secrets`.
- [ ] `just secret-verify-all` passes.
- [ ] Chart deployed; server + agent pods Ready.
- [ ] `kubectl port-forward` to server returns 200 on `/healthz`.
- [ ] Smoke login (GitHub OAuth through browser) deferred to T32 completion.

Only when the first five items hold, close T10:

```bash
bash -c 'source /Users/mrugesh/.claude/plugins/cache/dotplugins/dp-cto/8.0.4/lib/dp-beads.sh && dp_beads_close gxy-static-k7d.11 "completed: chart deployed; OAuth app provisioned; smoke login deferred to T32"'
```


# Post T10 Operator
# Woodpecker on gxy-launchbase — post-T10 operator checklist

Use this after the Woodpecker chart is deployed (T10 closed) and before
announcing the service as available.

---

## 0. Preconditions

- [ ] `kubectl -n woodpecker get pods` — server 1/1, both agents 1/1,
      both postgres replicas 1/1, no CrashLoopBackOff.
- [ ] `kubectl -n woodpecker get cluster woodpecker-postgres` — 2/2 healthy.
- [ ] `docs/runbooks/woodpecker-oauth-app.md` exit criteria all ticked.

## 1. DNS + TLS + auth (T32)

Current posture — Cloudflare Access is **off**; auth is the GitHub-org gate
(`WOODPECKER_ORGS=freeCodeCamp-Universe`, `WOODPECKER_OPEN=true`). CF Access
runbook `docs/runbooks/woodpecker-cf-access.md` is preserved for re-enable.

- [ ] Gateway `woodpecker-gateway` in the `woodpecker` namespace with both
      `:80` and `:443` listeners; `Programmed=True`.
- [ ] Secret `woodpecker-tls-cloudflare` present (built by kustomize
      secretGenerator from `manifests/base/secrets/tls.crt` + `tls.key`,
      i.e. the `*.freecodecamp.net` CF Origin Cert).
- [ ] DNS A records published (three launchbase IPs, proxied) on
      `woodpecker.freecodecamp.net`.
- [ ] `curl -sI https://woodpecker.freecodecamp.net` returns 200 (or 302
      to `*.cloudflareaccess.com` if CF Access was re-enabled).
- [ ] Browser smoke — GitHub OAuth with a `freeCodeCamp-Universe` member
      reaches the Woodpecker dashboard; admin handle (see §2) sees the
      admin menu.

## 2. Verify admin list matches reality

```
kubectl -n woodpecker get statefulset woodpecker-server \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WOODPECKER_ADMIN")].value}'
```

- [ ] Output is a comma-separated list matching the operator GitHub
      handles agreed with the platform-team lead.

Update via the sops overlay (see the CF Access runbook §Admin list).

## 3. Agent connectivity

```
kubectl -n woodpecker logs -l app.kubernetes.io/component=agent --tail=30
```

- [ ] Each agent logs `successfully connected to grpc server`.
- [ ] No repeating `WOODPECKER_AGENT_SECRET` mismatch errors.

## 4. First repo onboarded

In the Woodpecker UI, as admin:

- [ ] Repos listing shows the `freeCodeCamp-Universe` org.
- [ ] Enable one low-risk repo (e.g. `hello-universe` or
      `infra` itself) to produce a canary pipeline.
- [ ] Push a trivial commit, confirm the pipeline runs in an agent pod
      (`kubectl -n woodpecker get pods -w` shows a short-lived job pod).

## 5. Backup re-attach (T03b — deferred)

The Postgres `Cluster` CR was bootstrapped without `spec.backup` because
the native `barmanObjectStore` field is deprecated (CNPG >= 1.26) and
deadlocked the fresh cluster on `restore_command`. The plugin-based
replacement tracks as beads `gxy-static-k7d.TP03b`.

- [ ] Until T03b closes, schedule a weekly `pg_dump` export to R2 as a
      belt-and-braces fallback (separate operator task — file under
      `infra.ops.backup.weekly-dump` if the platform-team lead asks).

## 6. Image provenance

Woodpecker's own `.woodpecker/caddy-s3-build.yaml` pipeline tags and pushes
the caddy-s3 image. As of this runbook, `gxy-cassiopeia` runs a locally
built `dev-*` tag (beads `gxy-static-k7d.35`). The follow-up is to move
that pipeline to GitHub Actions — see that beads record before touching
the Woodpecker `.woodpecker/` workflows.

## 7. Observability (deferred)

- [ ] Cloudflare Access → Logs panel shows the operator's login event.
- [ ] gxy-backoffice o11y stack (ADR-015) is out of scope for T32; once
      live, wire `woodpecker.freecodecamp.net` request metrics + the
      `woodpecker-server` logs into it.

---

## Close T32

Only when items 1-4 are all checked, close the beads issue
`gxy-static-k7d.33` via the `dp_beads_close` wrapper (see
`lib/dp-beads.sh` under the dp-cto plugin). Then run the orchestrator's
next-dispatch command (see MASTER.md).


# Secrets
# Woodpecker — Required Secrets

All secrets live in `../infra-secrets` (sops+age) and are decrypted automatically
by the `just deploy gxy-launchbase woodpecker` and `just helm-upgrade
gxy-launchbase woodpecker` recipes.

## `infra-secrets/k3s/gxy-launchbase/woodpecker-backup.secrets.env.enc`

Dotenv format. Decrypted into `manifests/base/secrets/.backup-secrets.env` at
deploy time. Consumed by the `secretGenerator` in
`manifests/base/kustomization.yaml` to produce the
`woodpecker-postgres-s3-backup` Secret used by CNPG's barman-cloud backups.

Required keys:

```
ACCESS_KEY_ID=<DO Spaces key ID>
SECRET_ACCESS_KEY=<DO Spaces secret>
```

The DO Spaces key should be scoped to `net-freecodecamp-universe-backups` only
(same bucket as etcd snapshots, different prefix `cnpg/gxy-launchbase/...`).
Rotation: every 90 days, mint new DO Spaces key in the DO console, update the
sops file, `just deploy gxy-launchbase woodpecker`.

## `infra-secrets/k3s/gxy-launchbase/woodpecker.secrets.env.enc`

Dotenv format. Decrypted into `manifests/base/secrets/.secrets.env` at deploy
time. Holds Woodpecker chart secrets: `WOODPECKER_SERVER_SECRET`,
`WOODPECKER_AGENT_SECRET`, GitHub OAuth app ID/secret. The database URL
comes from the CNPG-generated `woodpecker-postgres-app` secret.

## `infra-secrets/k3s/gxy-launchbase/woodpecker.values.yaml.enc`

Optional Helm values overlay for the Woodpecker chart install.

## Verification

After bootstrap, `kubectl -n woodpecker get secrets` should list (at minimum):

- `woodpecker-postgres-app` (generated by CNPG — app user credentials)
- `woodpecker-postgres-ca` (generated by CNPG — internal TLS)
- `woodpecker-postgres-replication` (generated by CNPG — replication user)
- `woodpecker-postgres-server` (generated by CNPG — server TLS)
- `woodpecker-postgres-s3-backup` (generated by kustomize secretGenerator)
