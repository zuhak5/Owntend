import { assertEquals } from "@std/assert";

import { scrubEdgeSentryEvent } from "./sentry.ts";

Deno.test("Edge Sentry scrubber removes arbitrary sensitive event data", () => {
  const secrets = [
    "person@example.com",
    "eyJhbGciOiJIUzI1NiJ9.secret.signature",
    "recovery-key-value",
    "user-id-123",
    "owner/assets/private/photo.jpg",
    "C:\\Users\\Person\\private.txt",
  ];
  const event = {
    event_id: "abc123",
    timestamp: 42,
    level: "error",
    platform: "javascript",
    environment: "production",
    release: "deployment_1",
    user: { email: secrets[0] },
    request: { url: `https://example.test/?token=${secrets[1]}` },
    contexts: { arbitrary: { value: secrets[2] } },
    breadcrumbs: [{ message: secrets[3] }],
    modules: { private: secrets[4] },
    tags: { stage: "storage_cleanup", unsafe: secrets[0] },
    extra: { error_code: "storage_cleanup_failed", unsafe: secrets[2] },
    exception: {
      values: [{
        type: "EdgeTelemetryError",
        value: `failed for ${secrets.join(" ")}`,
        stacktrace: {
          frames: [{
            filename: secrets[4],
            abs_path: secrets[5],
            function: "handle_failure",
            lineno: 12,
            colno: 4,
            context_line: secrets[0],
            vars: { token: secrets[1] },
          }],
        },
      }],
    },
  };

  const scrubbed = scrubEdgeSentryEvent(event);
  const serialized = JSON.stringify(scrubbed);
  for (const secret of secrets) {
    assertEquals(serialized.includes(secret), false);
  }
  assertEquals("user" in scrubbed, false);
  assertEquals("request" in scrubbed, false);
  assertEquals("contexts" in scrubbed, false);
  assertEquals("breadcrumbs" in scrubbed, false);
  assertEquals("modules" in scrubbed, false);
  assertEquals(scrubbed.exception.values[0].value, "edge_failure");
  assertEquals(scrubbed.exception.values[0].stacktrace.frames[0] as unknown, {
    lineno: 12,
    colno: 4,
    function: "handle_failure",
  });
});
