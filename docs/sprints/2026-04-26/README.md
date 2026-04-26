# Sprint 2026-04-26 — Universe Static-Apps Proxy Pillar

**Goal:** staff dev runs `universe deploy` from any environment (laptop, GHA, Woodpecker) → site live on `<site>.freecode.camp`. Zero R2 tokens in staff hands or CI secrets. Identity = GitHub team membership. Upload plane = Go microservice at `uploads.freecode.camp`.

## Read order (every fresh session)

1. **[`STATUS.md`](STATUS.md)** — live cursor. Shipped / Open / Other state / Resume prompt. Read first.
2. **[`PLAN.md`](PLAN.md)** — sprint goal, phases + gates, sub-task matrix, dispatch graph, success criteria, invariants.
3. **[`DECISIONS.md`](DECISIONS.md)** — D43 + locked Q9–Q15 from D016 cross-ref.
4. **[`HANDOFF.md`](HANDOFF.md)** — append-only history log.
5. **[`dispatches/`](dispatches/)** — per-task briefs (T22, T30–T34).

## Layout

```
docs/sprints/2026-04-26/
├── README.md         — this file
├── STATUS.md         — live cursor (rewritten each session-roll)
├── PLAN.md           — stable plan
├── DECISIONS.md      — locked decisions
├── HANDOFF.md        — append-only history log
├── reports/          — audits + reports (created lazily)
└── dispatches/
    ├── T22-cleanup-cron.md           — windmill (post-T31 live)
    ├── T30-d016-deploy-proxy-adr.md  — Universe (cross-repo)
    ├── T31-uploads-service.md        — new repo `~/DEV/fCC-U/uploads`
    ├── T32-cli-v04-rewrite.md        — universe-cli `feat/proxy-pivot`
    ├── T33-platform-yaml-v2.md       — universe-cli `feat/proxy-pivot`
    └── T34-caddy-dns-smoke.md        — infra
```

## Predecessor

This sprint opens at the branch point of [`../archive/2026-04-21/`](../archive/2026-04-21/). That sprint shipped Wave A.1 (Caddy `r2_alias` D35 dot-scheme + R2 single-bucket layout + Phase 4 smoke harness). Wave A.3 (T11 per-site R2 token mint) was SUPERSEDED by D016 deploy-proxy plane (logged in archived sprint `HANDOFF.md` 2026-04-26 evening + this sprint `DECISIONS.md` D43).

## Authority model

**Broken ownership** for tonight's session per operator command 2026-04-26 evening. Session governs cross-repo (Universe ADRs + universe-cli + windmill + new uploads repo) without per-team round-trip. Decisions are append-only via amendment blocks; teams can object post-hoc and amendments land same way.

## Session protocol

See [`docs/GUIDELINES.md` §Sprint docs](../../GUIDELINES.md) and [`infra/CLAUDE.md` §Sprint protocol](../../../CLAUDE.md) for the minimal-prompt session-start ritual.
