import { assert, assertEquals, assertExists, assertMatch } from "@std/assert";

import {
  derEcdsaSignatureToP1363,
  handleAdmobSsv,
  parseSsvCallback,
  type RewardSettlementCallback,
  type SsvHandlerRuntime,
  type SsvServices,
  verifySsvSignature,
} from "./index.ts";

const userId = "11111111-1111-4111-8111-111111111111";
const claimId = "22222222-2222-4222-8222-222222222222";
const testNow = 1_785_663_807_975;
const requestId = "ssv-test-request-id";
const environment = {
  get: (key: string): string | undefined =>
    ({
      SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key",
    })[key],
};
const emptyEnvironment = { get: (_key: string): undefined => undefined };
const reportedGoogleSignature =
  "MEUCIACK-i0PJdKzFvdmoWcRjYT3hMo2HTwas8P8smpGHi1rAiEA_XVh_LtOrIKwX1EW_Bk3HqlnoDTmve0veVKZVEZu-JM";
const reportedGooglePublicKey = `-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE+nzvoGqvDeB9+SzE6igTl7TyK4JB
bglwir9oTcQta8NuG26ZpZFxt+F2NDk7asTE6/2Yc8i1ATcGIqtuS5hv0Q==
-----END PUBLIC KEY-----`;
const reportedGoogleQuery =
  "ad_network=5450213213286189855&ad_unit=1234567890&reward_amount=1&reward_item=point&timestamp=1785663807975&transaction_id=123456789";

Deno.test("health check is public, correlated, and does not read credentials", async () => {
  const response = await handleAdmobSsv(
    new Request("https://example.test/admob-ssv-handler/health"),
    emptyEnvironment,
    undefined,
    runtime(),
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    request_id: requestId,
    status: "ok",
  });
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(response.headers.get("x-request-id"), requestId);
});

Deno.test("callback only accepts GET and advertises the allowed method", async () => {
  const response = await handleAdmobSsv(
    new Request("https://example.test/admob-ssv-handler", { method: "POST" }),
    emptyEnvironment,
    undefined,
    runtime(),
  );
  assertEquals(response.status, 405);
  assertEquals(response.headers.get("allow"), "GET");
});

Deno.test("Google optional user_id and custom_data may be absent from the envelope", () => {
  const parsed = parseSsvCallback(reportedGoogleUrl());
  assertExists(parsed);
  assertEquals(parsed!.userId, null);
  assertEquals(parsed!.claimId, null);
  assertEquals(parsed!.rawAdUnitId, "1234567890");
  assertEquals(parsed!.rewardItem, "point");
});

Deno.test("the exact reported Google callback has a valid ECDSA signature", async () => {
  const parsed = parseSsvCallback(reportedGoogleUrl());
  assertExists(parsed);
  assertEquals(parsed!.keyId, 3335741209);
  assertEquals(
    await verifySsvSignature(parsed!, reportedGooglePublicKey),
    true,
  );
});

Deno.test("the exact signed AdMob configuration probe returns 200 without settlement", async () => {
  let settled = false;
  const logs: Record<string, unknown>[] = [];
  const response = await handleAdmobSsv(
    new Request(reportedGoogleUrl(), {
      headers: { "User-Agent": "Google-AdMob-Reward-Verification" },
    }),
    environment,
    () => ({
      getVerifierKey: (keyId) =>
        Promise.resolve(keyId === 3335741209 ? reportedGooglePublicKey : null),
      settleReward: () => {
        settled = true;
        return Promise.resolve({});
      },
    }),
    runtime(logs),
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    request_id: requestId,
    accepted: true,
    credited: false,
    duplicate: false,
    mode: "verified_debug_noop",
  });
  assertEquals(settled, false);
  assert(
    logs.some((record) =>
      record.event === "signature_verified" && record.valid === true
    ),
  );
  assert(
    logs.some((record) => record.event === "debug_callback_accepted"),
  );
});

Deno.test("setup probes with expired or future timestamps are rejected", async () => {
  for (
    const timestamp of [
      testNow - 20 * 60 * 1000 - 1,
      testNow + 5 * 60 * 1000 + 1,
    ]
  ) {
    const vector = await signedRequest({
      includeIdentifiers: false,
      adUnit: "1234567890",
      transactionId: "123456789",
      rewardItem: "point",
      timestamp,
      userAgent: "Google-AdMob-Reward-Verification",
    });
    const response = await handleAdmobSsv(
      vector.request,
      environment,
      () => servicesFor(vector.publicKeyPem),
      runtime(),
    );
    assertEquals(response.status, 400);
    assertEquals((await response.json()).error, "invalid_timestamp");
  }
});

Deno.test("missing required parameters fail before key lookup", async () => {
  const query =
    "ad_network=5450213213286189855&ad_unit=3342599731&reward_amount=1&reward_item=points&timestamp=1785663807975";
  let keyLookup = false;
  const response = await handleAdmobSsv(
    new Request(
      `https://example.test/admob-ssv-handler?${query}&signature=${fakeSignature()}&key_id=7`,
    ),
    environment,
    () => ({
      getVerifierKey: () => {
        keyLookup = true;
        return Promise.resolve(null);
      },
      settleReward: () => Promise.resolve({}),
    }),
    runtime(),
  );
  assertEquals(response.status, 400);
  assertEquals(keyLookup, false);
});

Deno.test("duplicate and malformed query parameters are rejected", () => {
  const duplicate =
    `${reportedGoogleQuery}&reward_item=point&signature=${reportedGoogleSignature}&key_id=3335741209`;
  assertEquals(
    parseSsvCallback(new URL(`https://example.test/?${duplicate}`)),
    null,
  );
  const malformed = reportedGoogleQuery.replace(
    "reward_item=point",
    "reward_item=%ZZ",
  );
  assertEquals(
    parseSsvCallback(
      new URL(
        `https://example.test/?${malformed}&signature=${reportedGoogleSignature}&key_id=3335741209`,
      ),
    ),
    null,
  );
});

Deno.test("callbacks whose signature and key are not final are rejected", () => {
  const parsed = parseSsvCallback(
    new URL(
      `https://example.test/?${reportedGoogleQuery}&signature=${reportedGoogleSignature}&key_id=3335741209&extra=x`,
    ),
  );
  assertEquals(parsed, null);
});

Deno.test("valid production callback is verified and settled", async () => {
  const vector = await signedRequest();
  const settledCallbacks: RewardSettlementCallback[] = [];
  const response = await handleAdmobSsv(
    vector.request,
    environment,
    () => ({
      getVerifierKey: (keyId) =>
        Promise.resolve(keyId === 7 ? vector.publicKeyPem : null),
      settleReward: (callback) => {
        settledCallbacks.push(callback);
        return Promise.resolve({
          credited: true,
          duplicate: false,
          balance: 8,
        });
      },
    }),
    runtime(),
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    request_id: requestId,
    accepted: true,
    credited: true,
    duplicate: false,
  });
  const settled = settledCallbacks[0];
  assertExists(settled);
  assertEquals(settled.userId, userId);
  assertEquals(settled.claimId, claimId);
  assertEquals(
    settled.adUnitId,
    "ca-app-pub-5274007212820203/4541482404",
  );
  assertEquals(settled.rewardAmount, 1);
});

Deno.test("production callbacks require signed claim and user identifiers", async () => {
  const vector = await signedRequest({ includeIdentifiers: false });
  let settled = false;
  const response = await handleAdmobSsv(
    vector.request,
    environment,
    () => ({
      getVerifierKey: () => Promise.resolve(vector.publicKeyPem),
      settleReward: () => {
        settled = true;
        return Promise.resolve({});
      },
    }),
    runtime(),
  );
  assertEquals(response.status, 400);
  assertEquals((await response.json()).error, "invalid_reward_callback");
  assertEquals(settled, false);
});

Deno.test("invalid production reward values and ad units fail after verification", async () => {
  const invalidCases = [
    { rewardItem: "point" },
    { rewardAmount: 2 },
    { adUnit: "9999999999" },
  ];
  for (const invalidCase of invalidCases) {
    const vector = await signedRequest(invalidCase);
    let settled = false;
    const response = await handleAdmobSsv(
      vector.request,
      environment,
      () => ({
        getVerifierKey: () => Promise.resolve(vector.publicKeyPem),
        settleReward: () => {
          settled = true;
          return Promise.resolve({});
        },
      }),
      runtime(),
    );
    assertEquals(response.status, 400);
    assertEquals(settled, false);
  }
});

Deno.test("invalid signatures return 401 and never settle", async () => {
  const vector = await signedRequest();
  const url = new URL(vector.request.url);
  url.searchParams.set("transaction_id", "tampered-transaction");
  let settled = false;
  const response = await handleAdmobSsv(
    new Request(url),
    environment,
    () => ({
      getVerifierKey: () => Promise.resolve(vector.publicKeyPem),
      settleReward: () => {
        settled = true;
        return Promise.resolve({});
      },
    }),
    runtime(),
  );
  assertEquals(response.status, 401);
  assertEquals((await response.json()).error, "invalid_signature");
  assertMatch(response.headers.get("www-authenticate") ?? "", /Signature/);
  assertEquals(settled, false);
});

Deno.test("an unknown key is refreshed once before rejection", async () => {
  const vector = await signedRequest();
  const refreshes: boolean[] = [];
  const response = await handleAdmobSsv(
    vector.request,
    environment,
    () => ({
      getVerifierKey: (_keyId, forceRefresh = false) => {
        refreshes.push(forceRefresh);
        return Promise.resolve(null);
      },
      settleReward: () => Promise.resolve({}),
    }),
    runtime(),
  );
  assertEquals(response.status, 400);
  assertEquals(refreshes, [false, true]);
});

Deno.test("database rejection statuses distinguish validation, authorization, and conflict", async () => {
  const cases = [
    {
      failure: { code: "22023", message: "SSV_TIMESTAMP_EXPIRED" },
      status: 400,
      error: "invalid_timestamp",
    },
    {
      failure: { code: "22023", message: "INVALID_REWARD_CLAIM" },
      status: 403,
      error: "reward_claim_rejected",
    },
    {
      failure: { code: "23505", message: "TRANSACTION_ID_REUSED" },
      status: 409,
      error: "transaction_conflict",
    },
  ];
  for (const testCase of cases) {
    const vector = await signedRequest();
    const response = await handleAdmobSsv(
      vector.request,
      environment,
      () => ({
        getVerifierKey: () => Promise.resolve(vector.publicKeyPem),
        settleReward: () => Promise.reject(testCase.failure),
      }),
      runtime(),
    );
    assertEquals(response.status, testCase.status);
    assertEquals((await response.json()).error, testCase.error);
  }
});

Deno.test("known duplicate settlement returns 200 without exposing wallet data", async () => {
  const vector = await signedRequest();
  const response = await handleAdmobSsv(
    vector.request,
    environment,
    () =>
      servicesFor(vector.publicKeyPem, {
        credited: true,
        duplicate: true,
        balance: 19,
      }),
    runtime(),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.duplicate, true);
  assertEquals("balance" in body, false);
});

Deno.test("transient dependency failures ask Google to retry", async () => {
  const vector = await signedRequest();
  const response = await handleAdmobSsv(
    vector.request,
    environment,
    () => ({
      getVerifierKey: () => Promise.resolve(vector.publicKeyPem),
      settleReward: () =>
        Promise.reject({ code: "08006", message: "connection failure" }),
    }),
    runtime(),
  );
  assertEquals(response.status, 503);
  assertEquals((await response.json()).error, "temporarily_unavailable");
  assertEquals(response.headers.get("retry-after"), "1");
});

Deno.test("unexpected failures return 500 and include a stack only in internal logs", async () => {
  const vector = await signedRequest();
  const logs: Record<string, unknown>[] = [];
  const response = await handleAdmobSsv(
    vector.request,
    environment,
    () => ({
      getVerifierKey: () => Promise.resolve(vector.publicKeyPem),
      settleReward: () => Promise.reject(new Error("unexpected test failure")),
    }),
    runtime(logs),
  );
  assertEquals(response.status, 500);
  const body = JSON.stringify(await response.json());
  assertEquals(body.includes("unexpected test failure"), false);
  assert(
    logs.some((record) => {
      const error = record.error as { stack?: string } | undefined;
      return error?.stack?.includes("unexpected test failure") ?? false;
    }),
  );
});

Deno.test("missing runtime credentials are reported through the injected reporter", async () => {
  const reports: Array<{ stage: string; requestId: string | undefined }> = [];
  const response = await handleAdmobSsv(
    reportedGoogleRequest(),
    emptyEnvironment,
    undefined,
    {
      ...runtime(),
      reportException: (_error, context) => {
        reports.push({ stage: context.stage, requestId: context.requestId });
        return Promise.resolve();
      },
    },
  );

  assertEquals(response.status, 500);
  assertEquals((await response.json()).error, "server_configuration_error");
  assertEquals(reports, [{ stage: "configuration", requestId }]);
});

Deno.test("transient dependency failures report retryable telemetry without leaking identifiers", async () => {
  const vector = await signedRequest();
  const reports: Array<
    { stage: string; tags: Record<string, unknown> | undefined }
  > = [];
  const response = await handleAdmobSsv(
    vector.request,
    environment,
    () => ({
      getVerifierKey: () => Promise.reject(new TypeError("network down")),
      settleReward: () => Promise.resolve({}),
    }),
    {
      ...runtime(),
      reportException: (_error, context) => {
        reports.push({ stage: context.stage, tags: context.tags });
        return Promise.resolve();
      },
    },
  );

  assertEquals(response.status, 503);
  assertEquals((await response.json()).error, "temporarily_unavailable");
  assertEquals(reports, [{
    stage: "public_key_lookup",
    tags: { retryable: true },
  }]);
});

Deno.test("structured logs cover every parameter without sensitive values", async () => {
  const vector = await signedRequest();
  const logs: Record<string, unknown>[] = [];
  await handleAdmobSsv(
    vector.request,
    environment,
    () => servicesFor(vector.publicKeyPem),
    runtime(logs),
  );
  const parsedLog = logs.find((record) => record.event === "callback_parsed");
  assertExists(parsedLog);
  const parameters = parsedLog!.parameters as Record<string, unknown>;
  assertEquals(Object.keys(parameters).sort(), [
    "ad_network",
    "ad_unit",
    "custom_data",
    "key_id",
    "reward_amount",
    "reward_item",
    "signature",
    "timestamp",
    "transaction_id",
    "user_id",
  ]);
  const serializedLogs = JSON.stringify(logs);
  assertEquals(serializedLogs.includes(userId), false);
  assertEquals(serializedLogs.includes(claimId), false);
  assertEquals(serializedLogs.includes("service-role-test-key"), false);
  assertEquals(serializedLogs.includes("signedContent"), false);
});

Deno.test("strict DER conversion returns a 64-byte P-256 signature", async () => {
  const vector = await signedRequest();
  const parsed = parseSsvCallback(new URL(vector.request.url));
  assertExists(parsed);
  const raw = derEcdsaSignatureToP1363(parsed!.signature, 32);
  assertEquals(raw.length, 64);
  assertMatch(toBase64Url(raw), /^[A-Za-z0-9_-]+$/);
});

interface SignedRequestOptions {
  rewardAmount?: number;
  rewardItem?: string;
  adUnit?: string;
  transactionId?: string;
  timestamp?: number;
  includeIdentifiers?: boolean;
  userAgent?: string;
}

async function signedRequest(
  options: SignedRequestOptions = {},
): Promise<{ request: Request; publicKeyPem: string }> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const signedContent = baseSignedQuery(options);
  const rawSignature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      keyPair.privateKey,
      new TextEncoder().encode(signedContent),
    ),
  );
  const derSignature = p1363ToDer(rawSignature);
  const signature = encodeURIComponent(toBase64Url(derSignature));
  const spki = new Uint8Array(
    await crypto.subtle.exportKey("spki", keyPair.publicKey),
  );
  const publicKeyPem = `-----BEGIN PUBLIC KEY-----\n${
    chunkedBase64(spki)
  }\n-----END PUBLIC KEY-----`;
  return {
    request: new Request(
      `https://example.test/admob-ssv-handler?${signedContent}&signature=${signature}&key_id=7`,
      options.userAgent
        ? { headers: { "User-Agent": options.userAgent } }
        : undefined,
    ),
    publicKeyPem,
  };
}

function baseSignedQuery(options: SignedRequestOptions = {}): string {
  const parameters: Record<string, string> = {
    ad_network: "5450213213286189855",
    ad_unit: options.adUnit ?? "4541482404",
  };
  if (options.includeIdentifiers !== false) parameters.custom_data = claimId;
  parameters.reward_amount = String(options.rewardAmount ?? 1);
  parameters.reward_item = options.rewardItem ?? "points";
  parameters.timestamp = String(options.timestamp ?? testNow);
  parameters.transaction_id = options.transactionId ?? "test-transaction-id";
  if (options.includeIdentifiers !== false) parameters.user_id = userId;
  return new URLSearchParams(parameters).toString();
}

function servicesFor(
  publicKeyPem: string,
  result: Record<string, unknown> = {
    credited: true,
    duplicate: false,
    balance: 8,
  },
): SsvServices {
  return {
    getVerifierKey: () => Promise.resolve(publicKeyPem),
    settleReward: () => Promise.resolve(result),
  };
}

function runtime(logs: Record<string, unknown>[] = []): SsvHandlerRuntime {
  return {
    now: () => testNow,
    requestIdFactory: () => requestId,
    log: (_level, record) => logs.push(record),
  };
}

function reportedGoogleUrl(): URL {
  return new URL(
    `https://example.test/admob-ssv-handler?${reportedGoogleQuery}&signature=${reportedGoogleSignature}&key_id=3335741209`,
  );
}

function reportedGoogleRequest(): Request {
  return new Request(reportedGoogleUrl());
}

function fakeSignature(): string {
  return toBase64Url(new Uint8Array(70));
}

function p1363ToDer(raw: Uint8Array): Uint8Array {
  if (raw.length !== 64) throw new Error("unexpected_signature_length");
  const r = positiveInteger(raw.slice(0, 32));
  const s = positiveInteger(raw.slice(32));
  const body = new Uint8Array(2 + r.length + 2 + s.length);
  let offset = 0;
  body[offset++] = 0x02;
  body[offset++] = r.length;
  body.set(r, offset);
  offset += r.length;
  body[offset++] = 0x02;
  body[offset++] = s.length;
  body.set(s, offset);
  const result = new Uint8Array(2 + body.length);
  result[0] = 0x30;
  result[1] = body.length;
  result.set(body, 2);
  return result;
}

function positiveInteger(value: Uint8Array): Uint8Array {
  let firstNonZero = 0;
  while (firstNonZero < value.length - 1 && value[firstNonZero] === 0) {
    firstNonZero++;
  }
  const trimmed = value.slice(firstNonZero);
  if ((trimmed[0] & 0x80) === 0) return trimmed;
  const padded = new Uint8Array(trimmed.length + 1);
  padded.set(trimmed, 1);
  return padded;
}

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_")
    .replace(/=+$/, "");
}

function chunkedBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).match(/.{1,64}/g)?.join("\n") ?? "";
}
