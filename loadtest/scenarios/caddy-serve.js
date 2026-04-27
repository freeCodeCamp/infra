// caddy-serve.js — high-RPS GET against the production alias.
//
// Hot path: client → CF edge → cassiopeia Caddy (r2_alias) → R2.
// CF edge cache absorbs the majority once warm; cold-cache RPS hits
// Caddy + R2.
//
// Run: just loadtest caddy-serve

import http from "k6/http";
import { sleep } from "k6";
import { loadConfig, stagesFor, checkResp } from "../lib/config.js";

const cfg = loadConfig();

export const options = {
  stages: stagesFor(cfg.profile),
  thresholds: {
    // 99% of requests succeed; p95 under 500 ms (CF edge typical).
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<500", "p(99)<1500"],
    checks: ["rate>0.99"],
  },
  tags: { scenario: "caddy-serve", target: "production" },
};

export default function () {
  const resp = http.get(cfg.productionUrl, {
    headers: { "Cache-Control": "no-cache" },
    tags: { url: cfg.productionUrl },
  });
  checkResp(resp, "caddy-serve");
  sleep(1);
}

export function setup() {
  // eslint-disable-next-line no-console
  console.log(
    `[caddy-serve] target=${cfg.productionUrl} profile=${cfg.profile}`,
  );
}
