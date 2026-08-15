import { assertEquals, assertMatch } from "@std/assert";

import {
  type AccountDeletionOperationStage,
  type AccountDeletionServices,
  handleDeleteAccount,
  type ServiceFactory,
} from "./index.ts";

const userId = "11111111-1111-4111-8111-111111111111";
const sessionId = "22222222-2222-4222-8222-222222222222";
const operationId = "44444444-4444-4444-8444-444444444444";
const recoveryKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
const validToken = jwtWithSession(sessionId);
const productionOrigin = "https://owntend.app";
const configuredEnvironment = {
  get: (key: string): string | undefined =>
    ({
      SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_ANON_KEY: "anon-test-key",
      SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key",
    })[key],
};
const emptyEnvironment = {
  get: (_key: string): undefined => undefined,
};

Deno.test("rejects non-POST methods before reading credentials", async () => {
  const response = await handleDeleteAccount(
    new Request("http://localhost/delete-account"),
    emptyEnvironment,
  );

  assertEquals(response.status, 405);
  assertEquals(await response.json(), { error: "method_not_allowed" });
  assertMatch(response.headers.get("content-type") ?? "", /application\/json/);
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(response.headers.get("access-control-allow-origin"), null);
});

Deno.test("answers preflight for each exact browser origin", async () => {
  for (
    const origin of [
      productionOrigin,
      "http://localhost:4173",
      "http://127.0.0.1:4173",
    ]
  ) {
    const response = await handleDeleteAccount(
      new Request("http://localhost/delete-account", {
        method: "OPTIONS",
        headers: {
          Origin: origin,
          "Access-Control-Request-Method": "POST",
          "Access-Control-Request-Headers": "authorization,apikey,content-type",
        },
      }),
      emptyEnvironment,
    );

    assertEquals(response.status, 204);
    assertEquals(response.headers.get("access-control-allow-origin"), origin);
    assertEquals(
      response.headers.get("access-control-allow-methods"),
      "POST, OPTIONS",
    );
    assertEquals(
      response.headers.get("access-control-allow-headers"),
      "authorization, apikey, content-type, x-client-info",
    );
    assertEquals(response.headers.get("vary"), "Origin");
  }
});

Deno.test("rejects missing or non-allowlisted preflight origins", async () => {
  for (
    const origin of [
      null,
      "https://example.com",
      "https://owntend.app.evil.example",
    ]
  ) {
    const headers = new Headers();
    if (origin != null) headers.set("Origin", origin);
    const response = await handleDeleteAccount(
      new Request("http://localhost/delete-account", {
        method: "OPTIONS",
        headers,
      }),
      emptyEnvironment,
    );

    assertEquals(response.status, 403);
    assertEquals(await response.json(), { error: "origin_not_allowed" });
    assertEquals(response.headers.get("access-control-allow-origin"), null);
  }
});

Deno.test("rejects an untrusted browser origin before authorization", async () => {
  const response = await handleDeleteAccount(
    deletionRequest({ origin: "https://attacker.example" }),
    emptyEnvironment,
  );

  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: "origin_not_allowed" });
  assertEquals(response.headers.get("access-control-allow-origin"), null);
});

Deno.test("adds CORS headers to errors for an allowed browser origin", async () => {
  const response = await handleDeleteAccount(
    deletionRequest({ includeAuthorization: false, origin: productionOrigin }),
    emptyEnvironment,
  );

  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "missing_authorization" });
  assertEquals(
    response.headers.get("access-control-allow-origin"),
    productionOrigin,
  );
  assertEquals(response.headers.get("vary"), "Origin");
});

Deno.test("preserves authenticated native deletion without an Origin header", async () => {
  const services = new FakeAccountDeletionServices();
  services.objectListings.push([]);

  const response = await handleDeleteAccount(
    deletionRequest(),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    deleted: true,
    status: "deleted",
    user_id: userId,
  });
  assertEquals(response.headers.get("access-control-allow-origin"), null);
});

Deno.test("requires a bearer authorization header", async () => {
  const response = await handleDeleteAccount(
    deletionRequest({ includeAuthorization: false }),
    emptyEnvironment,
  );

  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "missing_authorization" });
});

Deno.test("requires an explicit deletion confirmation payload", async () => {
  const response = await handleDeleteAccount(
    deletionRequest({ confirmation: "not-confirmed" }),
    emptyEnvironment,
  );

  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "confirmation_required" });
});

Deno.test("requires a 256-bit recovery capability", async () => {
  for (const candidate of [null, "short", "!".repeat(43)]) {
    const response = await handleDeleteAccount(
      deletionRequest({ recoveryKey: candidate }),
      emptyEnvironment,
    );

    assertEquals(response.status, 400);
    assertEquals(await response.json(), { error: "recovery_key_required" });
  }
});

Deno.test("fails closed when server credentials are unavailable", async () => {
  const reports: Array<{ context: { stage: string } }> = [];
  const response = await handleDeleteAccount(
    deletionRequest(),
    emptyEnvironment,
    undefined,
    {
      reportException: (_error, context) => {
        reports.push({ context: { stage: context.stage } });
        return Promise.resolve();
      },
    },
  );

  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: "server_configuration_error" });
  assertEquals(reports, [{ context: { stage: "configuration" } }]);
});

Deno.test("rejects a token without a valid session id", async () => {
  const response = await handleDeleteAccount(
    deletionRequest({ token: "not-a-jwt" }),
    configuredEnvironment,
  );

  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "invalid_session" });
});

Deno.test("requires a recent reauthenticated session", async () => {
  const services = new FakeAccountDeletionServices();
  services.recentSession = false;

  const response = await handleDeleteAccount(
    deletionRequest(),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 403);
  assertEquals(await response.json(), {
    error: "recent_reauthentication_required",
  });
  assertEquals(services.events, [
    "get_user",
    `recent_session:${userId}:${sessionId}`,
  ]);
});

Deno.test("deletes only the user derived from the verified JWT", async () => {
  const services = new FakeAccountDeletionServices();
  services.objectListings.push(
    [`${userId}/assets/photo.jpg`],
    [`${userId}/assets/photo.jpg`],
    [],
  );

  const response = await handleDeleteAccount(
    deletionRequest({
      origin: productionOrigin,
      extraBody: {
        user_id: "99999999-9999-4999-8999-999999999999",
      },
    }),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    deleted: true,
    status: "deleted",
    user_id: userId,
  });
  assertEquals(
    response.headers.get("access-control-allow-origin"),
    productionOrigin,
  );
  assertEquals(services.events, [
    "get_user",
    `recent_session:${userId}:${sessionId}`,
    `begin_operation:${userId}`,
    `list:${userId}`,
    `begin:${userId}:1`,
    "advance:storage_cleanup",
    `list:${userId}`,
    "remove:1",
    `list:${userId}`,
    "complete_cleanup",
    "advance:storage_complete",
    "advance:auth_delete_started",
    `delete_user:${userId}`,
    "complete_operation",
  ]);
});

Deno.test("an already-completed operation returns the strict receipt", async () => {
  const services = new FakeAccountDeletionServices();
  services.operationCompleted = true;

  const response = await handleDeleteAccount(
    deletionRequest(),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    deleted: true,
    status: "deleted",
    user_id: userId,
  });
  assertEquals(services.events, [
    "get_user",
    `recent_session:${userId}:${sessionId}`,
    `begin_operation:${userId}`,
  ]);
});

Deno.test("an already-acknowledged operation returns the strict receipt", async () => {
  const services = new FakeAccountDeletionServices();
  services.operationStage = "acknowledged";

  const response = await handleDeleteAccount(
    deletionRequest(),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    deleted: true,
    status: "deleted",
    user_id: userId,
  });
  assertEquals(services.events, [
    "get_user",
    `recent_session:${userId}:${sessionId}`,
    `begin_operation:${userId}`,
  ]);
});

Deno.test("does not delete Auth when Storage cleanup fails", async () => {
  const services = new FakeAccountDeletionServices();
  services.objectListings.push(
    [`${userId}/assets/photo.jpg`],
    [`${userId}/assets/photo.jpg`],
  );
  services.removeError = new Error("forced storage failure");

  const response = await handleDeleteAccount(
    deletionRequest(),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: "storage_cleanup_failed" });
  assertEquals(
    services.events.some((event) => event.startsWith("delete_user:")),
    false,
  );
  assertEquals(
    services.events.includes("record_error:remove_storage_failed"),
    true,
  );
  assertEquals(
    services.events.includes("record_operation_error:remove_storage_failed"),
    true,
  );
});

Deno.test("reports destructive backend failures through the injected reporter", async () => {
  const services = new FakeAccountDeletionServices();
  services.objectListings.push(
    [`${userId}/assets/photo.jpg`],
    [`${userId}/assets/photo.jpg`],
  );
  services.removeError = new Error("forced storage failure");
  const reports: Array<
    { stage: string; extras: Record<string, unknown> | undefined }
  > = [];

  const response = await handleDeleteAccount(
    deletionRequest(),
    configuredEnvironment,
    factoryFor(services),
    {
      reportException: (_error, context) => {
        reports.push({ stage: context.stage, extras: context.extras });
        return Promise.resolve();
      },
    },
  );

  assertEquals(response.status, 503);
  assertEquals(reports, [{
    stage: "remove_storage",
    extras: { error_code: "remove_storage_failed" },
  }]);
});

Deno.test("does not delete Auth when cleanup receipt finalization fails", async () => {
  const services = new FakeAccountDeletionServices();
  services.objectListings.push([]);
  services.completeCleanupError = new Error(
    "forced cleanup completion failure",
  );

  const response = await handleDeleteAccount(
    deletionRequest(),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: "account_deletion_failed" });
  assertEquals(
    services.events.some((event) => event.startsWith("delete_user:")),
    false,
  );
});

Deno.test("lost response after Auth deletion leaves a recoverable operation", async () => {
  const services = new FakeAccountDeletionServices();
  services.objectListings.push([]);
  services.completeOperationError = new Error("forced receipt write failure");

  const response = await handleDeleteAccount(
    deletionRequest(),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: "account_deletion_failed" });
  assertEquals(services.events.includes(`delete_user:${userId}`), true);
  assertEquals(
    services.events.includes(
      "record_operation_error:complete_operation_failed",
    ),
    true,
  );
});

class FakeAccountDeletionServices implements AccountDeletionServices {
  events: string[] = [];
  objectListings: string[][] = [];
  recentSession = true;
  removeError: unknown = null;
  completeCleanupError: unknown = null;
  completeOperationError: unknown = null;
  operationCompleted = false;
  operationStage: AccountDeletionOperationStage = "prepared";

  getVerifiedUserId(_token: string): Promise<string | null> {
    this.events.push("get_user");
    return Promise.resolve(userId);
  }

  isRecentSession(user: string, session: string): Promise<boolean> {
    this.events.push(`recent_session:${user}:${session}`);
    return Promise.resolve(this.recentSession);
  }

  listObjectPaths(user: string): Promise<string[]> {
    this.events.push(`list:${user}`);
    return Promise.resolve(this.objectListings.shift() ?? []);
  }

  beginCleanup(user: string, objectPaths: string[]): Promise<string> {
    this.events.push(`begin:${user}:${objectPaths.length}`);
    return Promise.resolve("33333333-3333-4333-8333-333333333333");
  }

  removeObjects(objectPaths: string[]): Promise<void> {
    this.events.push(`remove:${objectPaths.length}`);
    return this.removeError == null
      ? Promise.resolve()
      : Promise.reject(this.removeError);
  }

  deleteUser(user: string): Promise<void> {
    this.events.push(`delete_user:${user}`);
    return Promise.resolve();
  }

  completeCleanup(_jobId: string): Promise<void> {
    this.events.push("complete_cleanup");
    return this.completeCleanupError == null
      ? Promise.resolve()
      : Promise.reject(this.completeCleanupError);
  }

  recordCleanupError(_jobId: string, errorCode: string): Promise<void> {
    this.events.push(`record_error:${errorCode}`);
    return Promise.resolve();
  }

  beginOperation(
    _requestHash: string,
    _subjectBinding: string,
    user: string,
  ) {
    this.events.push(`begin_operation:${user}`);
    // Determine stage: if operationCompleted is explicitly set, use 'completed'.
    const stage = this.operationCompleted
      ? "completed" as const
      : this.operationStage;
    // Matches updated backend: both 'completed' and 'acknowledged' -> completed=true.
    const completed = stage === "completed" || stage === "acknowledged";
    return Promise.resolve({ operationId, stage, completed });
  }

  advanceOperation(
    _operationId: string,
    _userId: string,
    stage: Parameters<AccountDeletionServices["advanceOperation"]>[2],
  ): Promise<void> {
    this.events.push(`advance:${stage}`);
    return Promise.resolve();
  }

  completeOperation(
    _operationId: string,
    _userId: string,
    _subjectBinding: string,
  ): Promise<void> {
    this.events.push("complete_operation");
    return this.completeOperationError == null
      ? Promise.resolve()
      : Promise.reject(this.completeOperationError);
  }

  recordOperationError(
    _operationId: string,
    _userId: string,
    errorCode: string,
  ): Promise<void> {
    this.events.push(`record_operation_error:${errorCode}`);
    return Promise.resolve();
  }
}

function factoryFor(services: AccountDeletionServices): ServiceFactory {
  return () => services;
}

function deletionRequest({
  includeAuthorization = true,
  confirmation = "delete-my-account",
  token = validToken,
  extraBody = {},
  origin,
  recoveryKey: requestRecoveryKey = recoveryKey,
}: {
  includeAuthorization?: boolean;
  confirmation?: string;
  token?: string;
  extraBody?: Record<string, unknown>;
  origin?: string;
  recoveryKey?: string | null;
} = {}): Request {
  const headers = new Headers();
  if (includeAuthorization) headers.set("Authorization", `Bearer ${token}`);
  if (origin != null) headers.set("Origin", origin);
  headers.set("Content-Type", "application/json");
  return new Request("http://localhost/delete-account", {
    method: "POST",
    headers,
    body: JSON.stringify({
      confirmation,
      ...(requestRecoveryKey == null
        ? {}
        : { recovery_key: requestRecoveryKey }),
      ...extraBody,
    }),
  });
}

function jwtWithSession(session: string): string {
  const encode = (value: Record<string, string>): string =>
    btoa(JSON.stringify(value)).replaceAll("+", "-").replaceAll("/", "_")
      .replaceAll("=", "");
  return `${encode({ alg: "none" })}.${encode({ session_id: session })}.sig`;
}
