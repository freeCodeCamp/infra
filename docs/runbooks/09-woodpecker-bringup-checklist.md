# Woodpecker on gxy-launchbase — Post-deploy checklist + secrets reference

Run this after the Woodpecker chart is deployed and before announcing the
service as available.

**Pairs with:**

- [`07-woodpecker-oauth-app.md`](07-woodpecker-oauth-app.md) — OAuth app provisioning
- [`08-woodpecker-cf-access.md`](08-woodpecker-cf-access.md) — DNS + CF Access

---

## 0. Preconditions

- [ ] `kubectl -n woodpecker get pods` — server 1/1, both agents 1/1,
      both postgres replicas 1/1, no CrashLoopBackOff.
- [ ] `kubectl -n woodpecker get cluster woodpecker-postgres` — 2/2 healthy.
- [ ] OAuth app exit criteria all ticked
      (see [`07-woodpecker-oauth-app.md`](07-woodpecker-oauth-app.md)).

## 1. DNS + TLS + auth

Current posture — Cloudflare Access is **off**; auth is the GitHub-org gate
(`WOODPECKER_ORGS=freeCodeCamp-Universe`, `WOODPECKER_OPEN=true`). CF Access
runbook [`08-woodpecker-cf-access.md`](08-woodpecker-cf-access.md) is
preserved for re-enable.

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

Update via the sops overlay (see [`08-woodpecker-cf-access.md`](08-woodpecker-cf-access.md) §Admin list).

## 3. Agent connectivity

```
kubectl -n woodpecker logs -l app.kubernetes.io/component=agent --tail=30
```

- [ ] Each agent logs `successfully connected to grpc server`.
- [ ] No repeating `WOODPECKER_AGENT_SECRET` mismatch errors.

## 4. First repo onboarded

In the Woodpecker UI, as admin:

- [ ] Repos listing shows the `freeCodeCamp-Universe` org.
- [ ] Enable one low-risk repo (e.g. `hello-universe` or `infra` itself)
      to produce a canary pipeline.
- [ ] Push a trivial commit, confirm the pipeline runs in an agent pod
      (`kubectl -n woodpecker get pods -w` shows a short-lived job pod).

## 5. Backup re-attach (deferred)

The Postgres `Cluster` CR was bootstrapped without `spec.backup` because
the native `barmanObjectStore` field is deprecated (CNPG ≥ 1.26) and
deadlocked the fresh cluster on `restore_command`. The plugin-based
replacement is parked.

- [ ] Until the plugin-based path lands, schedule a weekly `pg_dump` export
      to R2 as a belt-and-braces fallback (separate operator task).

## 6. Image provenance

Woodpecker's own `.woodpecker/caddy-s3-build.yaml` pipeline tags and pushes
the caddy-s3 image. As of this runbook, `gxy-cassiopeia` runs a locally
built `dev-*` tag. The follow-up is to move that pipeline to GitHub Actions
— see TODO-park before touching the Woodpecker `.woodpecker/` workflows.

## 7. Observability (deferred)

- [ ] Cloudflare Access → Logs panel shows the operator's login event.
- [ ] gxy-backoffice o11y stack (ADR-015) is out of scope here; once live,
      wire `woodpecker.freecodecamp.net` request metrics + the
      `woodpecker-server` logs into it.

---

# Required secrets reference

All secrets live in `../infra-secrets` (sops+age) and are decrypted automatically
by the `just deploy gxy-launchbase woodpecker` and `just helm-upgrade
gxy-launchbase woodpecker` recipes. See
[`04-secrets-decrypt.md`](04-secrets-decrypt.md) for the canonical sops
incantation.

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
