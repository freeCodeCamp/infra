// artemis-deploy.js — sustained init+upload+finalize burst.
//
// Write-heavy. Each iteration:
//   1. POST /api/deploy/init  (GH bearer, mints deploy JWT)
//   2. PUT  /api/deploy/{id}/upload?path=index.html  (deploy JWT)
//   3. POST /api/deploy/{id}/finalize {mode:preview} (deploy JWT)
//
// Skips promote — that would flip the live preview alias under load
// and is not the point of this scenario. Each iteration leaves an
// orphaned deploy prefix; cleanup cron (T22, 7-day retention) sweeps.
//
// Caveats:
//   - Uses LOAD_PROFILE-clamped VUs (max 20 even on stress) to avoid
//     hammering R2 PUT quotas.
//   - Watch artemis pod CPU/mem — write path is heaviest there.
//   - Keep duration short; long runs accumulate R2 storage.
//
// Run: GH_TOKEN=$(gh auth token) just loadtest artemis-deploy

import http from "k6/http";
import { check, sleep } from "k6";
import { loadConfig, payloadHTML } from "../lib/config.js";

const cfg = loadConfig();

if (!cfg.ghToken) {
  // eslint-disable-next-line no-console
  console.error("GH_TOKEN required (try: GH_TOKEN=$(gh auth token))");
}

// Hand-tuned stages — small VU counts because each iteration writes to R2.
const stagesByProfile = {
  smoke: [
    { duration: "20s", target: 2 },
    { duration: "30s", target: 2 },
    { duration: "10s", target: 0 },
  ],
  baseline: [
    { duration: "1m", target: 5 },
    { duration: "3m", target: 5 },
    { duration: "1m", target: 0 },
  ],
  stress: [
    { duration: "1m", target: 10 },
    { duration: "3m", target: 20 },
    { duration: "1m", target: 0 },
  ],
};

export const options = {
  stages: stagesByProfile[cfg.profile] || stagesByProfile.smoke,
  thresholds: {
    http_req_failed: ["rate<0.05"],
    "http_req_duration{step:init}": ["p(95)<1500"],
    "http_req_duration{step:upload}": ["p(95)<2000"],
    "http_req_duration{step:finalize}": ["p(95)<2000"],
    checks: ["rate>0.95"],
  },
  tags: { scenario: "artemis-deploy" },
};

export default function () {
  // 1. init
  const sha = `lt${Date.now().toString(36)}`;
  const initBody = JSON.stringify({
    site: cfg.site,
    sha,
    files: ["index.html"],
  });
  const initResp = http.post(`${cfg.artemisUrl}/api/deploy/init`, initBody, {
    headers: {
      Authorization: `Bearer ${cfg.ghToken}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    tags: { step: "init" },
  });
  const initOk = check(initResp, {
    "init: status=200": (r) => r.status === 200,
    "init: jwt present": (r) => {
      try {
        return r.json("jwt") !== "" && r.json("deployId") !== "";
      } catch {
        return false;
      }
    },
  });
  if (!initOk) {
    sleep(2);
    return;
  }
  const deployId = initResp.json("deployId");
  const jwt = initResp.json("jwt");

  // 2. upload
  const marker = `lt-${sha}`;
  const upResp = http.put(
    `${cfg.artemisUrl}/api/deploy/${deployId}/upload?path=index.html`,
    payloadHTML(marker),
    {
      headers: {
        Authorization: `Bearer ${jwt}`,
        "Content-Type": "text/html; charset=utf-8",
        Accept: "application/json",
      },
      tags: { step: "upload" },
    },
  );
  const upOk = check(upResp, {
    "upload: status=200": (r) => r.status === 200,
  });
  if (!upOk) {
    sleep(1);
    return;
  }

  // 3. finalize → preview
  const finBody = JSON.stringify({
    mode: "preview",
    files: ["index.html"],
  });
  const finResp = http.post(
    `${cfg.artemisUrl}/api/deploy/${deployId}/finalize`,
    finBody,
    {
      headers: {
        Authorization: `Bearer ${jwt}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      tags: { step: "finalize" },
    },
  );
  check(finResp, {
    "finalize: status=200": (r) => r.status === 200,
  });

  sleep(1);
}

export function setup() {
  // eslint-disable-next-line no-console
  console.log(
    `[artemis-deploy] target=${cfg.artemisUrl} site=${cfg.site} profile=${cfg.profile}`,
  );
}
