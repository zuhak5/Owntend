const PKCE_STORAGE_KEY = "owntend-account-deletion-pkce-verifier";
const RECOVERY_STORAGE_KEY = "owntend-account-deletion-recovery-v1";
const REQUIRED_CONFIRMATION = "delete-my-account";
const EXPECTED_SUPABASE_ORIGIN = "https://qvdccazlbpvsrzkxunxo.supabase.co";
const EXPECTED_DELETION_PAGE_URL = "https://owntend.app/account-deletion.html";

export function validatePublicConfig(value) {
  if (!value || typeof value !== "object" || value.enabled !== true) {
    throw new Error("account_deletion_not_configured");
  }

  const supabaseUrl = parseExactUrl(value.supabaseUrl, EXPECTED_SUPABASE_ORIGIN);
  const deletionPageUrl = parseExactUrl(
    value.accountDeletionSiteUrl,
    EXPECTED_DELETION_PAGE_URL,
  );
  const publishableKey = value.supabasePublishableKey;
  if (!isPublicSupabaseKey(publishableKey)) {
    throw new Error("invalid_public_supabase_key");
  }

  return Object.freeze({
    supabaseUrl,
    supabasePublishableKey: publishableKey,
    accountDeletionSiteUrl: deletionPageUrl,
  });
}

export async function createPkcePair(cryptoApi = globalThis.crypto) {
  if (!cryptoApi?.getRandomValues || !cryptoApi?.subtle) {
    throw new Error("secure_browser_required");
  }
  const random = new Uint8Array(64);
  cryptoApi.getRandomValues(random);
  const verifier = base64Url(random);
  const digest = await cryptoApi.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(verifier),
  );
  return { verifier, challenge: base64Url(new Uint8Array(digest)) };
}

export function createAccountDeletionRecoveryKey(cryptoApi = globalThis.crypto) {
  if (!cryptoApi?.getRandomValues) throw new Error("secure_browser_required");
  const random = new Uint8Array(32);
  cryptoApi.getRandomValues(random);
  return base64Url(random);
}

export function loadAccountDeletionOperation(storage = globalThis.sessionStorage) {
  let value;
  try {
    value = JSON.parse(storage.getItem(RECOVERY_STORAGE_KEY));
  } catch {
    storage.removeItem(RECOVERY_STORAGE_KEY);
    return null;
  }
  if (
    !value || typeof value !== "object" ||
    !isRecoveryKey(value.recovery_key) ||
    typeof value.expected_user_id !== "string" ||
    value.expected_user_id.length === 0
  ) {
    if (value !== null) storage.removeItem(RECOVERY_STORAGE_KEY);
    return null;
  }
  return Object.freeze({
    recovery_key: value.recovery_key,
    expected_user_id: value.expected_user_id,
  });
}

export function saveAccountDeletionOperation(
  operation,
  storage = globalThis.sessionStorage,
) {
  if (
    !isRecoveryKey(operation?.recovery_key) ||
    typeof operation?.expected_user_id !== "string" ||
    operation.expected_user_id.length === 0
  ) {
    throw new Error("invalid_account_deletion_operation");
  }
  storage.setItem(RECOVERY_STORAGE_KEY, JSON.stringify(operation));
}

export function clearAccountDeletionOperation(
  storage = globalThis.sessionStorage,
) {
  storage.removeItem(RECOVERY_STORAGE_KEY);
}

export function createGoogleAuthorizationUrl(config, challenge) {
  if (!/^[A-Za-z0-9_-]{43}$/.test(challenge)) {
    throw new Error("invalid_pkce_challenge");
  }
  const url = new URL(`${config.supabaseUrl}/auth/v1/authorize`);
  url.searchParams.set("provider", "google");
  url.searchParams.set("redirect_to", config.accountDeletionSiteUrl);
  url.searchParams.set("code_challenge", challenge);
  url.searchParams.set("code_challenge_method", "s256");
  return url.toString();
}

export async function exchangeAuthorizationCode(
  config,
  code,
  verifier,
  fetchApi = globalThis.fetch,
) {
  if (!code || !verifier) throw new Error("oauth_callback_incomplete");
  const response = await fetchApi(
    `${config.supabaseUrl}/auth/v1/token?grant_type=pkce`,
    {
      method: "POST",
      headers: publicJsonHeaders(config),
      body: JSON.stringify({ auth_code: code, code_verifier: verifier }),
      cache: "no-store",
      credentials: "omit",
      referrerPolicy: "no-referrer",
    },
  );
  const payload = await readJson(response);
  if (!response.ok || typeof payload.access_token !== "string") {
    throw new Error("oauth_exchange_failed");
  }
  return payload.access_token;
}

export async function fetchAuthenticatedUser(
  config,
  accessToken,
  fetchApi = globalThis.fetch,
) {
  const response = await fetchApi(`${config.supabaseUrl}/auth/v1/user`, {
    method: "GET",
    headers: authenticatedHeaders(config, accessToken),
    cache: "no-store",
    credentials: "omit",
    referrerPolicy: "no-referrer",
  });
  const user = await readJson(response);
  if (!response.ok || typeof user.id !== "string" || user.id.length === 0) {
    throw new Error("identity_verification_failed");
  }
  return user;
}

export async function requestAccountDeletion(
  config,
  accessToken,
  expectedUserId,
  recoveryKey,
  fetchApi = globalThis.fetch,
) {
  if (!isRecoveryKey(recoveryKey)) throw new Error("recovery_key_required");
  const response = await fetchApi(
    `${config.supabaseUrl}/functions/v1/delete-account`,
    {
      method: "POST",
      headers: {
        ...authenticatedHeaders(config, accessToken),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        confirmation: REQUIRED_CONFIRMATION,
        recovery_key: recoveryKey,
      }),
      cache: "no-store",
      credentials: "omit",
      referrerPolicy: "no-referrer",
    },
  );
  const receipt = await readJson(response);
  if (response.ok && isDeletionReceipt(receipt, expectedUserId)) {
    return deletionReceipt(expectedUserId);
  }
  if (!response.ok && isSafePreDestructiveError(receipt.error)) {
    throw new Error(receipt.error);
  }
  throw new Error("account_deletion_ambiguous");
}

export async function requestAccountDeletionStatus(
  config,
  recoveryKey,
  expectedUserId,
  fetchApi = globalThis.fetch,
  acknowledge = false,
  capabilityVersion = "web-v1.0",
) {
  if (!isRecoveryKey(recoveryKey)) throw new Error("recovery_key_required");
  if (typeof expectedUserId !== "string" || expectedUserId.length === 0) {
    throw new Error("expected_user_id_required");
  }
  const body = {
    recovery_key: recoveryKey,
    expected_user_id: expectedUserId,
  };
  if (acknowledge) {
    body.action = "acknowledge";
    body.capability_version = capabilityVersion;
  }
  const response = await fetchApi(
    `${config.supabaseUrl}/functions/v1/account-deletion-status`,
    {
      method: "POST",
      headers: publicJsonHeaders(config),
      body: JSON.stringify(body),
      cache: "no-store",
      credentials: "omit",
      referrerPolicy: "no-referrer",
    },
  );
  const payload = await readJson(response);
  if (response.ok && isDeletionReceipt(payload, expectedUserId)) {
    return deletionReceipt(expectedUserId);
  }
  if (
    response.ok && payload.deleted === false && payload.status === "pending"
  ) {
    return Object.freeze({ deleted: false, status: "pending" });
  }
  if (payload.error === "recovery_not_found") {
    return Object.freeze({ deleted: false, status: "recovery_not_found" });
  }
  return Object.freeze({
    deleted: false,
    status: "recovery_temporarily_unavailable",
  });
}

export async function acknowledgeAccountDeletion(
  config,
  recoveryKey,
  expectedUserId,
  fetchApi = globalThis.fetch,
  capabilityVersion = "web-v1.0",
) {
  return requestAccountDeletionStatus(
    config,
    recoveryKey,
    expectedUserId,
    fetchApi,
    true,
    capabilityVersion,
  );
}

export async function deleteAccountWithRecovery(
  config,
  accessToken,
  expectedUserId,
  {
    fetchApi = globalThis.fetch,
    cryptoApi = globalThis.crypto,
    storage = globalThis.sessionStorage,
  } = {},
) {
  let operation = loadAccountDeletionOperation(storage);
  const existingOperation = operation !== null;
  if (operation && operation.expected_user_id !== expectedUserId) {
    throw new Error("account_deletion_recovery_identity_mismatch");
  }
  if (!operation) {
    operation = Object.freeze({
      recovery_key: createAccountDeletionRecoveryKey(cryptoApi),
      expected_user_id: expectedUserId,
    });
    saveAccountDeletionOperation(operation, storage);
  }

  try {
    const receipt = await requestAccountDeletion(
      config,
      accessToken,
      expectedUserId,
      operation.recovery_key,
      fetchApi,
    );
    try {
      await acknowledgeAccountDeletion(
        config,
        operation.recovery_key,
        expectedUserId,
        fetchApi,
      );
    } catch {
      // Acknowledgement is best-effort post-deletion; terminal state clears operation.
    }
    clearAccountDeletionOperation(storage);
    return receipt;
  } catch (error) {
    if (
      !existingOperation && error instanceof Error &&
      isSafePreDestructiveError(error.message)
    ) {
      clearAccountDeletionOperation(storage);
      throw error;
    }
  }

  return reconcileAccountDeletion(config, operation, { fetchApi, storage });
}

export async function reconcileAccountDeletion(
  config,
  operation,
  {
    fetchApi = globalThis.fetch,
    storage = globalThis.sessionStorage,
  } = {},
) {
  let status;
  try {
    status = await requestAccountDeletionStatus(
      config,
      operation.recovery_key,
      operation.expected_user_id,
      fetchApi,
    );
  } catch {
    throw new Error("account_deletion_status_unavailable");
  }
  if (status.deleted === true) {
    try {
      await acknowledgeAccountDeletion(
        config,
        operation.recovery_key,
        operation.expected_user_id,
        fetchApi,
      );
    } catch {
      // Best-effort post-deletion acknowledgement
    }
    clearAccountDeletionOperation(storage);
    return status;
  }
  if (status.status === "recovery_not_found") {
    // Retain saved operation for ambiguity fail-closed security; do not clear storage.
    throw new Error("account_deletion_not_started");
  }
  throw new Error(status.status === "pending"
    ? "account_deletion_pending"
    : "account_deletion_status_unavailable");
}

export async function signOutLocally(
  config,
  accessToken,
  fetchApi = globalThis.fetch,
) {
  try {
    await fetchApi(`${config.supabaseUrl}/auth/v1/logout?scope=local`, {
      method: "POST",
      headers: authenticatedHeaders(config, accessToken),
      cache: "no-store",
      credentials: "omit",
      referrerPolicy: "no-referrer",
    });
  } catch {
    // Account deletion already revoked the session; local sign-out is best effort.
  }
}

async function initializePage() {
  const status = document.getElementById("deletion-status");
  const authButton = document.getElementById("btn-authenticate");
  const deleteButton = document.getElementById("btn-delete");
  const statusButton = document.getElementById("btn-check-status");
  const identity = document.getElementById("authenticated-identity");
  const confirmationGroup = document.getElementById("deletion-confirmation");
  const confirmation = document.getElementById("confirm-deletion");
  if (
    !status || !authButton || !deleteButton || !statusButton || !identity ||
    !confirmationGroup || !confirmation
  ) return;

  let config;
  try {
    config = validatePublicConfig(
      globalThis.OWNTEND_ACCOUNT_DELETION_CONFIG,
    );
  } catch {
    authButton.disabled = true;
    setStatus(status, "Account deletion is temporarily unavailable. Please use the in-app option or contact support.", "error");
    return;
  }

  let accessToken = null;
  let verifiedUserId = null;

  const showConfirmedDeletion = async (tokenForRequest = null) => {
    if (tokenForRequest) await signOutLocally(config, tokenForRequest);
    accessToken = null;
    verifiedUserId = null;
    sessionStorage.removeItem(PKCE_STORAGE_KEY);
    authButton.hidden = true;
    statusButton.hidden = true;
    deleteButton.hidden = true;
    confirmationGroup.hidden = true;
    identity.hidden = true;
    setStatus(status, "Your Owntend account and synchronized cloud data were permanently deleted.", "success");
  };

  const checkSavedOperation = async () => {
    const operation = loadAccountDeletionOperation();
    if (!operation) {
      statusButton.hidden = true;
      return false;
    }
    statusButton.hidden = false;
    statusButton.disabled = true;
    setStatus(status, "Checking the pending account-deletion operation...", "normal");
    try {
      const receipt = await reconcileAccountDeletion(config, operation);
      await showConfirmedDeletion();
      return receipt.deleted === true;
    } catch (error) {
      statusButton.disabled = false;
      if (error instanceof Error && error.message === "account_deletion_not_started") {
        statusButton.hidden = true;
        setStatus(status, "The previous request did not start deletion. Sign in with Google to try again.", "normal");
      } else if (error instanceof Error && error.message === "account_deletion_pending") {
        setStatus(status, "Account deletion is still pending. Nothing is reported as complete; check again or sign in to resume the same request.", "normal");
      } else {
        setStatus(status, "The pending deletion could not be confirmed yet. Nothing is reported as complete; check again later.", "error");
      }
      return false;
    }
  };

  confirmation.addEventListener("change", () => {
    deleteButton.disabled = !confirmation.checked || !accessToken || !verifiedUserId;
  });

  authButton.addEventListener("click", async () => {
    authButton.disabled = true;
    setStatus(status, "Opening Google sign-in...", "normal");
    try {
      const pkce = await createPkcePair();
      sessionStorage.setItem(PKCE_STORAGE_KEY, pkce.verifier);
      location.assign(createGoogleAuthorizationUrl(config, pkce.challenge));
    } catch {
      sessionStorage.removeItem(PKCE_STORAGE_KEY);
      authButton.disabled = false;
      setStatus(status, "Google sign-in could not be started. Use a current browser and try again.", "error");
    }
  });

  statusButton.addEventListener("click", () => {
    void checkSavedOperation();
  });

  deleteButton.addEventListener("click", async () => {
    if (!confirmation.checked || !accessToken || !verifiedUserId) return;
    const tokenForRequest = accessToken;
    const userIdForReceipt = verifiedUserId;
    deleteButton.disabled = true;
    confirmation.disabled = true;
    setStatus(status, "Permanently deleting your Owntend account...", "normal");
    try {
      await deleteAccountWithRecovery(
        config,
        tokenForRequest,
        userIdForReceipt,
      );
      await showConfirmedDeletion(tokenForRequest);
    } catch (error) {
      confirmation.disabled = false;
      confirmation.checked = false;
      if (error instanceof Error && error.message === "recent_reauthentication_required") {
        accessToken = null;
        verifiedUserId = null;
        authButton.hidden = false;
        authButton.disabled = false;
        deleteButton.hidden = true;
        confirmationGroup.hidden = true;
        identity.hidden = true;
        setStatus(status, "Your verification is no longer recent. Sign in with Google again, then retry deletion.", "error");
      } else if (error instanceof Error && error.message === "account_deletion_pending") {
        statusButton.hidden = false;
        statusButton.disabled = false;
        deleteButton.disabled = true;
        setStatus(status, "Account deletion is still pending. Nothing is reported as complete; check status or retry to resume the same request.", "normal");
      } else {
        statusButton.hidden = loadAccountDeletionOperation() === null;
        statusButton.disabled = false;
        deleteButton.disabled = true;
        setStatus(status, "The account was not confirmed as deleted. Nothing is reported as complete; check status, retry, or contact support.", "error");
      }
    }
  });

  if (await checkSavedOperation()) return;

  const callback = readOAuthCallback();
  if (!callback.code && !callback.error) return;
  removeOAuthCallbackFromAddressBar();
  if (callback.error) {
    sessionStorage.removeItem(PKCE_STORAGE_KEY);
    setStatus(status, "Google sign-in was cancelled or could not be completed. Try again when ready.", "error");
    return;
  }

  const verifier = sessionStorage.getItem(PKCE_STORAGE_KEY);
  sessionStorage.removeItem(PKCE_STORAGE_KEY);
  authButton.disabled = true;
  setStatus(status, "Verifying your Google sign-in...", "normal");
  try {
    accessToken = await exchangeAuthorizationCode(config, callback.code, verifier);
    const user = await fetchAuthenticatedUser(config, accessToken);
    verifiedUserId = user.id;
    identity.textContent = "Your Google identity was verified for this deletion request.";
    identity.hidden = false;
    authButton.hidden = true;
    confirmationGroup.hidden = false;
    deleteButton.hidden = false;
    deleteButton.disabled = true;
    confirmation.focus();
    setStatus(status, "Identity verified. Read and select the permanent-deletion confirmation to continue.", "normal");
  } catch {
    accessToken = null;
    verifiedUserId = null;
    authButton.disabled = false;
    setStatus(status, "Google sign-in could not be verified. Sign in again and retry.", "error");
  }
}

function readOAuthCallback() {
  const query = new URLSearchParams(location.search);
  return {
    code: query.get("code"),
    error: query.get("error") || query.get("error_code") || query.get("error_description"),
  };
}

function removeOAuthCallbackFromAddressBar() {
  const url = new URL(location.href);
  for (const key of ["code", "error", "error_code", "error_description"]) {
    url.searchParams.delete(key);
  }
  history.replaceState(null, "", `${url.pathname}${url.search}${url.hash}`);
}

function setStatus(element, message, kind) {
  element.textContent = message;
  element.classList.toggle("is-error", kind === "error");
  element.classList.toggle("is-success", kind === "success");
}

function publicJsonHeaders(config) {
  return {
    apikey: config.supabasePublishableKey,
    "Content-Type": "application/json",
  };
}

function authenticatedHeaders(config, accessToken) {
  if (typeof accessToken !== "string" || accessToken.length === 0) {
    throw new Error("missing_access_token");
  }
  return {
    apikey: config.supabasePublishableKey,
    Authorization: `Bearer ${accessToken}`,
  };
}

async function readJson(response) {
  try {
    const value = await response.json();
    return value && typeof value === "object" ? value : {};
  } catch {
    return {};
  }
}

function parseExactUrl(value, expected) {
  if (typeof value !== "string" || value !== expected) {
    throw new Error("unexpected_public_endpoint");
  }
  const parsed = new URL(value);
  if (parsed.protocol !== "https:" || parsed.username || parsed.password) {
    throw new Error("invalid_public_endpoint");
  }
  return value;
}

function isPublicSupabaseKey(value) {
  if (typeof value !== "string" || value.length < 24) return false;
  if (value.startsWith("sb_publishable_")) return true;
  const parts = value.split(".");
  if (parts.length !== 3) return false;
  try {
    const payload = JSON.parse(base64UrlDecode(parts[1]));
    return payload?.role === "anon";
  } catch {
    return false;
  }
}

function isRecoveryKey(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{43}$/.test(value);
}

function isDeletionReceipt(value, expectedUserId) {
  return value?.deleted === true &&
    (value?.status === "deleted" || value?.status === "acknowledged") &&
    value?.user_id === expectedUserId;
}

function deletionReceipt(expectedUserId) {
  return Object.freeze({
    deleted: true,
    status: "deleted",
    user_id: expectedUserId,
  });
}

function isSafePreDestructiveError(value) {
  return new Set([
    "deletion_origin_forbidden",
    "invalid_session",
    "deletion_confirmation_required",
    "recovery_key_required",
    "deletion_server_misconfigured",
    "deletion_reauthentication_claims_required",
    "recent_reauthentication_required",
    "reauthentication_required",
    "reauthentication_user_mismatch",
    "account_lookup_failed",
  ]).has(value);
}

function base64Url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function base64UrlDecode(value) {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/");
  return atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "="));
}

if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", () => {
    void initializePage();
  });
}
