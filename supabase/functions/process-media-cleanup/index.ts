import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  createEdgeExceptionReporter,
  type EdgeExceptionReporter,
} from "../_shared/sentry.ts";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};

// Service-to-service contract: the scheduler presents a dedicated capability
// token in this header. The platform gateway runs with verify_jwt = false for
// this endpoint, and the Supabase service-role key is never accepted from or
// sent by the scheduler.
export const WORKER_TOKEN_HEADER = "X-Owntend-Worker-Token";

// Bounded work budget: small batches with bounded concurrency and an overall
// deadline comfortably below the cron request budget (30s), the Edge Runtime
// wall-clock limit, and pg_net defaults.
export const DEFAULT_BATCH_SIZE = 25;
export const MAX_BATCH_SIZE = 25;
export const MAX_CONCURRENT_REMOVALS = 4;
export const OVERALL_DEADLINE_MS = 20_000;

/** Allowlisted technical outcome codes persisted by the queue RPCs. */
export type MediaCleanupErrorCode =
  | "storage_not_found"
  | "storage_error"
  | "storage_timeout"
  | "invalid_path"
  | "rpc_error"
  | "unknown";

export interface MediaCleanupEntry {
  id: number;
  user_id: string;
  object_path: string;
  attempts: number;
}

export interface StorageRemovalOutcome {
  success: boolean;
  absent?: boolean;
  errorCode?: MediaCleanupErrorCode;
}

export interface MediaCleanupServices {
  claimBatch(batchSize: number): Promise<MediaCleanupEntry[]>;
  removeStorageObject(objectPath: string): Promise<StorageRemovalOutcome>;
  acknowledgeCleanup(id: number): Promise<void>;
  recordFailure(
    id: number,
    errorCode: MediaCleanupErrorCode,
    terminal?: boolean,
  ): Promise<void>;
}

interface StorageErrorShape {
  status?: number;
  code?: string | null;
  name?: string | null;
  message?: string | null;
}

/**
 * Classifies a Storage failure into a bounded, allowlisted error code. Only
 * structured status/code fields are inspected; free-form provider text is
 * never parsed beyond a single typed JSON body probe and never persisted.
 */
export function classifyStorageError(error: unknown): MediaCleanupErrorCode {
  const shaped = error as StorageErrorShape | null;
  if (!shaped || typeof shaped !== "object") return "unknown";
  if (shaped.status === 0) return "storage_timeout";
  if (shaped.status === 404) return "storage_not_found";
  const code = (shaped.code ?? shaped.name ?? "").toString().toLowerCase();
  if (code.includes("timeout")) return "storage_timeout";
  return "storage_error";
}

/**
 * Decides whether an already-absent object counts as successful removal.
 * Structured signals only: HTTP 404, or a typed JSON error body whose
 * `error`/`code` field names the canonical not-found codes used by Storage.
 */
export function isAbsentObjectOutcome(error: unknown): boolean {
  const shaped = error as StorageErrorShape | null;
  if (!shaped || typeof shaped !== "object") return false;
  if (shaped.status === 404) return true;
  const typed = (shaped.code ?? "").toString().toLowerCase();
  if (
    typed === "not_found" ||
    typed === "nosuchkey" ||
    typed === "object_not_found"
  ) {
    return true;
  }
  // Some Storage versions wrap not-found in HTTP 400 with a JSON body such
  // as {"error":"not found"}. Probe the typed body once, structurally.
  const message = shaped.message ?? "";
  try {
    const parsed = JSON.parse(message) as { error?: unknown; code?: unknown };
    const bodyCode = (parsed.error ?? parsed.code ?? "")
      .toString()
      .toLowerCase();
    return (
      bodyCode === "not found" ||
      bodyCode === "not_found" ||
      bodyCode === "nosuchkey"
    );
  } catch {
    return false;
  }
}

export class SupabaseMediaCleanupServices implements MediaCleanupServices {
  constructor(
    private readonly client: SupabaseClient,
    private readonly bucketName = "user-media",
  ) {}

  async claimBatch(batchSize: number): Promise<MediaCleanupEntry[]> {
    const bounded = Math.min(Math.max(batchSize, 1), MAX_BATCH_SIZE);
    const { data, error } = await this.client.rpc(
      "claim_media_cleanup_batch",
      { p_batch_size: bounded },
    );
    if (error) {
      throw new Error(`CLAIM_FAILED:${error.code ?? "rpc_error"}`);
    }
    return (data as MediaCleanupEntry[]) ?? [];
  }

  async removeStorageObject(
    objectPath: string,
  ): Promise<StorageRemovalOutcome> {
    // Defensive path contract: only relative object keys inside this worker's
    // bucket may be addressed.
    if (
      objectPath.length === 0 ||
      objectPath.includes("..") ||
      objectPath.startsWith("/") ||
      objectPath.includes("\\")
    ) {
      return { success: false, errorCode: "invalid_path" };
    }

    const { data, error } = await this.client.storage
      .from(this.bucketName)
      .remove([objectPath]);

    if (!error) {
      return { success: true };
    }

    if (isAbsentObjectOutcome(error)) {
      return { success: true, absent: true };
    }
    return { success: false, errorCode: classifyStorageError(error) };
  }

  async acknowledgeCleanup(id: number): Promise<void> {
    const { error } = await this.client.rpc("acknowledge_media_cleanup", {
      p_id: id,
    });
    if (error) {
      throw new Error(`ACK_FAILED:${id}`);
    }
  }

  async recordFailure(
    id: number,
    errorCode: MediaCleanupErrorCode,
    terminal = false,
  ): Promise<void> {
    const { error: rpcError } = await this.client.rpc(
      "record_media_cleanup_failure",
      {
        p_id: id,
        p_error_code: errorCode,
        p_terminal: terminal,
      },
    );
    if (rpcError) {
      throw new Error(`FAILURE_RECORD_FAILED:${id}`);
    }
  }
}

export interface BatchOutcome {
  processed: number;
  succeeded: number;
  failed: number;
}

export async function processMediaCleanupBatch(
  services: MediaCleanupServices,
  batchSize = DEFAULT_BATCH_SIZE,
  deadline: number = Date.now() + OVERALL_DEADLINE_MS,
): Promise<BatchOutcome> {
  const entries = await services.claimBatch(
    Math.min(Math.max(batchSize, 1), MAX_BATCH_SIZE),
  );
  let succeeded = 0;
  let failed = 0;
  let cursor = 0;

  // Bounded-concurrency worker pool; stops scheduling when the overall
  // deadline is reached so the invocation always answers within budget.
  const workers = Array.from(
    { length: Math.min(MAX_CONCURRENT_REMOVALS, entries.length) },
    async () => {
      while (cursor < entries.length && Date.now() < deadline) {
        const entry = entries[cursor++];
        try {
          const result = await services.removeStorageObject(entry.object_path);
          if (result.success) {
            await services.acknowledgeCleanup(entry.id);
            succeeded++;
          } else {
            const isTerminal = entry.attempts >= 5;
            if (isTerminal) {
              console.warn(
                `[media_cleanup_terminal_failure] Entry ${entry.id} reached terminal failure for object: ${result.errorCode ?? "storage_error"}`,
              );
            }
            await services.recordFailure(
              entry.id,
              result.errorCode ?? "storage_error",
              isTerminal,
            );
            failed++;
          }
        } catch (_err) {
          // RPC failures during ack/record leave the row claimed until its
          // lease expires; the next invocation retries it. No raw payload is
          // reported.
          failed++;
        }
      }
    },
  );

  await Promise.all(workers);

  // Entries never scheduled because of the deadline remain claimed under a
  // five-minute lease and are retried by the next invocation.
  const processed = succeeded + failed;
  return { processed, succeeded, failed };
}

export function verifyWorkerAuthority(req: Request): WorkerAuthorityResult {
  if (req.method !== "POST") {
    return { authorized: false, statusCode: 405, error: "Method not allowed" };
  }
  const contentType = req.headers.get("Content-Type") ?? "";
  if (
    contentType.length > 0 &&
    !contentType.toLowerCase().startsWith("application/json")
  ) {
    return {
      authorized: false,
      statusCode: 415,
      error: "Unsupported media type",
    };
  }

  const token = req.headers.get(WORKER_TOKEN_HEADER) ?? "";
  const configuredSecret = Deno.env.get("OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN") ??
    "";
  if (configuredSecret.length === 0) {
    // Fail closed: without a provisioned capability nothing may run.
    return { authorized: false, statusCode: 403, error: "Forbidden" };
  }
  if (token.length === 0) {
    return { authorized: false, statusCode: 401, error: "Unauthorized" };
  }
  if (!constantTimeEquals(token, configuredSecret)) {
    return { authorized: false, statusCode: 403, error: "Forbidden" };
  }
  return { authorized: true };
}

function constantTimeEquals(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const aBytes = encoder.encode(a);
  const bBytes = encoder.encode(b);
  // Compare a fixed number of bytes so token length does not leak timing.
  const length = Math.max(aBytes.length, bBytes.length);
  let mismatch = aBytes.length === bBytes.length ? 0 : 1;
  for (let i = 0; i < length; i++) {
    mismatch |= (aBytes[i] ?? 0) ^ (bBytes[i] ?? 0);
  }
  return mismatch === 0;
}

function isValidRequestShape(contentLength: number): boolean {
  // Worker invocations carry no meaningful body; reject oversized payloads.
  return contentLength <= 1024;
}

export function createHandler(
  servicesFactory: (req: Request) => MediaCleanupServices,
  reporterFactory: (req: Request) => EdgeExceptionReporter = (_req) =>
    createEdgeExceptionReporter("process-media-cleanup"),
  authority: WorkerAuthority = verifyWorkerAuthority,
) {
  return async (req: Request): Promise<Response> => {
    // Browser/CORS use is never supported for this service-to-service
    // endpoint; no CORS headers are emitted on any response.
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: jsonHeaders,
      });
    }
    const contentLength = Number(req.headers.get("Content-Length") ?? "0");
    if (!Number.isNaN(contentLength) && !isValidRequestShape(contentLength)) {
      return new Response(JSON.stringify({ error: "Payload too large" }), {
        status: 413,
        headers: jsonHeaders,
      });
    }

    const authorityResult = await authority(req);
    if (!authorityResult.authorized) {
      const reporter = reporterFactory(req);
      if (authorityResult.reportRejection) {
        await reporter(
          new Error(
            `worker_authority_rejected:${authorityResult.statusCode ?? 403}`,
          ),
          { stage: "authorize_worker" },
        );
      }
      return new Response(
        JSON.stringify({ error: authorityResult.error ?? "Unauthorized" }),
        {
          status: authorityResult.statusCode ?? 401,
          headers: jsonHeaders,
        },
      );
    }

    const reporter = reporterFactory(req);
    try {
      const services = servicesFactory(req);
      const url = new URL(req.url);
      const requestedBatch = parseInt(url.searchParams.get("batch") ?? "", 10);
      const batchSize = Number.isNaN(requestedBatch)
        ? DEFAULT_BATCH_SIZE
        : requestedBatch;

      const result = await processMediaCleanupBatch(services, batchSize);
      return new Response(JSON.stringify({ success: true, ...result }), {
        status: 200,
        headers: jsonHeaders,
      });
    } catch (error) {
      await reporter(error, {
        stage: "process_media_cleanup",
      });
      return new Response(
        JSON.stringify({
          success: false,
          error: "Internal server error during media cleanup",
        }),
        {
          status: 500,
          headers: jsonHeaders,
        },
      );
    }
  };
}

export interface WorkerAuthorityResult {
  authorized: boolean;
  statusCode?: number;
  error?: string;
  reportRejection?: boolean;
}

export type WorkerAuthority = (
  req: Request,
) => WorkerAuthorityResult | Promise<WorkerAuthorityResult>;

if (import.meta.main) {
  const handler = createHandler((_req) => {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const client = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    return new SupabaseMediaCleanupServices(client);
  });

  Deno.serve(handler);
}
