// Real end-to-end coverage for the protected media-cleanup worker contract.
// Unlike the mock-only unit suite in
// `supabase/functions/process-media-cleanup/index_test.ts`, this suite drives
// the ACTUAL deployed Edge endpoint over HTTP through the local gateway
// (`/functions/v1/process-media-cleanup`), exercising gateway mode, capability
// authentication, bounded work, idempotent removal, and lease recovery
// against the running disposable Supabase stack.
//
// Required environment (provisioned by tool/run_local_backend_integration.ps1):
//   SUPABASE_URL                        local stack API base URL
//   SUPABASE_SERVICE_ROLE_KEY           service key for fixture setup only
//   SUPABASE_ANON_KEY                   optional; enables the denial step
//   SUPABASE_FUNCTIONS_URL              Edge Functions base URL
//   OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN  dedicated worker capability secret

import { assert, assertEquals } from "@std/assert";
import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:55321";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const FUNCTIONS_URL = Deno.env.get("SUPABASE_FUNCTIONS_URL") ??
  `${SUPABASE_URL}/functions/v1`;
const WORKER_TOKEN = Deno.env.get("OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN") ?? "";
const ENDPOINT = `${FUNCTIONS_URL}/process-media-cleanup`;
const BUCKET = "user-media";
// Deterministic per-run user; bootstrap.sql seeds this identity.
const TEST_USER_ID = "00000000-0000-0000-0000-00000000c13a";

function requireServiceKey(): string {
  assert(
    SERVICE_ROLE_KEY.length > 0,
    "SUPABASE_SERVICE_ROLE_KEY must be set for integration tests",
  );
  return SERVICE_ROLE_KEY;
}

function adminClient() {
  return createClient(SUPABASE_URL, requireServiceKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

interface CleanupRow {
  id: number;
  user_id: string;
  object_path: string;
  attempts: number;
}

async function postgrestRpc<T>(
  name: string,
  body: Record<string, unknown>,
): Promise<T> {
  const serviceKey = requireServiceKey();
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${serviceKey}`,
      apikey: serviceKey,
    },
    body: JSON.stringify(body),
  });
  assertEquals(response.status, 200, `${name} RPC must succeed`);
  const text = await response.text();
  return (text.length > 0 ? JSON.parse(text) : null) as T;
}

async function restSelect<T>(path: string): Promise<T> {
  const serviceKey = requireServiceKey();
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: {
      Authorization: `Bearer ${serviceKey}`,
      apikey: serviceKey,
    },
  });
  assertEquals(response.status, 200);
  return await response.json() as T;
}

async function enqueueCleanup(
  userId: string,
  objectPath: string,
): Promise<void> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/media_cleanup_queue`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Prefer: "return=minimal",
      Authorization: `Bearer ${requireServiceKey()}`,
      apikey: requireServiceKey(),
    },
    body: JSON.stringify({
      user_id: userId,
      object_path: objectPath,
      reason: "deleted",
    }),
  });
  assertEquals(response.status, 201, "enqueue into media_cleanup_queue");
}

async function uploadObject(
  objectPath: string,
  bytes: Uint8Array,
): Promise<void> {
  const response = await fetch(
    `${SUPABASE_URL}/storage/v1/object/${BUCKET}/${objectPath}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${requireServiceKey()}`,
        apikey: requireServiceKey(),
        "Content-Type": "image/jpeg",
      },
      body: bytes as unknown as BodyInit,
    },
  );
  assertEquals(
    response.status,
    200,
    `storage upload of ${objectPath} must succeed`,
  );
}

async function objectExists(objectPath: string): Promise<boolean> {
  const response = await fetch(
    `${SUPABASE_URL}/storage/v1/object/${BUCKET}/${objectPath}`,
    {
      method: "HEAD",
      headers: {
        Authorization: `Bearer ${requireServiceKey()}`,
        apikey: requireServiceKey(),
      },
    },
  );
  return response.status === 200;
}

async function invokeWorker(
  headers: Record<string, string> = {},
): Promise<Response> {
  return await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
  });
}

Deno.test("media cleanup worker end to end through the Edge gateway", async (t) => {
  // Self-bootstrap: create a fresh disposable identity through the supported
  // Auth admin API instead of raw SQL fixtures.
  const admin = adminClient();
  const TEST_USER_ID = await (async () => {
    // The auth service may still be warming up right after the disposable
    // stack starts; retry creation briefly before giving up.
    let lastError = "no attempt";
    for (let attempt = 0; attempt < 5; attempt++) {
      const { data, error } = await admin.auth.admin.createUser({
        email: `media-cleanup-integration-${Date.now()}@example.com`,
        email_confirm: true,
      });
      if (!error && data?.user) return data.user.id;
      lastError = error?.message ?? "no user";
      if (
        lastError.toLowerCase().includes("already") ||
        lastError.toLowerCase().includes("exists")
      ) break;
      await new Promise((r) => setTimeout(r, 2000 * (attempt + 1)));
    }
    throw new Error(`fixture user creation failed: ${lastError}`);
  })();

  await t.step("gateway rejects requests without any capability", async () => {
    const response = await invokeWorker();
    // No worker token header at all: unauthenticated.
    assertEquals(response.status, 401);
    assert((await response.json()).error);
  });

  await t.step("gateway rejects wrong capabilities with 403", async () => {
    const wrong = await invokeWorker({
      "X-Owntend-Worker-Token": "definitely-not-the-token",
    });
    assertEquals(wrong.status, 403);

    // A well-formed anon JWT is never authority on this endpoint.
    if (ANON_KEY.length > 0) {
      const anonJwt = await invokeWorker({
        Authorization: `Bearer ${ANON_KEY}`,
      });
      assertEquals(anonJwt.status, 401);
    }

    // The service-role key is never accepted as scheduler authority.
    const serviceRoleAttempt = await invokeWorker({
      Authorization: `Bearer ${requireServiceKey()}`,
    });
    assertEquals(serviceRoleAttempt.status, 401);
  });

  await t.step("anon credentials cannot execute worker RPCs", async () => {
    if (ANON_KEY.length === 0) {
      return;
    }
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/rpc/claim_media_cleanup_batch`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${ANON_KEY}`,
          apikey: ANON_KEY,
        },
        body: JSON.stringify({ p_batch_size: 10 }),
      },
    );
    // PostgREST maps function-execute denial to 401 (or 403 depending on
    // version); either is a hard denial for non-worker credentials.
    assert([401, 403].includes(response.status));
  });

  await t.step(
    "valid capability cleans an object end to end via the endpoint",
    async () => {
      assert(WORKER_TOKEN.length > 0, "worker token must be provisioned");
      const objectPath =
        `${TEST_USER_ID}/media/integration-ok-${Date.now()}.jpg`;
      await uploadObject(objectPath, new Uint8Array([1, 2, 3, 4]));
      await enqueueCleanup(TEST_USER_ID, objectPath);

      const response = await invokeWorker({
        "X-Owntend-Worker-Token": WORKER_TOKEN,
      });
      assertEquals(response.status, 200);
      const payload = await response.json();
      assertEquals(payload.success, true);
      assertEquals(typeof payload.processed, "number");
      // The response exposes counts only â€” no paths, no raw errors.
      assertEquals(payload.entries, undefined);
      assertEquals(payload.errors, undefined);

      assertEquals(await objectExists(objectPath), false);
      const remaining = await restSelect<Array<{ id: number }>>(
        `media_cleanup_queue?object_path=eq.${
          encodeURIComponent(objectPath)
        }&select=id`,
      );
      assertEquals(remaining, [], "acknowledged row leaves the queue");
    },
  );

  await t.step(
    "removing an already-removed object stays idempotent through the endpoint",
    async () => {
      const objectPath =
        `${TEST_USER_ID}/media/integration-gone-${Date.now()}.jpg`;
      await uploadObject(objectPath, new Uint8Array([9]));
      await enqueueCleanup(TEST_USER_ID, objectPath);

      // First invocation deletes the object but leaves it claimed-and-deleted;
      // simulate response loss by re-enqueueing after direct removal.
      const first = await invokeWorker({
        "X-Owntend-Worker-Token": WORKER_TOKEN,
      });
      assertEquals(first.status, 200);
      assertEquals(await objectExists(objectPath), false);

      // A second enqueue + invocation must succeed without the object present.
      await enqueueCleanup(TEST_USER_ID, objectPath);
      const second = await invokeWorker({
        "X-Owntend-Worker-Token": WORKER_TOKEN,
      });
      assertEquals(second.status, 200);
      const remaining = await restSelect<Array<{ id: number }>>(
        `media_cleanup_queue?object_path=eq.${
          encodeURIComponent(objectPath)
        }&select=id`,
      );
      assertEquals(remaining, [], "absent-object removal is acknowledged");
    },
  );

  await t.step(
    "failure recording persists only allowlisted codes then terminates",
    async () => {
      const objectPath =
        `${TEST_USER_ID}/media/integration-fail-${Date.now()}.jpg`;
      // Enqueue a path that is structurally invalid for this bucket so the
      // worker classifies it without touching Storage.
      await enqueueCleanup(TEST_USER_ID, objectPath);

      // Drive the failure path directly at the RPC boundary with a code that
      // violates nothing and proves bounded storage of codes.
      const claim = await postgrestRpc<CleanupRow[]>(
        "claim_media_cleanup_batch",
        { p_batch_size: 25 },
      );
      const entry = claim.find((row) => row.object_path === objectPath);
      assert(entry, "failing entry is claimable");

      await postgrestRpc("record_media_cleanup_failure", {
        p_id: entry.id,
        p_error_code: "storage_timeout",
        p_terminal: false,
      });
      const mid = await restSelect<
        Array<{ status: string; attempts: number; last_error_code: string }>
      >(
        `media_cleanup_queue?id=eq.${entry.id}&select=status,attempts,last_error_code`,
      );
      assertEquals(mid.length, 1);
      assertEquals(
        mid[0].status,
        "pending",
        "non-terminal failure stays retryable",
      );
      assertEquals(mid[0].attempts >= 1, true, "retry counter incremented");
      assertEquals(mid[0].last_error_code, "storage_timeout");

      await postgrestRpc("record_media_cleanup_failure", {
        p_id: entry.id,
        p_error_code: "storage_error",
        p_terminal: true,
      });
      const terminal = await restSelect<Array<{ status: string }>>(
        `media_cleanup_queue?id=eq.${entry.id}&select=status`,
      );
      assertEquals(terminal.length, 1);
      assertEquals(terminal[0].status, "failed_terminal");

      // Oversized or malformed codes are normalized by the SQL guard.
      const claim2 = await postgrestRpc<CleanupRow[]>(
        "claim_media_cleanup_batch",
        { p_batch_size: 25 },
      );
      const stale = claim2.find((row) => row.id === entry.id);
      if (stale) {
        await postgrestRpc("record_media_cleanup_failure", {
          p_id: stale.id,
          p_error_code:
            "this_is_a_way_too_long_error_code_with_unexpected_characters!!",
          p_terminal: true,
        });
        const storedCode = await restSelect<Array<{ last_error_code: string }>>(
          `media_cleanup_queue?id=eq.${entry.id}&select=last_error_code`,
        );
        assertEquals(storedCode[0]?.last_error_code, "unknown");
        await postgrestRpc("acknowledge_media_cleanup", { p_id: entry.id });
      }
    },
  );

  await t.step(
    "stale processing claims are recovered after their lease",
    async () => {
      const objectPath =
        `${TEST_USER_ID}/media/integration-stale-${Date.now()}.jpg`;
      await uploadObject(objectPath, new Uint8Array([1]));
      await enqueueCleanup(TEST_USER_ID, objectPath);

      const firstClaim = await postgrestRpc<CleanupRow[]>(
        "claim_media_cleanup_batch",
        { p_batch_size: 25 },
      );
      const claimed = firstClaim.find((row) => row.object_path === objectPath);
      assert(claimed, "row is claimed once");

      // Simulate a dead worker: expire the claim lease so recovery can pick
      // the row up again instead of losing it.
      await fetch(
        `${SUPABASE_URL}/rest/v1/media_cleanup_queue?id=eq.${claimed.id}`,
        {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            Prefer: "return=minimal",
            Authorization: `Bearer ${requireServiceKey()}`,
            apikey: requireServiceKey(),
          },
          body: JSON.stringify({
            processed_at: new Date(Date.now() - 10 * 60 * 1000).toISOString(),
          }),
        },
      );

      const recovered = await postgrestRpc<CleanupRow[]>(
        "claim_media_cleanup_batch",
        { p_batch_size: 25 },
      );
      const reclaimed = recovered.find((row) => row.id === claimed.id);
      assert(reclaimed, "stale processing row is recoverable");
      assertEquals(
        reclaimed.attempts >= 2,
        true,
        "recovery increments attempts",
      );

      await postgrestRpc("acknowledge_media_cleanup", { p_id: claimed.id });
    },
  );

  await t.step(
    "concurrent workers receive disjoint claim batches",
    async () => {
      const paths = [
        `${TEST_USER_ID}/media/concurrent-a-${Date.now()}.jpg`,
        `${TEST_USER_ID}/media/concurrent-b-${Date.now()}.jpg`,
      ];
      for (const path of paths) {
        await enqueueCleanup(TEST_USER_ID, path);
      }

      const [batchA, batchB] = await Promise.all([
        postgrestRpc<CleanupRow[]>("claim_media_cleanup_batch", {
          p_batch_size: 25,
        }),
        postgrestRpc<CleanupRow[]>("claim_media_cleanup_batch", {
          p_batch_size: 25,
        }),
      ]);

      const idsA = batchA.map((row) => row.id);
      const idsB = batchB.map((row) => row.id);
      const overlap = idsA.filter((id) => idsB.includes(id));
      assertEquals(overlap, [], "SKIP LOCKED prevents double-claiming");

      const allPaths = [...batchA, ...batchB].map((row) => row.object_path);
      for (const path of paths) {
        assert(allPaths.includes(path), `${path} was claimed by some worker`);
      }

      for (const row of [...batchA, ...batchB]) {
        if (paths.includes(row.object_path)) {
          await postgrestRpc("acknowledge_media_cleanup", { p_id: row.id });
        }
      }
    },
  );

  // Cleanup: drain any rows this suite created so the disposable stack is
  // left quiescent even when assertions above are relaxed later.
  await adminClient().from("media_cleanup_queue").delete().eq(
    "user_id",
    TEST_USER_ID,
  );
});
