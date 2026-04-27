// Shared k6 config helpers. Imported by every scenario in
// `loadtest/scenarios/`. k6 runs under its own JS runtime (goja),
// not Node — keep imports k6-native (`k6/*`).

import { check } from "k6";

// envOrDefault — k6 exposes process env via `__ENV` (uppercase).
export function env(key, def) {
  const v = __ENV[key];
  return v === undefined || v === "" ? def : v;
}

// Resolved config singleton — call once at scenario top-level.
export function loadConfig() {
  const artemisUrl = env(
    "ARTEMIS_URL",
    "https://uploads.freecode.camp",
  ).replace(/\/+$/, "");
  const site = env("SITE", "test");
  const rootDomain = env("ROOT_DOMAIN", "freecode.camp");
  return {
    artemisUrl,
    site,
    rootDomain,
    productionUrl: `https://${site}.${rootDomain}/`,
    previewUrl: `https://${site}.preview.${rootDomain}/`,
    ghToken: env("GH_TOKEN", ""),
    profile: env("LOAD_PROFILE", "smoke"),
  };
}

// Stage profiles — selected by LOAD_PROFILE. Each entry is a k6
// `stages` array driving a ramping VUs executor. Tune per scenario
// if needed; these are sane defaults.
export const stagesByProfile = {
  smoke: [
    { duration: "20s", target: 5 },
    { duration: "30s", target: 5 },
    { duration: "10s", target: 0 },
  ],
  baseline: [
    { duration: "1m", target: 50 },
    { duration: "3m", target: 50 },
    { duration: "1m", target: 0 },
  ],
  stress: [
    { duration: "2m", target: 50 },
    { duration: "3m", target: 200 },
    { duration: "3m", target: 200 },
    { duration: "2m", target: 0 },
  ],
};

// Pick stages for the current profile, falling back to smoke.
export function stagesFor(profile) {
  return stagesByProfile[profile] || stagesByProfile.smoke;
}

// Wrapper around k6 `check` that tags failures with the URL hit so
// the summary report attributes errors precisely.
export function checkResp(resp, name, expectedStatus = 200) {
  return check(resp, {
    [`${name}: status=${expectedStatus}`]: (r) => r.status === expectedStatus,
    [`${name}: body non-empty`]: (r) => r.body && r.body.length > 0,
  });
}

// Tiny payload generator — used by the deploy scenario to simulate
// realistic per-deploy file sizes without storing fixtures.
export function payloadHTML(marker) {
  return `<!doctype html><html><body><h1>${marker}</h1><p>k6 loadtest payload</p></body></html>\n`;
}
