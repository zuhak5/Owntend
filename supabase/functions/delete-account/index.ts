import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import {
  createEdgeExceptionReporter,
  type EdgeExceptionReporter,
} from "../_shared/sentry.ts";
import { readBoundedJsonObject } from "../_shared/request.ts";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const requiredConfirmation = "delete-my-account";
const maxDeletionBodyBytes = 512;
const recoveryKeyPattern = /^[A-Za-z0-9_-]{43}$/;
const allowedBrowserOrigins = new Set([
  "https://owntend.app",
  "http://localhost:4173",
  "http://127.0.0.1:4173",
]);

type EnvironmentReader = Pick<typeof Deno.env, "get">;

export interface AccountDeletionServices {
  getVerifiedUserId(token: string): Promise<string | null>;
  isRecentSession(userId: string, sessionId: string): Promise<boolean>;
  listObjectPaths(userId: string): Promise<string[]>;
  beginCleanup(userId: string, objectPaths: string[]): Promise<string>;
  removeObjects(objectPaths: string[]): Promise<void>;
  deleteUser(userId: string): Promise<void>;
  completeCleanup(jobId: string): Promise<void>;
  recordCleanupError(jobId: string, errorCode: string): Promise<void>;
  beginOperation(
    requestHash: string,
    subjectBinding: string,
    userId: string,
  ): Promise<AccountDeletionOperation>;
  advanceOperation(
    operationId: string,
    userId: string,
    stage: AccountDeletionOperationStage,
  ): Promise<void>;
  completeOperation(
    operationId: string,
    userId: string,
    subjectBinding: string,
  ): Promise<void>;
  recordOperationError(
    operationId: string,
    userId: string,
    errorCode: string,
  ): Promise<void>;
}

export interface AccountDeletionOperation {
  operationId: string;
  stage: AccountDeletionOperationStage;
  completed: boolean;
}

export type AccountDeletionOperationStage =
  | "prepared"
  | "storage_cleanup"
  | "storage_complete"
  | "auth_delete_started"
  | "completed"
  | "acknowledged";

export type ServiceFactory = (
  supabaseUrl: string,
  anonKey: string,
  serviceRoleKey: string,
  authorization: string,
) => AccountDeletionServices;

export interface DeleteAccountRuntime {
  reportException?: EdgeExceptionReporter;
}

export async function handleDeleteAccount(
  request: Request,
  environment: EnvironmentReader = Deno.env,
  createServices: ServiceFactory = createAccountDeletionServices,
  runtime: DeleteAccountRuntime = {},
): Promise<Response> {
  const reportException = runtime.reportException ??
    createEdgeExceptionReporter("delete-account", environment);
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

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return respond(401, { error: "missing_authorization" });
  }

  const deletionPayloadResult = await readDeletionPayload(request);
  if (!deletionPayloadResult.ok) {
    if (deletionPayloadResult.reason === "too_large") {
      return respond(413, { error: "request_too_large" });
    }
    if (deletionPayloadResult.reason === "unsupported_media_type") {
      return respond(415, { error: "unsupported_media_type" });
    }
    return respond(400, { error: "invalid_request" });
  }
  const deletionPayload = deletionPayloadResult.value;
  if (!deletionPayload.confirmed) {
    return respond(400, { error: "confirmation_required" });
  }
  if (deletionPayload.recoveryKey == null) {
    return respond(400, { error: "recovery_key_required" });
  }

  const supabaseUrl = environment.get("SUPABASE_URL");
  const anonKey = environment.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = environment.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    await reportException(new Error("server_configuration_error"), {
      stage: "configuration",
      tags: {
        supabase_url_present: Boolean(supabaseUrl),
        anon_key_present: Boolean(anonKey),
        service_role_key_present: Boolean(serviceRoleKey),
      },
      fingerprint: ["delete-account", "configuration"],
    });
    return respond(500, { error: "server_configuration_error" });
  }

  const token = authorization.slice("Bearer ".length);
  const sessionId = sessionIdFromJwt(token);
  if (sessionId == null) {
    return respond(401, { error: "invalid_session" });
  }

  const services = createServices(
    supabaseUrl,
    anonKey,
    serviceRoleKey,
    authorization,
  );
  const userId = await services.getVerifiedUserId(token);
  if (userId == null) {
    return respond(401, { error: "invalid_session" });
  }

  if (!await services.isRecentSession(userId, sessionId)) {
    return respond(403, { error: "recent_reauthentication_required" });
  }

  const requestHash = await sha256Hex(deletionPayload.recoveryKey);
  const subjectBinding = await sha256Hex(
    `${deletionPayload.recoveryKey}:${userId}`,
  );
  let cleanupJobId: string | null = null;
  let operationId: string | null = null;
  let phase = "begin_operation";
  try {
    const operation = await services.beginOperation(
      requestHash,
      subjectBinding,
      userId,
    );
    operationId = operation.operationId;
    if (operation.completed) {
      return respond(200, deletionReceipt(userId));
    }

    phase = "prepare_cleanup";
    const initialObjectPaths = await services.listObjectPaths(userId);
    cleanupJobId = await services.beginCleanup(userId, initialObjectPaths);

    phase = "remove_storage";
    await services.advanceOperation(operationId, userId, "storage_cleanup");
    await removeAllUserObjects(services, userId);

    phase = "complete_cleanup";
    await services.completeCleanup(cleanupJobId);
    cleanupJobId = null;
    await services.advanceOperation(operationId, userId, "storage_complete");

    phase = "delete_auth_user";
    await services.advanceOperation(
      operationId,
      userId,
      "auth_delete_started",
    );
    await services.deleteUser(userId);

    phase = "complete_operation";
    await services.completeOperation(operationId, userId, subjectBinding);

    return respond(200, deletionReceipt(userId));
  } catch (error) {
    const errorCode = `${phase}_failed`;
    if (cleanupJobId != null) {
      try {
        await services.recordCleanupError(cleanupJobId, errorCode);
      } catch (recordError) {
        logDeletionFailure("record_cleanup_error", recordError);
      }
    }
    if (operationId != null) {
      try {
        await services.recordOperationError(operationId, userId, errorCode);
      } catch (recordError) {
        logDeletionFailure("record_operation_error", recordError);
      }
    }
    await reportException(error, {
      stage: phase,
      tags: {
        cleanup_job_present: cleanupJobId != null,
        operation_present: operationId != null,
      },
      extras: { error_code: errorCode },
      fingerprint: ["delete-account", phase, errorCode],
    });
    logDeletionFailure(phase, error);
    switch (phase) {
      case "remove_storage":
        return respond(503, { error: "storage_cleanup_failed" });
      case "delete_auth_user":
      case "complete_operation":
      case "complete_cleanup":
        return respond(500, { error: "account_deletion_failed" });
      default:
        return respond(500, { error: "account_deletion_failed" });
    }
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleDeleteAccount(request));
}

function createAccountDeletionServices(
  supabaseUrl: string,
  anonKey: string,
  serviceRoleKey: string,
  authorization: string,
): AccountDeletionServices {
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return {
    async getVerifiedUserId(token: string): Promise<string | null> {
      const { data, error } = await userClient.auth.getUser(token);
      return error == null ? data.user?.id ?? null : null;
    },
    async isRecentSession(userId: string, sessionId: string): Promise<boolean> {
      const { data, error } = await admin.rpc("is_recent_owntend_session", {
        p_user_id: userId,
        p_session_id: sessionId,
      });
      if (error) throw error;
      return data === true;
    },
    listObjectPaths: (userId: string) =>
      listObjectPaths(admin, "user-media", userId),
    async beginCleanup(
      userId: string,
      objectPaths: string[],
    ): Promise<string> {
      const { data, error } = await admin.rpc(
        "begin_owntend_account_cleanup",
        { p_user_id: userId, p_object_paths: objectPaths },
      );
      if (error || typeof data !== "string") {
        throw error ?? new Error("cleanup_job_creation_failed");
      }
      return data;
    },
    removeObjects: (objectPaths: string[]) =>
      removeObjectsWithRetry(admin, "user-media", objectPaths),
    async deleteUser(userId: string): Promise<void> {
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) throw error;
    },
    async completeCleanup(jobId: string): Promise<void> {
      const { error } = await admin.rpc("complete_owntend_account_cleanup", {
        p_job_id: jobId,
        p_error: null,
      });
      if (error) throw error;
    },
    async recordCleanupError(jobId: string, errorCode: string): Promise<void> {
      const { error } = await admin.rpc("complete_owntend_account_cleanup", {
        p_job_id: jobId,
        p_error: errorCode,
      });
      if (error) throw error;
    },
    async beginOperation(requestHash, subjectBinding, userId) {
      const { data, error } = await admin.rpc(
        "begin_owntend_account_deletion_operation",
        {
          p_request_hash: requestHash,
          p_subject_binding: subjectBinding,
          p_user_id: userId,
        },
      );
      if (error || !isRecord(data)) {
        throw error ?? new Error("deletion_operation_creation_failed");
      }
      const operationId = data.operation_id;
      const stage = data.stage;
      if (
        typeof operationId !== "string" || !isOperationStage(stage) ||
        typeof data.completed !== "boolean"
      ) {
        throw new Error("invalid_deletion_operation");
      }
      return {
        operationId,
        stage,
        completed: data.completed,
      };
    },
    async advanceOperation(operationId, userId, stage): Promise<void> {
      const { error } = await admin.rpc(
        "advance_owntend_account_deletion_operation",
        {
          p_operation_id: operationId,
          p_user_id: userId,
          p_stage: stage,
        },
      );
      if (error) throw error;
    },
    async completeOperation(
      operationId,
      userId,
      subjectBinding,
    ): Promise<void> {
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
    async recordOperationError(
      operationId,
      userId,
      errorCode,
    ): Promise<void> {
      const { error } = await admin.rpc(
        "record_owntend_account_deletion_operation_error",
        {
          p_operation_id: operationId,
          p_user_id: userId,
          p_error_code: errorCode,
        },
      );
      if (error) throw error;
    },
  };
}

async function readDeletionPayload(
  request: Request,
): Promise<
  | {
    ok: true;
    value: { confirmed: boolean; recoveryKey: string | null };
  }
  | { ok: false; reason: "invalid" | "too_large" | "unsupported_media_type" }
> {
  const result = await readBoundedJsonObject(request, maxDeletionBodyBytes);
  if (!result.ok) return result;
  const candidate = result.value;
  const keys = Object.keys(candidate);
  if (keys.some((key) => key !== "confirmation" && key !== "recovery_key")) {
    return { ok: false, reason: "invalid" };
  }
  return {
    ok: true,
    value: {
      confirmed: candidate.confirmation === requiredConfirmation,
      recoveryKey: isRecoveryKey(candidate.recovery_key)
        ? candidate.recovery_key
        : null,
    },
  };
}

function isRecoveryKey(value: unknown): value is string {
  if (typeof value !== "string" || !recoveryKeyPattern.test(value)) {
    return false;
  }
  try {
    return decodeBase64Url(value).length === 32;
  } catch {
    return false;
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

function isOperationStage(
  value: unknown,
): value is AccountDeletionOperationStage {
  return typeof value === "string" && [
    "prepared",
    "storage_cleanup",
    "storage_complete",
    "auth_delete_started",
    "completed",
    "acknowledged",
  ].includes(value);
}

function deletionReceipt(userId: string): Record<string, boolean | string> {
  return { deleted: true, status: "deleted", user_id: userId };
}

function sessionIdFromJwt(token: string): string | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const encoded = parts[1].replaceAll("-", "+").replaceAll("_", "/");
    const padded = encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=");
    const binary = atob(padded);
    const bytes = Uint8Array.from(binary, (value) => value.charCodeAt(0));
    const payload: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (
      typeof payload !== "object" || payload == null ||
      !("session_id" in payload)
    ) {
      return null;
    }
    const sessionId = payload.session_id;
    return typeof sessionId === "string" && isUuid(sessionId)
      ? sessionId
      : null;
  } catch {
    return null;
  }
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

async function removeAllUserObjects(
  services: AccountDeletionServices,
  userId: string,
): Promise<void> {
  for (let pass = 0; pass < 3; pass++) {
    const objectPaths = await services.listObjectPaths(userId);
    if (objectPaths.length === 0) return;
    await services.removeObjects(objectPaths);
  }
  if ((await services.listObjectPaths(userId)).length !== 0) {
    throw new Error("storage_cleanup_incomplete");
  }
}

async function listObjectPaths(
  admin: SupabaseClient,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const paths: string[] = [];
  let offset = 0;
  while (true) {
    const { data, error } = await admin.storage.from(bucket).list(prefix, {
      limit: 100,
      offset,
      sortBy: { column: "name", order: "asc" },
    });
    if (error) throw error;
    for (const item of data ?? []) {
      const path = `${prefix}/${item.name}`;
      if (item.id) {
        paths.push(path);
      } else {
        paths.push(...await listObjectPaths(admin, bucket, path));
      }
    }
    if (!data || data.length < 100) break;
    offset += data.length;
  }
  return paths;
}

async function removeObjectsWithRetry(
  admin: SupabaseClient,
  bucket: string,
  objectPaths: string[],
): Promise<void> {
  for (let index = 0; index < objectPaths.length; index += 100) {
    const batch = objectPaths.slice(index, index + 100);
    let lastError: Error | null = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      const { error } = await admin.storage.from(bucket).remove(batch);
      if (!error) {
        lastError = null;
        break;
      }
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 250 * 2 ** attempt));
    }
    if (lastError) throw lastError;
  }
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
      "authorization, apikey, content-type, x-client-info",
    );
    headers.set("Access-Control-Max-Age", "600");
  }
  return headers;
}

function logDeletionFailure(phase: string, error: unknown): void {
  const errorName = error instanceof Error ? error.name : "UnknownError";
  console.error("account_deletion_failed", {
    phase,
    error_name: errorName.replaceAll(/[^A-Za-z0-9_.-]/g, "_"),
  });
}
