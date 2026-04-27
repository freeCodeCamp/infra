// caddy-serve-preview.js — high-RPS GET against the preview alias.
//
// Same hot path as caddy-serve.js but targets the preview hostname
// (`<site>.preview.<root>`). Preview traffic sees less CF cache hit
// because preview content rotates per-deploy; this scenario stresses
// the cold-cache path more aggressively.
//
// Run: just loadtest caddy-serve-preview

import http from "k6/http";
import { sleep } from "k6";
import { loadConfig, stagesFor, checkResp } from "../lib/config.js";

const cfg = loadConfig();

export const options = {
  stages: stagesFor(cfg.profile),
  thresholds: {
    http_req_failed: ["rate<0.02"],
    http_req_duration: ["p(95)<800", "p(99)<2000"],
    checks: ["rate>0.98"],
  },
  tags: { scenario: "caddy-serve-preview", target: "preview" },
};

export default function () {
  const resp = http.get(cfg.previewUrl, {
    headers: { "Cache-Control": "no-cache" },
    tags: { url: cfg.previewUrl },
  });
  checkResp(resp, "caddy-serve-preview");
  sleep(1);
}

export function setup() {
  // eslint-disable-next-line no-console
  console.log(
    `[caddy-serve-preview] target=${cfg.previewUrl} profile=${cfg.profile}`,
  );
}
