# Woodpecker on gxy-launchbase — post-T10 operator checklist

Use this after the Woodpecker chart is deployed (T10 closed) and before
announcing the service as available.

---

## 0. Preconditions

- [ ] `kubectl -n woodpecker get pods` — server 1/1, both agents 1/1,
      both postgres replicas 1/1, no CrashLoopBackOff.
- [ ] `kubectl -n woodpecker get cluster woodpecker-postgres` — 2/2 healthy.
- [ ] `docs/runbooks/woodpecker-oauth-app.md` exit criteria all ticked.

## 1. DNS + Access (T32)

Follow `docs/runbooks/woodpecker-cf-access.md` end-to-end.

- [ ] CF Access app created FIRST.
- [ ] DNS A records published (three launchbase IPs, proxied).
- [ ] `curl -sI https://woodpecker.freecodecamp.net` returns 302 to
      `*.cloudflareaccess.com`.
- [ ] Browser smoke — email OTP → GitHub OAuth → admin menu visible.

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
