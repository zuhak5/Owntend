import { createClient } from "@supabase/supabase-js";

import {
  createEdgeExceptionReporter,
  type EdgeExceptionReporter,
} from "../_shared/sentry.ts";

const googleVerifierKeysUrl =
  "https://www.gstatic.com/admob/reward/verifier-keys.json";
const keyCacheLifetimeMs = 23 * 60 * 60 * 1000;
const verifierKeyFetchTimeoutMs = 5_000;
const maxRawQueryLength = 8_192;
const maxSetupProbeAgeMs = 20 * 60 * 1000;
const maxFutureClockSkewMs = 5 * 60 * 1000;
const admobVerificationUserAgent = "Google-AdMob-Reward-Verification";
const admobVerificationAdUnit = "1234567890";
const admobVerificationTransaction = "123456789";
const jsonHeaders = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const productionAdUnits = new Map([
  [
    "4541482404",
    {
      fullId: "ca-app-pub-5274007212820203/4541482404",
      rewardAmount: 1,
    },
  ],
  [
    "7295784043",
    {
      fullId: "ca-app-pub-5274007212820203/7295784043",
      rewardAmount: 2,
    },
  ],
]);

type EnvironmentReader = Pick<typeof Deno.env, "get">;
type SsvLogLevel = "info" | "warn" | "error";

export interface GoogleVerifierKey {
  keyId: number;
  pem: string;
}

export interface ParsedSsvCallback {
  signedContent: string;
  signature: Uint8Array;
  keyId: number;
  adNetworkId: string;
  rawAdUnitId: string;
  transactionId: string;
  claimId: string | null;
  userId: string | null;
  rewardAmount: number;
  rewardItem: string;
  googleTimestamp: Date;
  receivedParameterNames: string[];
}

export interface RewardSettlementCallback extends ParsedSsvCallback {
  claimId: string;
  userId: string;
  adUnitId: string;
}

export interface SsvServices {
  getVerifierKey(keyId: number, forceRefresh?: boolean): Promise<string | null>;
  settleReward(
    callback: RewardSettlementCallback,
  ): Promise<Record<string, unknown>>;
}

export type SsvServiceFactory = (
  supabaseUrl: string,
  serviceRoleKey: string,
) => SsvServices;

export type SsvLogSink = (
  level: SsvLogLevel,
  record: Record<string, unknown>,
) => void;

export interface SsvHandlerRuntime {
  now?: () => number;
  requestIdFactory?: () => string;
  log?: SsvLogSink;
  reportException?: EdgeExceptionReporter;
}

interface ParseFailure {
  ok: false;
  reason: string;
  parameterNames: string[];
}

interface ParseSuccess {
  ok: true;
  callback: ParsedSsvCallback;
}

type ParseResult = ParseFailure | ParseSuccess;

interface ValidationFailure {
  ok: false;
  reason: string;
}

interface ValidationSuccess {
  ok: true;
  callback: RewardSettlementCallback;
}

type ProductionValidationResult = ValidationFailure | ValidationSuccess;

let cachedKeys: { fetchedAt: number; keys: GoogleVerifierKey[] } | null = null;
let keyRefreshInFlight:
  | Promise<{
    fetchedAt: number;
    keys: GoogleVerifierKey[];
  }>
  | null = null;

export async function handleAdmobSsv(
  request: Request,
  environment: EnvironmentReader = Deno.env,
  createServices: SsvServiceFactory = createSsvServices,
  runtime: SsvHandlerRuntime = {},
): Promise<Response> {
  const now = runtime.now ?? Date.now;
  const requestId = runtime.requestIdFactory?.() ?? crypto.randomUUID();
  const startedAt = performance.now();
  const logger = runtime.log ?? defaultLogSink;
  const reportException = runtime.reportException ??
    createEdgeExceptionReporter("admob-ssv-handler", environment);
  const requestUrl = new URL(request.url);
  const emit = (
    level: SsvLogLevel,
    event: string,
    fields: Record<string, unknown> = {},
  ) => {
    logger(level, {
      component: "admob_ssv_handler",
      request_id: requestId,
      event,
      logged_at: new Date(now()).toISOString(),
      ...fields,
    });
  };
  const respond = (
    status: number,
    body: Record<string, unknown>,
    headers: HeadersInit = {},
  ) => {
    emit(
      status >= 500 ? "error" : status >= 400 ? "warn" : "info",
      "response",
      {
        status,
        decision: body.error ?? body.mode ?? "accepted",
        elapsed_ms: Math.round(performance.now() - startedAt),
      },
    );
    return jsonResponse(
      status,
      { request_id: requestId, ...body },
      { "X-Request-ID": requestId, ...headers },
    );
  };

  emit("info", "request_received", {
    method: request.method,
    path: requestUrl.pathname,
    user_agent: request.headers.get("user-agent") ?? "",
    query_length: requestUrl.search.length,
    parameter_names: safeParameterNames(requestUrl),
  });

  if (request.method !== "GET") {
    return respond(405, { error: "method_not_allowed" }, { Allow: "GET" });
  }
  if (requestUrl.pathname.endsWith("/health")) {
    return respond(200, { status: "ok" });
  }

  const parseResult = parseSsvCallbackDetailed(requestUrl);
  if (!parseResult.ok) {
    emit("warn", "validation_failed", {
      stage: "envelope",
      reason: parseResult.reason,
      parameter_names: parseResult.parameterNames,
    });
    return respond(400, { error: "invalid_callback" });
  }
  const parsed = parseResult.callback;
  emit("info", "callback_parsed", {
    parameters: await safeCallbackParameters(parsed),
    validation: "envelope_valid",
  });

  const supabaseUrl = environment.get("SUPABASE_URL");
  const serviceRoleKey = environment.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    await reportException(new Error("server_configuration_error"), {
      stage: "configuration",
      requestId,
      tags: {
        supabase_url_present: Boolean(supabaseUrl),
        service_role_key_present: Boolean(serviceRoleKey),
      },
      fingerprint: ["admob-ssv-handler", "configuration"],
    });
    emit("error", "configuration_failed", {
      reason: "missing_supabase_runtime_credentials",
      supabase_url_present: Boolean(supabaseUrl),
      service_role_key_present: Boolean(serviceRoleKey),
    });
    return respond(500, { error: "server_configuration_error" });
  }

  let stage = "service_initialization";
  try {
    const services = createServices(supabaseUrl, serviceRoleKey);
    stage = "public_key_lookup";
    emit("info", "public_key_lookup_started", {
      key_id: parsed.keyId,
      forced_refresh: false,
    });
    let verifierKey = await services.getVerifierKey(parsed.keyId);
    if (verifierKey == null) {
      emit("warn", "public_key_not_found", {
        key_id: parsed.keyId,
        forced_refresh: false,
      });
      verifierKey = await services.getVerifierKey(parsed.keyId, true);
    }
    if (verifierKey == null) {
      emit("warn", "validation_failed", {
        stage,
        reason: "unknown_key_id_after_refresh",
        key_id: parsed.keyId,
      });
      return respond(400, { error: "unknown_key" });
    }
    emit("info", "public_key_selected", {
      key_id: parsed.keyId,
      algorithm: "ECDSA_P256_SHA256",
    });

    stage = "signature_verification";
    const signatureValid = await verifySsvSignature(parsed, verifierKey);
    emit(signatureValid ? "info" : "warn", "signature_verified", {
      key_id: parsed.keyId,
      valid: signatureValid,
      signed_content_bytes:
        new TextEncoder().encode(parsed.signedContent).length,
      signature_bytes: parsed.signature.length,
    });
    if (!signatureValid) {
      return respond(
        401,
        { error: "invalid_signature" },
        { "WWW-Authenticate": 'Signature realm="admob-ssv"' },
      );
    }

    if (isAdmobSetupVerificationProbe(request, parsed)) {
      const timestampFailure = setupProbeTimestampFailure(
        parsed.googleTimestamp,
        now(),
      );
      if (timestampFailure != null) {
        emit("warn", "validation_failed", {
          stage: "setup_probe_timestamp",
          reason: timestampFailure,
          key_id: parsed.keyId,
        });
        return respond(400, { error: "invalid_timestamp" });
      }
      emit("info", "debug_callback_accepted", {
        transaction_fingerprint: await identifierFingerprint(
          parsed.transactionId,
        ),
        database_operation: "skipped",
        key_id: parsed.keyId,
        reason: "signed_admob_configuration_test",
      });
      return respond(200, {
        accepted: true,
        credited: false,
        duplicate: false,
        mode: "verified_debug_noop",
      });
    }

    stage = "production_validation";
    const validation = validateProductionCallback(parsed);
    if (!validation.ok) {
      emit("warn", "validation_failed", {
        stage,
        reason: validation.reason,
        key_id: parsed.keyId,
      });
      return respond(400, { error: "invalid_reward_callback" });
    }

    stage = "database_settlement";
    emit("info", "database_operation_started", {
      operation: "process_admob_ssv_reward",
      transaction_fingerprint: await identifierFingerprint(
        parsed.transactionId,
      ),
    });
    const result = await services.settleReward(validation.callback);
    const credited = result.credited === true;
    const duplicate = result.duplicate === true;
    emit("info", "database_operation_completed", {
      operation: "process_admob_ssv_reward",
      credited,
      duplicate,
      result_reason: typeof result.reason === "string" ? result.reason : null,
    });
    return respond(200, { accepted: true, credited, duplicate });
  } catch (error) {
    const failure = databaseFailure(error);
    if (stage === "database_settlement" && failure != null) {
      if (failure.status >= 500) {
        await reportException(error, {
          stage,
          requestId,
          tags: { retryable: failure.retryable, status: failure.status },
          extras: {
            public_error: failure.publicError,
            failure_reason: failure.reason,
            sqlstate: failure.sqlstate,
          },
          fingerprint: ["admob-ssv-handler", stage, failure.publicError],
        });
      }
      emit(
        failure.status >= 500 ? "error" : "warn",
        "database_operation_failed",
        {
          operation: "process_admob_ssv_reward",
          reason: failure.reason,
          sqlstate: failure.sqlstate,
          retryable: failure.retryable,
          error: internalErrorDetails(error),
        },
      );
      const headers: HeadersInit = failure.retryable
        ? { "Retry-After": "1" }
        : {};
      return respond(failure.status, { error: failure.publicError }, headers);
    }

    const retryable = stage === "public_key_lookup" || isTransientError(error);
    await reportException(error, {
      stage,
      requestId,
      tags: { retryable },
      extras: {
        failure_reason: retryable
          ? "transient_dependency_failure"
          : "unexpected_failure",
      },
      fingerprint: [
        "admob-ssv-handler",
        stage,
        retryable ? "retryable" : "unexpected",
      ],
    });
    emit("error", "processing_failed", {
      stage,
      reason: retryable ? "transient_dependency_failure" : "unexpected_failure",
      retryable,
      error: internalErrorDetails(error),
    });
    return respond(
      retryable ? 503 : 500,
      {
        error: retryable ? "temporarily_unavailable" : "internal_server_error",
      },
      retryable ? { "Retry-After": "1" } : {},
    );
  }
}

export function parseSsvCallback(url: URL): ParsedSsvCallback | null {
  const result = parseSsvCallbackDetailed(url);
  return result.ok ? result.callback : null;
}

function parseSsvCallbackDetailed(url: URL): ParseResult {
  const rawQuery = url.search.startsWith("?")
    ? url.search.slice(1)
    : url.search;
  const parameterNames = safeParameterNames(url);
  if (!rawQuery || rawQuery.length > maxRawQueryLength) {
    return parseFailure("invalid_query_length", parameterNames);
  }

  const signatureMarker = "&signature=";
  const signatureIndex = rawQuery.indexOf(signatureMarker);
  if (
    signatureIndex <= 0 ||
    rawQuery.indexOf(signatureMarker, signatureIndex + 1) !== -1
  ) {
    return parseFailure("signature_not_unique_or_not_final", parameterNames);
  }
  const keyMarker = "&key_id=";
  const keyIndex = rawQuery.indexOf(
    keyMarker,
    signatureIndex + signatureMarker.length,
  );
  if (
    keyIndex <= signatureIndex ||
    rawQuery.indexOf(keyMarker, keyIndex + 1) !== -1 ||
    rawQuery.indexOf("&", keyIndex + 1) !== -1
  ) {
    return parseFailure("key_id_not_unique_or_not_final", parameterNames);
  }

  const signedContent = rawQuery.slice(0, signatureIndex);
  const encodedSignature = rawQuery.slice(
    signatureIndex + signatureMarker.length,
    keyIndex,
  );
  const encodedKeyId = rawQuery.slice(keyIndex + keyMarker.length);
  let signatureValue: string;
  let keyIdValue: string;
  try {
    signatureValue = decodeURIComponent(encodedSignature);
    keyIdValue = decodeURIComponent(encodedKeyId);
  } catch {
    return parseFailure("malformed_signature_encoding", parameterNames);
  }
  if (
    !/^[A-Za-z0-9_-]+={0,2}$/.test(signatureValue) ||
    !/^\d{1,20}$/.test(keyIdValue)
  ) {
    return parseFailure("invalid_signature_or_key_encoding", parameterNames);
  }

  let signature: Uint8Array;
  try {
    signature = decodeBase64Url(signatureValue);
  } catch {
    return parseFailure("invalid_signature_encoding", parameterNames);
  }
  const keyId = Number(keyIdValue);
  if (
    signature.length < 64 || signature.length > 80 ||
    !Number.isSafeInteger(keyId) || keyId < 0
  ) {
    return parseFailure("invalid_signature_or_key_length", parameterNames);
  }

  const pairs = new Map<string, string[]>();
  for (const segment of signedContent.split("&")) {
    const equalsIndex = segment.indexOf("=");
    if (equalsIndex <= 0) {
      return parseFailure("malformed_query_parameter", parameterNames);
    }
    let name: string;
    let value: string;
    try {
      name = decodeFormComponent(segment.slice(0, equalsIndex));
      value = decodeFormComponent(segment.slice(equalsIndex + 1));
    } catch {
      return parseFailure("malformed_query_encoding", parameterNames);
    }
    const values = pairs.get(name) ?? [];
    values.push(value);
    pairs.set(name, values);
  }

  const requiredNames = [
    "ad_network",
    "ad_unit",
    "reward_amount",
    "reward_item",
    "timestamp",
    "transaction_id",
  ];
  const optionalNames = ["custom_data", "user_id"];
  const allowedNames = new Set([...requiredNames, ...optionalNames]);
  for (const name of requiredNames) {
    if (pairs.get(name)?.length !== 1) {
      return parseFailure(
        `missing_or_duplicate_parameter:${name}`,
        parameterNames,
      );
    }
  }
  for (const name of optionalNames) {
    if ((pairs.get(name)?.length ?? 0) > 1) {
      return parseFailure(`duplicate_parameter:${name}`, parameterNames);
    }
  }
  for (const name of pairs.keys()) {
    if (!allowedNames.has(name)) {
      return parseFailure(`unexpected_parameter:${name}`, parameterNames);
    }
  }

  const value = (name: string) => pairs.get(name)?.[0] ?? "";
  const adNetworkId = value("ad_network");
  const rawAdUnitId = value("ad_unit");
  const transactionId = value("transaction_id");
  const rewardItem = value("reward_item");
  const rewardAmountValue = value("reward_amount");
  const timestampValue = value("timestamp");
  const claimId = pairs.has("custom_data") ? value("custom_data") : null;
  const userId = pairs.has("user_id") ? value("user_id") : null;
  if (!/^\d{1,32}$/.test(adNetworkId)) {
    return parseFailure("invalid_ad_network", parameterNames);
  }
  if (
    rawAdUnitId.length < 1 || rawAdUnitId.length > 120 ||
    containsControlCharacter(rawAdUnitId)
  ) {
    return parseFailure("invalid_ad_unit", parameterNames);
  }
  if (
    transactionId.length < 1 || transactionId.length > 200 ||
    containsControlCharacter(transactionId)
  ) {
    return parseFailure("invalid_transaction_id", parameterNames);
  }
  if (
    rewardItem.length < 1 || rewardItem.length > 80 ||
    containsControlCharacter(rewardItem) ||
    !/^[1-9]\d{0,8}$/.test(rewardAmountValue) ||
    !/^\d{13,16}$/.test(timestampValue)
  ) {
    return parseFailure("invalid_reward_or_timestamp", parameterNames);
  }
  for (
    const [name, optionalValue] of [
      ["custom_data", claimId],
      ["user_id", userId],
    ] as const
  ) {
    if (
      optionalValue != null &&
      (optionalValue.length > 1_024 || containsControlCharacter(optionalValue))
    ) {
      return parseFailure(`invalid_optional_parameter:${name}`, parameterNames);
    }
  }

  const rewardAmount = Number(rewardAmountValue);
  const timestampMs = Number(timestampValue);
  if (
    !Number.isSafeInteger(rewardAmount) ||
    !Number.isSafeInteger(timestampMs) ||
    timestampMs < 1_500_000_000_000
  ) {
    return parseFailure("invalid_numeric_parameter", parameterNames);
  }
  const googleTimestamp = new Date(timestampMs);
  if (Number.isNaN(googleTimestamp.getTime())) {
    return parseFailure("invalid_timestamp", parameterNames);
  }

  return {
    ok: true,
    callback: {
      signedContent,
      signature,
      keyId,
      adNetworkId,
      rawAdUnitId,
      transactionId,
      claimId,
      userId,
      rewardAmount,
      rewardItem,
      googleTimestamp,
      receivedParameterNames: [...pairs.keys(), "signature", "key_id"],
    },
  };
}

function validateProductionCallback(
  callback: ParsedSsvCallback,
): ProductionValidationResult {
  if (callback.claimId == null || !uuidPattern.test(callback.claimId)) {
    return { ok: false, reason: "missing_or_invalid_custom_data_claim_id" };
  }
  if (callback.userId == null || !uuidPattern.test(callback.userId)) {
    return { ok: false, reason: "missing_or_invalid_user_id" };
  }
  if (callback.rewardItem !== "points") {
    return { ok: false, reason: "unexpected_reward_item" };
  }
  const adUnit = productionAdUnit(callback.rawAdUnitId);
  if (adUnit == null) {
    return { ok: false, reason: "unexpected_ad_unit" };
  }
  if (callback.rewardAmount !== adUnit.rewardAmount) {
    return { ok: false, reason: "unexpected_reward_amount" };
  }
  return {
    ok: true,
    callback: {
      ...callback,
      claimId: callback.claimId,
      userId: callback.userId,
      adUnitId: adUnit.fullId,
    },
  };
}

function isAdmobSetupVerificationProbe(
  request: Request,
  callback: ParsedSsvCallback,
): boolean {
  return (
    (request.headers.get("user-agent") === admobVerificationUserAgent &&
      callback.rawAdUnitId === admobVerificationAdUnit &&
      callback.transactionId === admobVerificationTransaction) ||
    callback.claimId === "fakeForAdDebugLog" ||
    callback.userId === "fakeForAdDebugLog"
  );
}

function setupProbeTimestampFailure(
  googleTimestamp: Date,
  nowMs: number,
): string | null {
  const timestampMs = googleTimestamp.getTime();
  if (timestampMs > nowMs + maxFutureClockSkewMs) {
    return "timestamp_too_far_in_future";
  }
  if (timestampMs < nowMs - maxSetupProbeAgeMs) {
    return "timestamp_expired";
  }
  return null;
}

export async function verifySsvSignature(
  callback: Pick<ParsedSsvCallback, "signedContent" | "signature">,
  publicKeyPem: string,
): Promise<boolean> {
  try {
    const publicKeyBytes = pemToBytes(publicKeyPem);
    const key = await crypto.subtle.importKey(
      "spki",
      toArrayBuffer(publicKeyBytes),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    const rawSignature = derEcdsaSignatureToP1363(callback.signature, 32);
    return await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      toArrayBuffer(rawSignature),
      new TextEncoder().encode(callback.signedContent),
    );
  } catch {
    return false;
  }
}

export function derEcdsaSignatureToP1363(
  der: Uint8Array,
  componentSize: number,
): Uint8Array {
  let offset = 0;
  if (der[offset++] !== 0x30) throw new Error("invalid_der_sequence");
  const sequenceLength = readDerLength(der, offset);
  offset = sequenceLength.nextOffset;
  if (sequenceLength.length !== der.length - offset) {
    throw new Error("invalid_der_sequence_length");
  }
  const r = readDerInteger(der, offset, componentSize);
  offset = r.nextOffset;
  const s = readDerInteger(der, offset, componentSize);
  offset = s.nextOffset;
  if (offset !== der.length) throw new Error("trailing_der_data");
  const result = new Uint8Array(componentSize * 2);
  result.set(r.value, 0);
  result.set(s.value, componentSize);
  return result;
}

function readDerInteger(
  bytes: Uint8Array,
  offset: number,
  componentSize: number,
): { value: Uint8Array; nextOffset: number } {
  if (bytes[offset++] !== 0x02) throw new Error("invalid_der_integer");
  const integerLength = readDerLength(bytes, offset);
  offset = integerLength.nextOffset;
  if (
    integerLength.length < 1 || offset + integerLength.length > bytes.length
  ) {
    throw new Error("invalid_der_integer_length");
  }
  let value = bytes.slice(offset, offset + integerLength.length);
  offset += integerLength.length;
  if ((value[0] & 0x80) !== 0) throw new Error("negative_der_integer");
  if (value.length > 1 && value[0] === 0) value = value.slice(1);
  if (value.length > componentSize) throw new Error("oversized_der_integer");
  const padded = new Uint8Array(componentSize);
  padded.set(value, componentSize - value.length);
  return { value: padded, nextOffset: offset };
}

function readDerLength(
  bytes: Uint8Array,
  offset: number,
): { length: number; nextOffset: number } {
  const first = bytes[offset++];
  if (first == null) throw new Error("missing_der_length");
  if ((first & 0x80) === 0) return { length: first, nextOffset: offset };
  const count = first & 0x7f;
  if (count < 1 || count > 2 || offset + count > bytes.length) {
    throw new Error("invalid_der_length");
  }
  let length = 0;
  for (let index = 0; index < count; index++) {
    length = (length << 8) | bytes[offset++];
  }
  return { length, nextOffset: offset };
}

function productionAdUnit(
  raw: string,
): { fullId: string; rewardAmount: number } | null {
  const id = raw.includes("/") ? raw.slice(raw.lastIndexOf("/") + 1) : raw;
  return productionAdUnits.get(id) ?? null;
}

function containsControlCharacter(value: string): boolean {
  return [...value].some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint < 32 || codePoint === 127;
  });
}

function decodeFormComponent(value: string): string {
  return decodeURIComponent(value.replaceAll("+", " "));
}

function decodeBase64Url(value: string): Uint8Array {
  const unpadded = value.replace(/=+$/, "");
  const base64 = unpadded.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - unpadded.length % 4) % 4);
  const decoded = atob(base64);
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function pemToBytes(pem: string): Uint8Array {
  const base64 = pem
    .replace("-----BEGIN PUBLIC KEY-----", "")
    .replace("-----END PUBLIC KEY-----", "")
    .replace(/\s/g, "");
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
}

function createSsvServices(
  supabaseUrl: string,
  serviceRoleKey: string,
): SsvServices {
  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return {
    async getVerifierKey(keyId, forceRefresh = false) {
      const now = Date.now();
      const minRefreshCooldownMs = 60_000;
      const canForceRefresh = forceRefresh &&
        (cachedKeys == null ||
          now - cachedKeys.fetchedAt >= minRefreshCooldownMs);
      if (
        cachedKeys == null ||
        canForceRefresh ||
        now - cachedKeys.fetchedAt >= keyCacheLifetimeMs
      ) {
        if (keyRefreshInFlight == null) {
          keyRefreshInFlight = refreshGoogleVerifierKeys(now).finally(() => {
            keyRefreshInFlight = null;
          });
        }
        cachedKeys = await keyRefreshInFlight;
      }
      return cachedKeys.keys.find((key) => key.keyId === keyId)?.pem ?? null;
    },
    async settleReward(callback) {
      const { data, error } = await client.rpc("process_admob_ssv_reward", {
        p_transaction_id: callback.transactionId,
        p_claim_id: callback.claimId,
        p_user_id: callback.userId,
        p_ad_unit_id: callback.adUnitId,
        p_reward_amount: callback.rewardAmount,
        p_reward_item: callback.rewardItem,
        p_google_timestamp: callback.googleTimestamp.toISOString(),
      });
      if (error) throw error;
      return (data ?? {}) as Record<string, unknown>;
    },
  };
}

async function refreshGoogleVerifierKeys(
  fetchedAt: number,
): Promise<{ fetchedAt: number; keys: GoogleVerifierKey[] }> {
  const response = await fetch(googleVerifierKeysUrl, {
    headers: { Accept: "application/json", "Cache-Control": "no-cache" },
    signal: AbortSignal.timeout(verifierKeyFetchTimeoutMs),
  });
  if (!response.ok) throw new Error("verifier_key_fetch_failed");
  const contentLength = Number(response.headers.get("content-length") ?? "0");
  if (contentLength > 256_000) throw new Error("verifier_key_set_too_large");
  const body = await response.json() as { keys?: GoogleVerifierKey[] };
  const keys = (body.keys ?? []).filter((key) =>
    Number.isSafeInteger(key.keyId) &&
    typeof key.pem === "string" &&
    key.pem.includes("BEGIN PUBLIC KEY") &&
    key.pem.length <= 2_048
  );
  if (keys.length === 0) throw new Error("invalid_verifier_key_set");
  return { fetchedAt, keys };
}

function databaseFailure(error: unknown): {
  status: number;
  publicError: string;
  reason: string;
  sqlstate: string | null;
  retryable: boolean;
} | null {
  const failure = error as { code?: string; message?: string };
  const code = failure?.code ?? "";
  const message = failure?.message ?? "";
  if (message === "SSV_TIMESTAMP_EXPIRED") {
    return {
      status: 400,
      publicError: "invalid_timestamp",
      reason: "signed_timestamp_expired",
      sqlstate: code || null,
      retryable: false,
    };
  }
  if (message === "INVALID_REWARD_CLAIM") {
    return {
      status: 403,
      publicError: "reward_claim_rejected",
      reason: message,
      sqlstate: code || null,
      retryable: false,
    };
  }
  if (message === "INVALID_SSV_PAYLOAD" || code === "22023") {
    return {
      status: 400,
      publicError: "invalid_reward_callback",
      reason: message || "invalid_database_payload",
      sqlstate: code || null,
      retryable: false,
    };
  }
  if (message === "TRANSACTION_ID_REUSED" || code === "23505") {
    return {
      status: 409,
      publicError: "transaction_conflict",
      reason: message || "unique_transaction_conflict",
      sqlstate: code || null,
      retryable: false,
    };
  }
  if (code === "42501" || message === "SERVICE_ROLE_REQUIRED") {
    return {
      status: 500,
      publicError: "server_configuration_error",
      reason: "settlement_authorization_failed",
      sqlstate: code || null,
      retryable: false,
    };
  }
  if (isTransientError(error)) {
    return {
      status: 503,
      publicError: "temporarily_unavailable",
      reason: message || "transient_database_failure",
      sqlstate: code || null,
      retryable: true,
    };
  }
  return null;
}

function isTransientError(error: unknown): boolean {
  if (error instanceof TypeError || error instanceof DOMException) return true;
  const code = (error as { code?: string })?.code ?? "";
  return code.startsWith("08") || code.startsWith("53") ||
    code.startsWith("57P") || code === "40001" || code === "40P01" ||
    code === "55P03" || code === "PGRST000" || code === "PGRST002";
}

function internalErrorDetails(error: unknown): Record<string, unknown> {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
      stack: error.stack ?? null,
    };
  }
  const failure = error as { code?: string; message?: string };
  return {
    name: "DatabaseError",
    code: failure?.code ?? null,
    message: failure?.message ?? "unknown_error",
    stack: null,
  };
}

async function safeCallbackParameters(
  callback: ParsedSsvCallback,
): Promise<Record<string, unknown>> {
  return {
    ad_network: callback.adNetworkId,
    ad_unit: callback.rawAdUnitId,
    custom_data: redactedParameter(callback.claimId),
    reward_amount: callback.rewardAmount,
    reward_item: callback.rewardItem,
    timestamp: callback.googleTimestamp.getTime(),
    transaction_id: {
      present: true,
      length: callback.transactionId.length,
      fingerprint: await identifierFingerprint(callback.transactionId),
    },
    user_id: redactedParameter(callback.userId),
    signature: { present: true, byte_length: callback.signature.length },
    key_id: callback.keyId,
  };
}

function redactedParameter(value: string | null): Record<string, unknown> {
  return value == null
    ? { present: false }
    : { present: true, length: value.length, value: "[REDACTED]" };
}

async function identifierFingerprint(value: string): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
  return [...digest.slice(0, 8)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function safeParameterNames(url: URL): string[] {
  const rawQuery = url.search.startsWith("?")
    ? url.search.slice(1)
    : url.search;
  if (!rawQuery) return [];
  return rawQuery.split("&").map((segment) => {
    const equalsIndex = segment.indexOf("=");
    const encodedName = equalsIndex < 0
      ? segment
      : segment.slice(0, equalsIndex);
    try {
      const name = decodeFormComponent(encodedName);
      return /^[a-z_]+$/.test(name) ? name : "[INVALID_NAME]";
    } catch {
      return "[MALFORMED_NAME]";
    }
  });
}

function parseFailure(reason: string, parameterNames: string[]): ParseFailure {
  return { ok: false, reason, parameterNames };
}

function defaultLogSink(
  level: SsvLogLevel,
  record: Record<string, unknown>,
): void {
  const line = JSON.stringify(record);
  if (level === "error") {
    console.error(line);
  } else if (level === "warn") {
    console.warn(line);
  } else {
    console.log(line);
  }
}

function jsonResponse(
  status: number,
  body: Record<string, unknown>,
  extraHeaders: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...jsonHeaders, ...extraHeaders },
  });
}

if (import.meta.main) {
  Deno.serve((request) => handleAdmobSsv(request));
}
