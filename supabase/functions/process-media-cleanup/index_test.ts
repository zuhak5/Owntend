import { assertEquals } from "@std/assert";
import {
  classifyStorageError,
  createHandler,
  DEFAULT_BATCH_SIZE,
  isAbsentObjectOutcome,
  type MediaCleanupEntry,
  type MediaCleanupErrorCode,
  type MediaCleanupServices,
  processMediaCleanupBatch,
  verifyWorkerAuthority,
  WORKER_TOKEN_HEADER,
} from "./index.ts";

class MockMediaCleanupServices implements MediaCleanupServices {
  entries: MediaCleanupEntry[] = [];
  storageObjects = new Set<string>();
  acknowledged = new Set<number>();
  failures = new Map<number, { error: string; terminal: boolean }>();
  storageFailures = new Set<string>();
  claimedBatchSizes: number[] = [];

  async claimBatch(batchSize: number): Promise<MediaCleanupEntry[]> {
    this.claimedBatchSizes.push(batchSize);
    return this.entries.slice(0, batchSize);
  }

  async removeStorageObject(objectPath: string): Promise<{
    success: boolean;
    absent?: boolean;
    errorCode?: MediaCleanupErrorCode;
  }> {
    if (this.storageFailures.has(objectPath)) {
      return { success: false, errorCode: "storage_error" };
    }
    if (!this.storageObjects.has(objectPath)) {
      return { success: true, absent: true };
    }
    this.storageObjects.delete(objectPath);
    return { success: true };
  }

  async acknowledgeCleanup(id: number): Promise<void> {
    this.acknowledged.add(id);
  }

  async recordFailure(
    id: number,
    error: MediaCleanupErrorCode,
    terminal = false,
  ): Promise<void> {
    this.failures.set(id, { error, terminal });
  }
}

function workerRequest(
  url = "https://localhost/process-media-cleanup",
  extraHeaders: Record<string, string> = {},
): Request {
  return new Request(url, {
    method: "POST",
    headers: {
      [WORKER_TOKEN_HEADER]: "worker-capability-secret",
      ...extraHeaders,
    },
  });
}

Deno.test("processMediaCleanupBatch: cleans up storage objects and acknowledges queue rows", async () => {
  const services = new MockMediaCleanupServices();
  services.entries = [
    { id: 1, user_id: "u1", object_path: "u1/media/photo1.jpg", attempts: 1 },
    { id: 2, user_id: "u1", object_path: "u1/media/photo2.jpg", attempts: 1 },
  ];
  services.storageObjects.add("u1/media/photo1.jpg");
  services.storageObjects.add("u1/media/photo2.jpg");

  const result = await processMediaCleanupBatch(services, 10);
  assertEquals(result.processed, 2);
  assertEquals(result.succeeded, 2);
  assertEquals(result.failed, 0);
  assertEquals(services.acknowledged.has(1), true);
  assertEquals(services.acknowledged.has(2), true);
  assertEquals(services.storageObjects.size, 0);
});

Deno.test("processMediaCleanupBatch: claims bounded batches only", async () => {
  const services = new MockMediaCleanupServices();
  services.claimBatch = (batchSize: number) => {
    services.claimedBatchSizes.push(batchSize);
    return Promise.resolve([]);
  };

  await processMediaCleanupBatch(services, 500);
  assertEquals(
    services.claimedBatchSizes.every((size) => size <= DEFAULT_BATCH_SIZE),
    true,
    "oversized batch requests are clamped to the worker budget",
  );
});

Deno.test("processMediaCleanupBatch: treats object not found as idempotent success", async () => {
  const services = new MockMediaCleanupServices();
  services.entries = [
    { id: 1, user_id: "u1", object_path: "u1/media/missing.jpg", attempts: 1 },
  ];

  const result = await processMediaCleanupBatch(services, 10);
  assertEquals(result.processed, 1);
  assertEquals(result.succeeded, 1);
  assertEquals(result.failed, 0);
  assertEquals(services.acknowledged.has(1), true);
});

Deno.test("processMediaCleanupBatch: records allowlisted codes and terminal state at attempts >= 5", async () => {
  const services = new MockMediaCleanupServices();
  services.entries = [
    { id: 1, user_id: "u1", object_path: "u1/media/fail1.jpg", attempts: 2 },
    { id: 2, user_id: "u1", object_path: "u1/media/fail2.jpg", attempts: 5 },
  ];
  services.storageFailures.add("u1/media/fail1.jpg");
  services.storageFailures.add("u1/media/fail2.jpg");

  const result = await processMediaCleanupBatch(services, 10);
  assertEquals(result.processed, 2);
  assertEquals(result.succeeded, 0);
  assertEquals(result.failed, 2);
  assertEquals(services.acknowledged.size, 0);
  assertEquals(services.failures.get(1)?.error, "storage_error");
  assertEquals(services.failures.get(1)?.terminal, false);
  assertEquals(services.failures.get(2)?.error, "storage_error");
  assertEquals(services.failures.get(2)?.terminal, true);
});

Deno.test("HTTP handler: rejects missing, wrong, and non-worker credentials", async () => {
  const services = new MockMediaCleanupServices();
  const handler = createHandler(
    () => services,
    () => async () => {},
  );

  // No capability header at all.
  Deno.env.set(
    "OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN",
    "worker-capability-secret",
  );
  const noAuthRes = await handler(
    new Request("https://localhost/process-media-cleanup", { method: "POST" }),
  );
  assertEquals(noAuthRes.status, 401);
  Deno.env.delete("OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN");

  // Wrong capability value.
  const wrongRes = await handler(
    new Request(
      "https://localhost/process-media-cleanup",
      {
        method: "POST",
        headers: { [WORKER_TOKEN_HEADER]: "wrong-value" },
      },
    ),
  );
  assertEquals(wrongRes.status, 403);

  // A well-formed user/anon JWT carries no worker capability: without the
  // dedicated header the request is unauthenticated, never authorized.
  Deno.env.set(
    "OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN",
    "worker-capability-secret",
  );
  const bearerRes = await handler(
    new Request(
      "https://localhost/process-media-cleanup",
      {
        method: "POST",
        headers: { Authorization: "Bearer eyJhbGciOiJub25lIn9.anon.signature" },
      },
    ),
  );
  assertEquals(bearerRes.status, 401);
  Deno.env.delete("OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN");

  Deno.env.set(
    "OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN",
    "worker-capability-secret",
  );
  const validRes = await handler(
    workerRequest("https://localhost/process-media-cleanup?batch=20"),
  );
  assertEquals(validRes.status, 200);
  const data = await validRes.json();
  assertEquals(data.success, true);
  assertEquals(typeof data.processed, "number");
  Deno.env.delete("OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN");
});

Deno.test("HTTP handler: rejects non-POST, oversized payloads, and non-JSON content types", async () => {
  const services = new MockMediaCleanupServices();
  const handler = createHandler(() => services);

  const getRes = await handler(
    new Request("https://localhost/process-media-cleanup", { method: "GET" }),
  );
  assertEquals(getRes.status, 405);

  const tooLarge = await handler(workerRequest(
    "https://localhost/process-media-cleanup",
    { "Content-Length": "999999" },
  ));
  assertEquals(tooLarge.status, 413);

  const formRes = await handler(workerRequest(
    "https://localhost/process-media-cleanup",
    { "Content-Type": "text/plain" },
  ));
  assertEquals(formRes.status, 415);
  const corsHeader = formRes.headers.get("Access-Control-Allow-Origin");
  assertEquals(corsHeader, null, "no CORS headers are ever emitted");
});

Deno.test("verifyWorkerAuthority: fails closed without configured authority", () => {
  Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
  Deno.env.delete("OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN");
  Deno.env.delete("MEDIA_CLEANUP_WORKER_TOKEN");
  const req = new Request("https://localhost/process-media-cleanup", {
    method: "POST",
    headers: { [WORKER_TOKEN_HEADER]: "anything" },
  });
  const result = verifyWorkerAuthority(req);
  assertEquals(result.authorized, false);
  assertEquals(result.statusCode, 403);
});

Deno.test("verifyWorkerAuthority: accepts only the exact dedicated capability", () => {
  Deno.env.set("OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN", "dedicated-worker-secret");
  const req = new Request("https://localhost/process-media-cleanup", {
    method: "POST",
    headers: { [WORKER_TOKEN_HEADER]: "dedicated-worker-secret" },
  });
  const result = verifyWorkerAuthority(req);
  assertEquals(result.authorized, true);
  Deno.env.delete("OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN");

  // The service-role key is NOT accepted as scheduler authority.
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-role-key");
  const serviceRoleReq = new Request(
    "https://localhost/process-media-cleanup",
    {
      method: "POST",
      headers: { [WORKER_TOKEN_HEADER]: "service-role-key" },
    },
  );
  const denied = verifyWorkerAuthority(serviceRoleReq);
  assertEquals(denied.authorized, false);
  assertEquals(denied.statusCode, 403);
  Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
});

Deno.test("Storage outcome classification uses structured signals only", () => {
  // HTTP 404 status is absent-object success.
  assertEquals(isAbsentObjectOutcome({ status: 404 }), true);
  // Structured typed body naming not-found is absent-object success.
  assertEquals(
    isAbsentObjectOutcome({
      status: 400,
      message: JSON.stringify({ error: "not found" }),
    }),
    true,
  );
  assertEquals(isAbsentObjectOutcome({ code: "NoSuchKey" }), true);
  // Free-form provider text without structured fields stays a failure.
  assertEquals(
    isAbsentObjectOutcome({ message: "object not found somewhere" }),
    false,
  );
  assertEquals(classifyStorageError({ status: 0 }), "storage_timeout");
  assertEquals(classifyStorageError({ status: 500 }), "storage_error");
  assertEquals(classifyStorageError(null), "unknown");
});
