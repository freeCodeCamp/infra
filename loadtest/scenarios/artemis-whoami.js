// artemis-whoami.js — moderate-RPS GET /api/whoami.
//
// Authenticated read path. Exercises:
//   - GitHub bearer validation (RequireGitHubBearer middleware)
//   - GH /user/teams round-trip on cold cache; in-process cache (5 min
//     default, GH_MEMBERSHIP_CACHE_TTL) on warm cache.
//   - sites.yaml × user-teams intersection (local, no GH calls).
//
// Watch GH rate limit — keep `LOAD_PROFILE=smoke` unless using a
// high-rate token (org-level App). GitHub default is 5000/h/user.
//
// Run: GH_TOKEN=$(gh auth token) just loadtest artemis-whoami

import http from "k6/http";
import { sleep } from "k6";
import { loadConfig, stagesFor, checkResp } from "../lib/config.js";

const cfg = loadConfig();

if (!cfg.ghToken) {
  // eslint-disable-next-line no-console
  console.error("GH_TOKEN required (try: GH_TOKEN=$(gh auth token))");
  // k6 setup() can return early — but here we just let the run hit 401s
  // so the failure is visible in the summary rather than silently aborting.
}

export const options = {
  // Cap whoami at smoke profile by default — protects against GH rate limit.
  stages:
    cfg.profile === "stress"
      ? [
          { duration: "1m", target: 20 },
          { duration: "3m", target: 20 },
          { duration: "1m", target: 0 },
        ]
      : stagesFor(cfg.profile),
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<800", "p(99)<2000"],
    checks: ["rate>0.99"],
  },
  tags: { scenario: "artemis-whoami" },
};

export default function () {
  const url = `${cfg.artemisUrl}/api/whoami`;
  const resp = http.get(url, {
    headers: {
      Authorization: `Bearer ${cfg.ghToken}`,
      Accept: "application/json",
    },
    tags: { url },
  });
  checkResp(resp, "whoami");
  sleep(1);
}

export function setup() {
  // eslint-disable-next-line no-console
  console.log(
    `[artemis-whoami] target=${cfg.artemisUrl}/api/whoami profile=${cfg.profile}`,
  );
}
