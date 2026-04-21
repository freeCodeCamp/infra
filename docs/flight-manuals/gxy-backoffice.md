# Flight Manual — gxy-backoffice

**Planned, not provisioned.** Backoffice + observability galaxy. Hosts the
o11y stack (VictoriaMetrics → ClickHouse + Vector → HyperDX → GlitchTip per
ADR-015) and future internal tools (Outline, Appsmith, etc.).

Activation trigger: gxy-cassiopeia MVP shipped + staff team onboarded. Until
then this file stays a placeholder.

## Planned scope (per ADR-015 + operator reassignment, 2026-04-21)

| Tool                      | Role                                      | Phase |
| ------------------------- | ----------------------------------------- | ----- |
| VictoriaMetrics + vmagent | Metrics ingest + storage                  | 1     |
| Grafana                   | Dashboards                                | 1     |
| ClickHouse + Vector       | Logs ingest + storage                     | 2     |
| HyperDX                   | Correlated logs + traces + session replay | 3     |
| GlitchTip                 | Error tracking (Sentry SDK compatible)    | 4     |

Scaling, retention, and data-flow details live in the ADR until this galaxy
lands.

## Planned provisioning

- Provider: TBD (cloud initial) → Hetzner post-M5
- Region: FRA (aligns with other galaxies)
- Sizing: TBD (depends on cross-galaxy traffic volume once other galaxies
  emit metrics/logs)
- Substrate: k3s HA embedded etcd + Cilium + Traefik (consistent with other
  galaxies)

## Write this manual when

- gxy-backoffice droplets exist (DO or Hetzner)
- First o11y tool is deployed
- Cross-galaxy scrape / ingest endpoints are configured

Cross-ref: [00-index.md](00-index.md) for shared infrastructure,
[../GUIDELINES.md](../GUIDELINES.md) for flight-manual format.
