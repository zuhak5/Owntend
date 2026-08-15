import fs from "node:fs/promises";
import path from "node:path";

export const ACCOUNT_DELETION_SUPABASE_URL =
  "https://iajvkvvvhwjdiuaufymh.supabase.co";
export const ACCOUNT_DELETION_SITE_URL =
  "https://owntend.app/account-deletion.html";

export const INERT_ACCOUNT_DELETION_CONFIG = Object.freeze({
  enabled: false,
  supabaseUrl: "https://example.invalid",
  supabasePublishableKey: "sb_publishable_inert_pull_request_only",
  accountDeletionSiteUrl: "https://example.invalid/account-deletion.html",
});

export function accountDeletionConfigFromEnvironment(
  environment,
  { allowInert = false } = {},
) {
  if (allowInert) return INERT_ACCOUNT_DELETION_CONFIG;

  const missing = [
    "PUBLIC_SUPABASE_URL",
    "PUBLIC_SUPABASE_PUBLISHABLE_KEY",
    "ACCOUNT_DELETION_SITE_URL",
  ].filter((name) => !environment[name]?.trim());
  if (missing.length > 0) {
    throw new Error(
      `Missing required public account-deletion configuration: ${missing.join(", ")}`,
    );
  }

  return validateAccountDeletionPublicConfig({
    enabled: true,
    supabaseUrl: environment.PUBLIC_SUPABASE_URL.trim(),
    supabasePublishableKey:
      environment.PUBLIC_SUPABASE_PUBLISHABLE_KEY.trim(),
    accountDeletionSiteUrl: environment.ACCOUNT_DELETION_SITE_URL.trim(),
  });
}

export function validateAccountDeletionPublicConfig(
  config,
  { allowInert = false } = {},
) {
  if (!config || typeof config !== "object") {
    throw new Error("Account-deletion public configuration must be an object.");
  }
  if (config.enabled === false) {
    if (!allowInert || !isExactInertConfig(config)) {
      throw new Error("Inert account-deletion configuration requires explicit test mode.");
    }
    return Object.freeze({ ...INERT_ACCOUNT_DELETION_CONFIG });
  }
  if (config.enabled !== true) {
    throw new Error("Account-deletion public configuration must declare enabled=true.");
  }
  if (config.supabaseUrl !== ACCOUNT_DELETION_SUPABASE_URL) {
    throw new Error("PUBLIC_SUPABASE_URL does not match the allowlisted Supabase project URL.");
  }
  if (config.accountDeletionSiteUrl !== ACCOUNT_DELETION_SITE_URL) {
    throw new Error("ACCOUNT_DELETION_SITE_URL does not match the canonical deletion page.");
  }
  if (!isPublicSupabaseKey(config.supabasePublishableKey)) {
    throw new Error("PUBLIC_SUPABASE_PUBLISHABLE_KEY is not a public anon/publishable key.");
  }
  return Object.freeze({
    enabled: true,
    supabaseUrl: config.supabaseUrl,
    supabasePublishableKey: config.supabasePublishableKey,
    accountDeletionSiteUrl: config.accountDeletionSiteUrl,
  });
}

export function renderAccountDeletionConfig(config, options = {}) {
  const validated = validateAccountDeletionPublicConfig(config, options);
  const serialized = JSON.stringify(validated, null, 2)
    .replaceAll("<", "\\u003c")
    .replaceAll("\u2028", "\\u2028")
    .replaceAll("\u2029", "\\u2029");
  return `globalThis.OWNTEND_ACCOUNT_DELETION_CONFIG = Object.freeze(${serialized});\n`;
}

export async function writeAccountDeletionConfig(
  outputDirectory,
  config,
  options = {},
) {
  const content = renderAccountDeletionConfig(config, options);
  const outputPath = path.join(outputDirectory, "account-deletion-config.js");
  await fs.writeFile(outputPath, content, "utf8");
  return outputPath;
}

function isExactInertConfig(config) {
  return Object.entries(INERT_ACCOUNT_DELETION_CONFIG).every(
    ([key, value]) => config[key] === value,
  );
}

function isPublicSupabaseKey(value) {
  if (typeof value !== "string" || value.length < 24) return false;
  if (value.startsWith("sb_publishable_")) return true;

  const parts = value.split(".");
  if (parts.length !== 3) return false;
  try {
    const payload = JSON.parse(
      Buffer.from(parts[1], "base64url").toString("utf8"),
    );
    return payload?.role === "anon";
  } catch {
    return false;
  }
}
