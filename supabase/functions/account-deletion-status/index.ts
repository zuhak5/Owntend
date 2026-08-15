import { createClient } from "@supabase/supabase-js";

import {
  createEdgeExceptionReporter,
  type EdgeExceptionReporter,
} from "../_shared/sentry.ts";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const recoveryKeyPattern = /^[A-Za-z0-9_-]{43}$/;
const userIdPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const allowedBrowserOrigins = new Set([
  "https://owntend.app",
  "http://localhost:4173",
  "http://127.0.0.1:4173",
]);

type EnvironmentReader = Pick<typeof Deno.env, "get">;

export interface DeletionRecoveryOperation {
  operationId: string;
  stage: string;
  activeUserId: string | null;
  completed: boolean;
}

export interface AccountDeletionStatusServices {
  lookupOperation(
    requestHash: string,
    subjectBinding: string,
  ): Promise<DeletionRecoveryOperation | null>;
  authUserExists(userId: string): Promise<boolean>;
  completeOperation(
    operationId: string,
    userId: string,
    subjectBinding: string,
  ): Promise<void>;
  acknowledgeOperation(
    operationId: string,
    subjectBinding: string,
    capabilityVersion: string,
  ): Promise<void>;
}

export type StatusServiceFactory = (
  supabaseUrl: string,
  serviceRoleKey: string,
) => AccountDeletionStatusServices;

export interface AccountDeletionStatusRuntime {
  reportException?: EdgeExceptionReporter;
}

export async function handleAccountDeletionStatus(
  request: Request,
  environment: EnvironmentReader = Deno.env,
  createServices: StatusServiceFactory = createAccountDeletionStatusServices,
  runtime: AccountDeletionStatusRuntime = {},
): Promise<Response> {
  const reportException = runtime.reportException ??
    createEdgeExceptionReporter("account-deletion-status", environment);
  const origin = request.headers.get("Origin");
  if (origin != null && !allowedBrowserOrigins.has(origin)) {
    return jsonResponse(403, { error: "origin_not_allowed" });
  }
  if (request.method === "OPTIONS") {
    if (origin == null) {
      return jsonResponse(403, { error: "origin_not_allowed" });
    }
    return new Response(null, {
      status: 204,
      headers: responseHeaders(origin, true),
    });
  }

  const respond = (
    status: number,
    body: Record<string, boolean | string>,
  ): Response => jsonResponse(status, body, origin);

  if (request.method !== "POST") {
    return respond(405, { error: "method_not_allowed" });
  }

  const payload = await readRecoveryPayload(request);
  if (payload == null) {
    return respond(400, { error: "invalid_recovery_request" });
  }

  const supabaseUrl = environment.get("SUPABASE_URL");
  const serviceRoleKey = environment.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    await reportException(new Error("server_configuration_error"), {
      stage: "configuration",
      tags: {
        supabase_url_present: Boolean(supabaseUrl),
        service_role_key_present: Boolean(serviceRoleKey),
      },
      fingerprint: ["account-deletion-status", "configuration"],
    });
    return respond(500, { error: "server_configuration_error" });
  }

  const requestHash = await sha256Hex(payload.recoveryKey);
  const subjectBinding = await sha256Hex(
    `${payload.recoveryKey}:${payload.expectedUserId}`,
  );
  const services = createServices(supabaseUrl, serviceRoleKey);
  let phase = "lookup_operation";
  try {
    let operation = await services.lookupOperation(
      requestHash,
      subjectBinding,
    );
    if (operation == null) {
      return respond(404, { error: "recovery_not_found" });
    }

    if (!operation.completed && operation.stage !== "acknowledged") {
      if (
        operation.activeUserId === payload.expectedUserId &&
        operation.stage === "auth_delete_started"
      ) {
        phase = "check_auth_user";
        if (await services.authUserExists(payload.expectedUserId)) {
          return respond(202, { deleted: false, status: "pending" });
        }

        phase = "complete_operation";
        await services.completeOperation(
          operation.operationId,
          payload.expectedUserId,
          subjectBinding,
        );
        operation = {
          ...operation,
          completed: true,
          stage: "completed",
        };
      } else {
        return respond(202, { deleted: false, status: "pending" });
      }
    }

    if (payload.acknowledge) {
      phase = "acknowledge_operation";
      await services.acknowledgeOperation(
        operation.operationId,
        subjectBinding,
        payload.capabilityVersion,
      );
      return respond(200, {
        deleted: true,
        status: "acknowledged",
        user_id: payload.expectedUserId,
      });
    }

    return respond(200, deletionReceipt(payload.expectedUserId));
  } catch (error) {
    await reportException(error, {
      stage: phase,
      fingerprint: ["account-deletion-status", phase],
    });
    logStatusFailure(phase, error);
    return respond(503, { error: "recovery_temporarily_unavailable" });
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleAccountDeletionStatus(request));
}

function createAccountDeletionStatusServices(
  supabaseUrl: string,
  serviceRoleKey: string,
): AccountDeletionStatusServices {
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return {
    async lookupOperation(requestHash, subjectBinding) {
      const { data, error } = await admin.rpc(
        "lookup_owntend_account_deletion_operation",
        {
          p_request_hash: requestHash,
          p_subject_binding: subjectBinding,
        },
      );
      if (error) throw error;
      if (data == null) return null;
      if (!isRecord(data)) throw new Error("invalid_recovery_operation");
      const operationId = data.operation_id;
      const stage = data.stage;
      const activeUserId = data.active_user_id;
      const completed = data.completed;
      if (
        typeof operationId !== "string" || typeof stage !== "string" ||
        (activeUserId !== null && typeof activeUserId !== "string") ||
        typeof completed !== "boolean"
      ) {
        throw new Error("invalid_recovery_operation");
      }
      return { operationId, stage, activeUserId, completed };
    },
    async authUserExists(userId) {
      const { data, error } = await admin.auth.admin.getUserById(userId);
      if (error != null) {
        const status = (error as { status?: number }).status;
        const code = (error as { code?: string }).code;
        if (status === 404 || code === "user_not_found") return false;
        throw error;
      }
      return data.user != null;
    },
    async completeOperation(operationId, userId, subjectBinding) {
      const { error } = await admin.rpc(
        "complete_owntend_account_deletion_operation",
        {
          p_operation_id: operationId,
          p_user_id: userId,
          p_subject_binding: subjectBinding,
        },
      );
      if (error) throw error;
    },
    async acknowledgeOperation(operationId, subjectBinding, capabilityVersion) {
      const { error } = await admin.rpc(
        "acknowledge_owntend_account_deletion_operation",
        {
          p_operation_id: operationId,
          p_subject_binding: subjectBinding,
          p_capability_version: capabilityVersion,
        },
      );
      if (error) throw error;
    },
  };
}

async function readRecoveryPayload(
  request: Request,
): Promise<
  {
    recoveryKey: string;
    expectedUserId: string;
    acknowledge: boolean;
    capabilityVersion: string;
  } | null
> {
  try {
    const body: unknown = await request.json();
    if (!isRecord(body)) return null;
    const recoveryKey = body.recovery_key;
    const expectedUserId = body.expected_user_id;
    const acknowledge = body.action === "acknowledge" ||
      body.acknowledge === true;
    const rawCapabilityVersion = typeof body.capability_version === "string"
      ? body.capability_version
      : typeof body.capabilityVersion === "string"
      ? body.capabilityVersion
      : "client-v1.0";
    const capabilityVersion =
      /^[A-Za-z0-9._-]{1,120}$/.test(rawCapabilityVersion)
        ? rawCapabilityVersion
        : "client-v1.0";

    if (
      typeof recoveryKey !== "string" ||
      !recoveryKeyPattern.test(recoveryKey) ||
      decodeBase64Url(recoveryKey).length !== 32 ||
      typeof expectedUserId !== "string" ||
      !userIdPattern.test(expectedUserId)
    ) {
      return null;
    }
    return { recoveryKey, expectedUserId, acknowledge, capabilityVersion };
  } catch {
    return null;
  }
}

function decodeBase64Url(value: string): Uint8Array {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - value.length % 4) % 4);
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

async function sha256Hex(value: string): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value != null;
}

function deletionReceipt(userId: string): Record<string, boolean | string> {
  return { deleted: true, status: "deleted", user_id: userId };
}

function jsonResponse(
  status: number,
  body: Record<string, boolean | string>,
  origin: string | null = null,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: responseHeaders(origin),
  });
}

function responseHeaders(origin: string | null, preflight = false): Headers {
  const headers = new Headers(jsonHeaders);
  if (origin != null) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Vary", "Origin");
  }
  if (preflight) {
    headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    headers.set(
      "Access-Control-Allow-Headers",
      "apikey, content-type, x-client-info",
    );
    headers.set("Access-Control-Max-Age", "600");
  }
  return headers;
}

function logStatusFailure(phase: string, error: unknown): void {
  const errorName = error instanceof Error ? error.name : "UnknownError";
  console.error("account_deletion_status_failed", {
    phase,
    error_name: errorName.replaceAll(/[^A-Za-z0-9_.-]/g, "_"),
  });
}
