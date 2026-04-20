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
