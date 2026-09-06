import http from "k6/http";
import { check } from "k6";
import { Counter } from "k6/metrics";
import encoding from "k6/encoding";
import { env } from "../lib/config.js";

const LOGIN = env("VERITAS_LOGIN_ORIGIN", "https://login.freecodecamp.dev");
const ACCOUNT = env(
  "VERITAS_ACCOUNT_ORIGIN",
  "https://account.freecodecamp.dev",
);
const CONSOLE = env(
  "VERITAS_CONSOLE_ORIGIN",
  "https://auth-console.freecodecamp.dev",
);

http.setResponseCallback(http.expectedStatuses(200, 401, 403, 404, 429, 503));

const tokenLimited = new Counter("veritas_token_429");
const bootstrapLimited = new Counter("veritas_bootstrap_429");
const consoleLimited = new Counter("veritas_console_429");
const edgeLimited = new Counter("veritas_edge_429");
const spaLimited = new Counter("veritas_spa_429");
const bootstrapCreated = new Counter("veritas_bootstrap_201");

export const options = {
  scenarios: {
    discovery_hot: {
      executor: "constant-arrival-rate",
      rate: 20,
      timeUnit: "1s",
      duration: "1m",
      preAllocatedVUs: 10,
      maxVUs: 40,
      exec: "discovery",
    },
    token_abuse: {
      executor: "constant-arrival-rate",
      rate: 2,
      timeUnit: "1s",
      duration: "1m",
      preAllocatedVUs: 2,
      maxVUs: 5,
      exec: "token",
    },
    bootstrap_abuse: {
      executor: "constant-arrival-rate",
      rate: 5,
      timeUnit: "1s",
      duration: "40s",
      preAllocatedVUs: 5,
      maxVUs: 10,
      exec: "bootstrap",
      startTime: "5s",
    },
    console_abuse: {
      executor: "constant-arrival-rate",
      rate: 5,
      timeUnit: "1s",
      duration: "40s",
      preAllocatedVUs: 5,
      maxVUs: 10,
      exec: "controlMe",
      startTime: "10s",
    },
    edge_burst: {
      executor: "constant-arrival-rate",
      rate: 60,
      timeUnit: "1s",
      duration: "10s",
      preAllocatedVUs: 30,
      maxVUs: 120,
      exec: "edge",
      startTime: "70s",
    },
    spa_burst: {
      executor: "constant-arrival-rate",
      rate: 60,
      timeUnit: "1s",
      duration: "10s",
      preAllocatedVUs: 30,
      maxVUs: 120,
      exec: "spa",
      startTime: "85s",
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    "http_req_duration{scenario:discovery_hot}": ["p(95)<500", "p(99)<1500"],
    checks: ["rate>0.99"],
    veritas_token_429: ["count>0"],
    veritas_bootstrap_429: ["count>0"],
    veritas_console_429: ["count>0"],
    veritas_edge_429: ["count>0"],
    veritas_spa_429: ["count>0"],
    veritas_bootstrap_201: ["count==0"],
  },
  tags: { scenario: "veritas-abuse" },
};

export function discovery() {
  const resp = http.get(`${LOGIN}/.well-known/openid-configuration`, {
    tags: { url: "discovery" },
  });
  check(resp, {
    "discovery: 200": (r) => r.status === 200,
    "discovery: issuer": (r) => (r.json("issuer") || "") === LOGIN,
  });
}

export function token() {
  const resp = http.post(
    `${LOGIN}/api/auth/oauth2/token`,
    { grant_type: "client_credentials" },
    {
      headers: {
        Authorization: `Basic ${encoding.b64encode("abuse:not-a-secret")}`,
      },
      tags: { url: "token" },
    },
  );
  if (resp.status === 429) tokenLimited.add(1);
  check(resp, {
    "token: 401 or 429": (r) => r.status === 401 || r.status === 429,
  });
}

export function bootstrap() {
  const resp = http.post(
    `${CONSOLE}/internal/bootstrap`,
    JSON.stringify({ adminEmail: "abuse@example.test" }),
    {
      headers: { "content-type": "application/json" },
      tags: { url: "bootstrap" },
    },
  );
  if (resp.status === 429) bootstrapLimited.add(1);
  if (resp.status === 201) bootstrapCreated.add(1);
  check(resp, {
    "bootstrap: 401, 503 or 429": (r) =>
      r.status === 401 || r.status === 503 || r.status === 429,
  });
}

export function controlMe() {
  const resp = http.get(`${CONSOLE}/api/control/me`, {
    tags: { url: "control-me" },
  });
  if (resp.status === 429) consoleLimited.add(1);
  check(resp, {
    "control/me: 401 or 429": (r) => r.status === 401 || r.status === 429,
  });
}

export function edge() {
  const resp = http.get(`${LOGIN}/healthz`, { tags: { url: "healthz" } });
  if (resp.status === 429) edgeLimited.add(1);
  check(resp, {
    "healthz: 200 or 429": (r) => r.status === 200 || r.status === 429,
  });
}

export function spa() {
  const resp = http.get(`${ACCOUNT}/`, { tags: { url: "account-spa" } });
  if (resp.status === 429) spaLimited.add(1);
  check(resp, {
    "account spa: 200 or 429": (r) => r.status === 200 || r.status === 429,
  });
}

export function setup() {
  console.log(
    `[veritas-abuse] login=${LOGIN} account=${ACCOUNT} console=${CONSOLE}`,
  );
}
