# Woodpecker CI — GitHub OAuth App Provisioning Runbook

**Type:** ClickOps (GitHub UI) — one-time per Woodpecker deployment.
**Prerequisite for:** [`08-woodpecker-cf-access.md`](08-woodpecker-cf-access.md) — DNS + CF Access. The OAuth app's Callback URL requires the DNS record to resolve before end-to-end login flow works. The OAuth app can be _provisioned_ independently; it only exercises the flow after DNS lands.

---

## Blast radius (CRITICAL — read first)

The OAuth app grants the `repo`, `read:org`, and `user:email` scopes. `repo`
is broad — full r/w to every private repo the authorizing user can access in
the `freeCodeCamp-Universe` org. Compensating controls:

1. Cloudflare Access on `woodpecker.freecodecamp.net` with email OTP
   restricted to the platform-team group (enforced by the CF Access runbook
   before the OAuth flow is exposed to the general operator population).
2. Woodpecker server runs in a namespace with a restrictive
   CiliumNetworkPolicy (`manifests/base/cilium-netpol.yaml`) — egress only
   to api.github.com, \*.r2.cloudflarestorage.com, api.cloudflare.com, DNS.
3. Admin OAuth sessions must use 2FA at the GitHub org level (enforced in
   `freeCodeCamp-Universe` org settings).
4. Target end state: migrate to a GitHub App with fine-grained per-repo
   permissions (post-MVP).

Authorize this app ONLY after the CF Access runbook has gated the domain.

---

## Prerequisites

- GitHub organization owner on `freeCodeCamp-Universe`.
- sops+age configured locally; `infra-secrets/` repo checked out as a sibling
  of `infra/` (see [`04-secrets-decrypt.md`](04-secrets-decrypt.md)).
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
   | **Application description**    | `Woodpecker CI for Universe constellations. Platform-team access only; see runbook 07-woodpecker-oauth-app.` |
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

Only after CNPG + postgres Cluster has been applied and is healthy:

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

### 5. Smoke test (deferred — requires DNS + Access)

End-to-end GitHub OAuth login requires:

- DNS A record for `woodpecker.freecodecamp.net`
- Cloudflare Access application gating the domain

(See [`08-woodpecker-cf-access.md`](08-woodpecker-cf-access.md).)

Until the DNS + Access steps land, the OAuth app is provisioned but the
login flow is not exercisable externally. An operator CAN verify internal
reachability:

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
- [ ] Smoke login (GitHub OAuth through browser) deferred to DNS + CF Access landing.
