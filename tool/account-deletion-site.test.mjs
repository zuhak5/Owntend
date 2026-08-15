import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  createAccountDeletionRecoveryKey,
  createGoogleAuthorizationUrl,
  createPkcePair,
  deleteAccountWithRecovery,
  exchangeAuthorizationCode,
  fetchAuthenticatedUser,
  loadAccountDeletionOperation,
  reconcileAccountDeletion,
  requestAccountDeletion,
  requestAccountDeletionStatus,
  saveAccountDeletionOperation,
  signOutLocally,
  validatePublicConfig,
} from "../download-site/account-deletion.js";
import {
  ACCOUNT_DELETION_SITE_URL,
  ACCOUNT_DELETION_SUPABASE_URL,
  accountDeletionConfigFromEnvironment,
  INERT_ACCOUNT_DELETION_CONFIG,
  renderAccountDeletionConfig,
  validateAccountDeletionPublicConfig,
} from "./build_account_deletion_site.mjs";
import { buildVersionDeckSite } from "./build_versiondeck_site.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const publishableKey = `sb_publishable_${"a".repeat(32)}`;
const productionConfig = Object.freeze({
  enabled: true,
  supabaseUrl: ACCOUNT_DELETION_SUPABASE_URL,
  supabasePublishableKey: publishableKey,
  accountDeletionSiteUrl: ACCOUNT_DELETION_SITE_URL,
});
const browserConfig = validatePublicConfig(productionConfig);
const recoveryKey = "A".repeat(43);

test("production public configuration is exact and fails closed", () => {
  assert.throws(
    () => accountDeletionConfigFromEnvironment({}),
    /PUBLIC_SUPABASE_URL.*PUBLIC_SUPABASE_PUBLISHABLE_KEY.*ACCOUNT_DELETION_SITE_URL/,
  );
  assert.deepEqual(
    accountDeletionConfigFromEnvironment({
      PUBLIC_SUPABASE_URL: ACCOUNT_DELETION_SUPABASE_URL,
      PUBLIC_SUPABASE_PUBLISHABLE_KEY: publishableKey,
      ACCOUNT_DELETION_SITE_URL,
    }),
    productionConfig,
  );
  assert.throws(
    () => validateAccountDeletionPublicConfig({
      ...productionConfig,
      supabaseUrl: "https://other-project.supabase.co",
    }),
    /allowlisted Supabase project URL/,
  );
  assert.throws(
    () => validateAccountDeletionPublicConfig({
      ...productionConfig,
      supabasePublishableKey: "not-a-public-supabase-key",
    }),
    /public anon\/publishable key/,
  );
});

test("inert configuration requires an explicit build mode", () => {
  assert.throws(
    () => validateAccountDeletionPublicConfig(INERT_ACCOUNT_DELETION_CONFIG),
    /explicit test mode/,
  );
  assert.deepEqual(
    accountDeletionConfigFromEnvironment({}, { allowInert: true }),
    INERT_ACCOUNT_DELETION_CONFIG,
  );
  const source = renderAccountDeletionConfig(INERT_ACCOUNT_DELETION_CONFIG, {
    allowInert: true,
  });
  assert.match(source, /enabled": false/);
});

test("PKCE authorization uses the fixed Google callback contract", async () => {
  const pair = await createPkcePair(webcrypto);
  assert.match(pair.verifier, /^[A-Za-z0-9_-]{86}$/);
  assert.match(pair.challenge, /^[A-Za-z0-9_-]{43}$/);
  const authorization = new URL(
    createGoogleAuthorizationUrl(browserConfig, pair.challenge),
  );
  assert.equal(
    `${authorization.origin}${authorization.pathname}`,
    `${ACCOUNT_DELETION_SUPABASE_URL}/auth/v1/authorize`,
  );
  assert.equal(authorization.searchParams.get("provider"), "google");
  assert.equal(
    authorization.searchParams.get("redirect_to"),
    ACCOUNT_DELETION_SITE_URL,
  );
  assert.equal(authorization.searchParams.get("code_challenge"), pair.challenge);
  assert.equal(authorization.searchParams.get("code_challenge_method"), "s256");
});

test("account-deletion recovery keys use 32 secure random bytes", () => {
  const key = createAccountDeletionRecoveryKey(webcrypto);
  assert.match(key, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(Buffer.from(key, "base64url").length, 32);
});

test("OAuth code exchange and identity lookup use public authenticated requests", async () => {
  const calls = [];
  const fetchApi = async (url, options) => {
    calls.push({ url, options });
    if (String(url).endsWith("/auth/v1/user")) {
      return jsonResponse(200, { id: "verified-user", email: "owner@example.com" });
    }
    return jsonResponse(200, { access_token: "memory-only-token" });
  };

  const accessToken = await exchangeAuthorizationCode(
    browserConfig,
    "oauth-code",
    "pkce-verifier",
    fetchApi,
  );
  const user = await fetchAuthenticatedUser(browserConfig, accessToken, fetchApi);

  assert.equal(accessToken, "memory-only-token");
  assert.equal(user.id, "verified-user");
  assert.equal(
    calls[0].url,
    `${ACCOUNT_DELETION_SUPABASE_URL}/auth/v1/token?grant_type=pkce`,
  );
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    auth_code: "oauth-code",
    code_verifier: "pkce-verifier",
  });
  assert.equal(calls[0].options.headers.apikey, publishableKey);
  assert.equal(calls[1].options.headers.Authorization, "Bearer memory-only-token");
  assert.equal(calls[1].options.credentials, "omit");
});

test("deletion requires an exact receipt for the authenticated user", async () => {
  const calls = [];
  const receipt = await requestAccountDeletion(
    browserConfig,
    "access-token",
    "verified-user",
    recoveryKey,
    async (url, options) => {
      calls.push({ url, options });
      return jsonResponse(200, {
        deleted: true,
        status: "deleted",
        user_id: "verified-user",
      });
    },
  );

  assert.deepEqual(receipt, {
    deleted: true,
    status: "deleted",
    user_id: "verified-user",
  });
  assert.equal(
    calls[0].url,
    `${ACCOUNT_DELETION_SUPABASE_URL}/functions/v1/delete-account`,
  );
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    confirmation: "delete-my-account",
    recovery_key: recoveryKey,
  });
  assert.equal(calls[0].options.headers.Authorization, "Bearer access-token");

  for (const invalidReceipt of [
    { deleted: false, status: "deleted", user_id: "verified-user" },
    { deleted: true, status: "pending", user_id: "verified-user" },
    { deleted: true, status: "deleted", user_id: "different-user" },
    {},
  ]) {
    await assert.rejects(
      requestAccountDeletion(
        browserConfig,
        "access-token",
        "verified-user",
        recoveryKey,
        async () => jsonResponse(200, invalidReceipt),
      ),
      /account_deletion_ambiguous/,
    );
  }
});

test("deletion rejects missing and malformed recovery keys before transport", async () => {
  for (const invalidKey of [undefined, "", "A".repeat(42), "!".repeat(43)]) {
    await assert.rejects(
      requestAccountDeletion(
        browserConfig,
        "access-token",
        "verified-user",
        invalidKey,
        async () => assert.fail("transport must not run"),
      ),
      /recovery_key_required/,
    );
  }
});

test("status recovery sends the same key and original user identity", async () => {
  const calls = [];
  const pending = await requestAccountDeletionStatus(
    browserConfig,
    recoveryKey,
    "verified-user",
    async (url, options) => {
      calls.push({ url, options });
      return jsonResponse(202, { deleted: false, status: "pending" });
    },
  );
  assert.deepEqual(pending, { deleted: false, status: "pending" });
  assert.equal(
    calls[0].url,
    `${ACCOUNT_DELETION_SUPABASE_URL}/functions/v1/account-deletion-status`,
  );
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    recovery_key: recoveryKey,
    expected_user_id: "verified-user",
  });
  assert.equal(calls[0].options.headers.Authorization, undefined);

  const deleted = await requestAccountDeletionStatus(
    browserConfig,
    recoveryKey,
    "verified-user",
    async () => jsonResponse(200, {
      deleted: true,
      status: "deleted",
      user_id: "verified-user",
    }),
  );
  assert.equal(deleted.deleted, true);

  const missing = await requestAccountDeletionStatus(
    browserConfig,
    recoveryKey,
    "verified-user",
    async () => jsonResponse(404, { error: "recovery_not_found" }),
  );
  assert.equal(missing.status, "recovery_not_found");

  const unavailable = await requestAccountDeletionStatus(
    browserConfig,
    recoveryKey,
    "verified-user",
    async () => jsonResponse(503, {
      error: "recovery_temporarily_unavailable",
    }),
  );
  assert.equal(unavailable.status, "recovery_temporarily_unavailable");
});

test("transport loss reconciles deletion and clears recovery only after proof", async () => {
  const storage = memoryStorage();
  const calls = [];
  const receipt = await deleteAccountWithRecovery(
    browserConfig,
    "access-token",
    "verified-user",
    {
      storage,
      cryptoApi: deterministicCrypto(),
      fetchApi: async (url, options) => {
        calls.push({ url, options });
        if (String(url).endsWith("/delete-account")) {
          throw new TypeError("connection lost");
        }
        return jsonResponse(200, {
          deleted: true,
          status: "deleted",
          user_id: "verified-user",
        });
      },
    },
  );
  assert.equal(receipt.deleted, true);
  const deletionPayload = JSON.parse(calls[0].options.body);
  const statusPayload = JSON.parse(calls[1].options.body);
  assert.match(deletionPayload.recovery_key, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(statusPayload.recovery_key, deletionPayload.recovery_key);
  assert.equal(statusPayload.expected_user_id, "verified-user");
  assert.equal(loadAccountDeletionOperation(storage), null);
});

test("pending recovery survives retry and reuses one logical operation key", async () => {
  const storage = memoryStorage();
  saveAccountDeletionOperation({
    recovery_key: recoveryKey,
    expected_user_id: "verified-user",
  }, storage);

  await assert.rejects(
    reconcileAccountDeletion(
      browserConfig,
      loadAccountDeletionOperation(storage),
      {
        storage,
        fetchApi: async () => jsonResponse(202, {
          deleted: false,
          status: "pending",
        }),
      },
    ),
    /account_deletion_pending/,
  );
  assert.equal(loadAccountDeletionOperation(storage).recovery_key, recoveryKey);

  const calls = [];
  await deleteAccountWithRecovery(
    browserConfig,
    "new-access-token",
    "verified-user",
    {
      storage,
      fetchApi: async (url, options) => {
        calls.push({ url, options });
        return jsonResponse(200, {
          deleted: true,
          status: "deleted",
          user_id: "verified-user",
        });
      },
    },
  );
  assert.equal(JSON.parse(calls[0].options.body).recovery_key, recoveryKey);
  assert.equal(loadAccountDeletionOperation(storage), null);
});

test("reconcileAccountDeletion retains operation on recovery_not_found for ambiguity safety", async () => {
  const storage = memoryStorage();
  saveAccountDeletionOperation({
    recovery_key: recoveryKey,
    expected_user_id: "verified-user",
  }, storage);

  await assert.rejects(
    reconcileAccountDeletion(
      browserConfig,
      loadAccountDeletionOperation(storage),
      {
        storage,
        fetchApi: async () => jsonResponse(404, {
          error: "recovery_not_found",
        }),
      },
    ),
    /account_deletion_not_started/,
  );
  assert.equal(loadAccountDeletionOperation(storage).recovery_key, recoveryKey);
});

test("safe pre-destructive rejection clears a new recovery operation", async () => {
  const storage = memoryStorage();
  await assert.rejects(
    deleteAccountWithRecovery(
      browserConfig,
      "access-token",
      "verified-user",
      {
        storage,
        cryptoApi: deterministicCrypto(),
        fetchApi: async () => jsonResponse(401, {
          error: "recent_reauthentication_required",
        }),
      },
    ),
    /recent_reauthentication_required/,
  );
  assert.equal(loadAccountDeletionOperation(storage), null);
});

test("local sign-out is best effort and does not surface a revoked-session failure", async () => {
  const calls = [];
  await signOutLocally(browserConfig, "access-token", async (url, options) => {
    calls.push({ url, options });
    throw new TypeError("network unavailable");
  });
  assert.equal(
    calls[0].url,
    `${ACCOUNT_DELETION_SUPABASE_URL}/auth/v1/logout?scope=local`,
  );
  assert.equal(calls[0].options.headers.Authorization, "Bearer access-token");
});

test("site assets expose confirmation and isolate deletion from offline navigation", async () => {
  const [html, script, serviceWorker, index] = await Promise.all([
    fs.readFile(path.join(root, "download-site/account-deletion.html"), "utf8"),
    fs.readFile(path.join(root, "download-site/account-deletion.js"), "utf8"),
    fs.readFile(path.join(root, "download-site/sw.js"), "utf8"),
    fs.readFile(path.join(root, "download-site/index.html"), "utf8"),
  ]);
  assert.match(html, /id="confirm-deletion"/);
  assert.match(html, /Content-Security-Policy/);
  assert.match(
    html,
    /connect-src https:\/\/iajvkvvvhwjdiuaufymh\.supabase\.co/,
  );
  assert.ok(
    html.indexOf("account-deletion-config.js") <
      html.indexOf("account-deletion.js"),
  );
  assert.match(html, /account-deletion\.css\?v=__ACCOUNT_DELETION_ASSET_REVISION__/);
  assert.doesNotMatch(script, /\blocalStorage\b|setTimeout\(|console\./);
  assert.match(serviceWorker, /networkOnlyAccountDeletionNavigation/);
  assert.match(serviceWorker, /relativePath === "account-deletion\.html"/);
  assert.match(index, /href="account-deletion\.html"/);
});

test("VersionDeck build writes the generated public config into its inventory", async (t) => {
  const temporaryRoot = await fs.mkdtemp(
    path.join(os.tmpdir(), "owntend-account-deletion-"),
  );
  t.after(() => fs.rm(temporaryRoot, { recursive: true, force: true }));
  const releaseManifest = JSON.parse(
    await fs.readFile(path.join(root, "download-site/releases.json"), "utf8"),
  );
  const output = path.join(temporaryRoot, "site");
  await buildVersionDeckSite({
    source: path.join(root, "download-site"),
    output,
    revision: releaseManifest.generatorCommit,
    accountDeletionConfig: productionConfig,
  });

  const generatedConfig = await fs.readFile(
    path.join(output, "account-deletion-config.js"),
    "utf8",
  );
  const inventory = JSON.parse(
    await fs.readFile(path.join(output, "asset-manifest.json"), "utf8"),
  );
  assert.match(generatedConfig, /enabled": true/);
  assert.match(generatedConfig, /sb_publishable_/);
  const generatedHtml = await fs.readFile(
    path.join(output, "account-deletion.html"),
    "utf8",
  );
  assert.doesNotMatch(generatedHtml, /__ACCOUNT_DELETION_ASSET_REVISION__/);
  assert.match(
    generatedHtml,
    new RegExp(`account-deletion\\.js\\?v=${releaseManifest.generatorCommit}`),
  );
  assert.equal(
    typeof inventory.files["account-deletion-config.js"],
    "string",
  );
});

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function memoryStorage() {
  const values = new Map();
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
  };
}

function deterministicCrypto() {
  return {
    getRandomValues: (bytes) => {
      bytes.fill(0x41);
      return bytes;
    },
  };
}
