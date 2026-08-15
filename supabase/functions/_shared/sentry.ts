import * as Sentry from "@sentry/deno";

type EnvironmentReader = Pick<typeof Deno.env, "get">;

export interface EdgeExceptionContext {
  stage: string;
  requestId?: string;
  tags?: Record<string, boolean | number | string>;
  extras?: Record<string, boolean | number | string | null>;
  fingerprint?: string[];
}

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
      Sentry.captureException(error);
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
      delete event.user;
      delete event.request;
      if (event.tags) {
        for (const [key, value] of Object.entries(event.tags)) {
          if (typeof value === "string") {
            event.tags[key] = safeText(value);
          }
        }
      }
      return event;
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
