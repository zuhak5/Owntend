import * as Sentry from "@sentry/deno";

type EnvironmentReader = Pick<typeof Deno.env, "get">;

export interface EdgeExceptionContext {
  stage: string;
  requestId?: string;
  tags?: Record<string, boolean | number | string>;
  extras?: Record<string, boolean | number | string | null>;
  fingerprint?: string[];
}

type JsonRecord = Record<string, unknown>;

const safeTechnicalToken = /^[a-z][a-z0-9_.:-]{0,79}$/;
const allowedStringFields = new Set([
  "function",
  "stage",
  "request_id",
  "error_type",
  "error_code",
]);

export type EdgeExceptionReporter = (
  error: unknown,
  context: EdgeExceptionContext,
) => Promise<void>;

let initialized = false;
let enabled = false;

export function createEdgeExceptionReporter(
  functionName: string,
  environment: EnvironmentReader = Deno.env,
): EdgeExceptionReporter {
  return async (error, context) => {
    if (!ensureEdgeSentry(environment)) {
      return;
    }
    await Sentry.withScope(async (scope) => {
      scope.setTag("function", safeToken(functionName));
      scope.setTag("stage", safeToken(context.stage));
      if (context.requestId != null) {
        scope.setTag("request_id", safeToken(context.requestId));
      }
      for (const [key, value] of Object.entries(context.tags ?? {})) {
        scope.setTag(safeToken(key), safeScalar(value));
      }
      for (const [key, value] of Object.entries(context.extras ?? {})) {
        scope.setExtra(safeToken(key), safeExtra(value));
      }
      if (context.fingerprint?.length) {
        scope.setFingerprint(context.fingerprint.map(safeToken));
      }
      const errorType = error instanceof Error
        ? safeTechnicalValue(error.name, "error")
        : "unknown_error";
      scope.setTag("error_type", errorType);
      Sentry.captureException(
        new EdgeTelemetryError(
          `${safeTechnicalValue(context.stage, "operation")}_failed`,
        ),
      );
      await Sentry.flush(2_000);
    });
  };
}

function ensureEdgeSentry(environment: EnvironmentReader): boolean {
  if (initialized) {
    return enabled;
  }
  initialized = true;
  const dsn = environment.get("SENTRY_DSN")?.trim();
  if (!dsn) {
    return false;
  }
  Sentry.init({
    dsn,
    sendDefaultPii: false,
    defaultIntegrations: false,
    tracesSampleRate: 0,
    environment: environment.get("APP_ENV")?.trim() || undefined,
    release: environment.get("DENO_DEPLOYMENT_ID")?.trim() || undefined,
    beforeSend(event) {
      return scrubEdgeSentryEvent(event);
    },
  });
  enabled = true;
  return true;
}

function safeExtra(
  value: boolean | number | string | null,
): boolean | number | string | null {
  if (typeof value !== "string") {
    return value;
  }
  return safeText(value);
}

function safeScalar(value: boolean | number | string): string {
  return typeof value === "string" ? safeText(value) : String(value);
}

function safeText(value: string): string {
  const normalized = value.replaceAll(/[^A-Za-z0-9_.:-]/g, "_");
  return normalized.length <= 120 ? normalized : normalized.slice(0, 120);
}

function safeToken(value: string): string {
  return safeText(value);
}

class EdgeTelemetryError extends Error {
  override readonly name = "EdgeTelemetryError";
}

function safeTechnicalValue(value: string, fallback: string): string {
  const normalized = value.trim().toLowerCase().replaceAll(
    /[^a-z0-9_.:-]/g,
    "_",
  );
  return safeTechnicalToken.test(normalized) ? normalized : fallback;
}

/**
 * Returns an allowlisted Sentry event. Arbitrary request, exception, context,
 * breadcrumb, module, and runtime values are intentionally not copied.
 */
export function scrubEdgeSentryEvent<T extends object>(event: T): T {
  const source = event as unknown as JsonRecord;
  const scrubbed: JsonRecord = {};
  copyFiniteNumber(source, scrubbed, "timestamp");
  copyTechnicalString(source, scrubbed, "event_id");
  copyTechnicalString(source, scrubbed, "level");
  copyTechnicalString(source, scrubbed, "platform");
  copyTechnicalString(source, scrubbed, "environment");
  copyTechnicalString(source, scrubbed, "release");

  const tags = sanitizeTechnicalMap(source.tags);
  if (Object.keys(tags).length > 0) scrubbed.tags = tags;
  const extra = sanitizeTechnicalMap(source.extra, { allowNumbers: true });
  if (Object.keys(extra).length > 0) scrubbed.extra = extra;

  const values = exceptionValues(source.exception);
  if (values.length > 0) {
    scrubbed.exception = {
      values: values.map((value) => ({
        type: "edge_telemetry_error",
        value: "edge_failure",
        stacktrace: sanitizeStacktrace(value.stacktrace),
      })),
    };
  } else {
    scrubbed.message = "edge_failure";
  }
  return scrubbed as unknown as T;
}

function exceptionValues(value: unknown): JsonRecord[] {
  if (!isRecord(value) || !Array.isArray(value.values)) return [];
  return value.values.filter(isRecord).slice(0, 4);
}

function sanitizeStacktrace(value: unknown): JsonRecord | undefined {
  if (!isRecord(value) || !Array.isArray(value.frames)) return undefined;
  const frames = value.frames.filter(isRecord).slice(-40).map((frame) => {
    const result: JsonRecord = {};
    copyFiniteNumber(frame, result, "lineno");
    copyFiniteNumber(frame, result, "colno");
    if (typeof frame.in_app === "boolean") result.in_app = frame.in_app;
    if (typeof frame.function === "string") {
      result.function = safeTechnicalValue(frame.function, "anonymous");
    }
    return result;
  });
  return frames.length > 0 ? { frames } : undefined;
}

function sanitizeTechnicalMap(
  value: unknown,
  { allowNumbers = false }: { allowNumbers?: boolean } = {},
): JsonRecord {
  if (!isRecord(value)) return {};
  const result: JsonRecord = {};
  for (const [rawKey, rawValue] of Object.entries(value).slice(0, 32)) {
    const key = safeTechnicalValue(rawKey, "field");
    if (typeof rawValue === "boolean" || rawValue === null) {
      result[key] = rawValue;
    } else if (
      allowNumbers && typeof rawValue === "number" && Number.isFinite(rawValue)
    ) {
      result[key] = rawValue;
    } else if (typeof rawValue === "string" && allowedStringFields.has(key)) {
      result[key] = safeTechnicalValue(rawValue, "redacted");
    } else if (typeof rawValue === "string") {
      result[key] = "redacted";
    }
  }
  return result;
}

function copyFiniteNumber(
  source: JsonRecord,
  target: JsonRecord,
  key: string,
): void {
  const value = source[key];
  if (typeof value === "number" && Number.isFinite(value)) target[key] = value;
}

function copyTechnicalString(
  source: JsonRecord,
  target: JsonRecord,
  key: string,
): void {
  const value = source[key];
  if (typeof value === "string") target[key] = safeTechnicalValue(value, key);
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value != null && !Array.isArray(value);
}
