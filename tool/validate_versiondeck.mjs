import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { validateVersionDeckManifest } from "../download-site/manifest-schema.js";
import { validateAccountDeletionPublicConfig } from "./build_account_deletion_site.mjs";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDirectory, "..");
const site = path.resolve(root, process.argv[2] || "download-site");
const requiredFiles = [
  "index.html",
  "account-deletion.html",
  "account-deletion.css",
  "account-deletion.js",
  "account-deletion-config.js",
  "styles.css",
  "enhancements.css",
  "security.css",
  "build-status.css",
  "build-status-ui.css",
  "build-status-timeline.css",
  "sticky-download-fix.css",
  "app.js",
  "build-status.js",
  "build-status-ui.js",
  "build-status-timeline.js",
  "sticky-download-fix.js",
  "manifest-schema.js",
  "cache-policy.js",
  "relative-time.js",
  "manifest.webmanifest",
  "sw.js",
  "releases.json",
  "asset-manifest.json",
  "build-info.json",
  "app-ads.txt",
  ".nojekyll",
  "assets/versiondeck-mark.svg",
  "assets/versiondeck-192.png",
  "assets/versiondeck-512.png",
];

for (const file of requiredFiles) await fs.access(path.join(site, file));

// Verify service worker APP_SHELL references all exist
const swContent = await fs.readFile(path.join(site, "sw.js"), "utf8");
const appShellMatch = swContent.match(/const\s+APP_SHELL\s*=\s*\[([\s\S]*?)\];/);
if (!appShellMatch) {
  throw new Error("sw.js is missing APP_SHELL precache array");
}
const appShellFiles = appShellMatch[1]
  .split("\n")
  .map(l => l.trim().replace(/^['"]\.\/|['"],?$/g, ""))
  .filter(f => f && f !== "");
for (const shellFile of appShellFiles) {
  await fs.access(path.join(site, shellFile));
}

const html = await fs.readFile(path.join(site, "index.html"), "utf8");
const requiredHtml = [
  'id="release-status"',
  'id="stale-banner"',
  'id="latest-card"',
  'id="release-template"',
  'id="build-progress-section"',
  'id="build-progress-heading"',
  'id="build-progress-meta"',
  'id="build-progress-phase"',
  'id="build-progress-track"',
  'id="build-progress-percent"',
  'id="build-progress-preview"',
  'id="build-progress-step-list"',
  'id="build-progress-alerts"',
  'id="build-progress-alerts-state"',
  'id="build-progress-notifications"',
  'id="build-progress-notifications-state"',
  'id="build-announcer"',
  'id="build-toast"',
  'id="build-toast-message"',
  'id="build-toast-dismiss"',
  'type="module" src="app.js"',
  "Content-Security-Policy",
  'href="account-deletion.html"',
];
for (const marker of requiredHtml) {
  if (!html.includes(marker)) throw new Error(`index.html is missing ${marker}`);
}
if (!/type="module"\s+src="build-status\.js\?v=[a-z\d-]+"/i.test(html)) {
  throw new Error("index.html must load a versioned build-status.js asset.");
}
if (!/rel="stylesheet"\s+href="build-status\.css\?v=[a-z\d-]+"/i.test(html)) {
  throw new Error("index.html must load a versioned build-status.css asset.");
}
if (!/type="module"\s+src="build-status-ui\.js\?v=[a-z\d-]+"/i.test(html)) {
  throw new Error("index.html must load a versioned build-status-ui.js asset.");
}
if (!/rel="stylesheet"\s+href="build-status-ui\.css\?v=[a-z\d-]+"/i.test(html)) {
  throw new Error("index.html must load a versioned build-status-ui.css asset.");
}
if (/<script(?![^>]*\bsrc=)/i.test(html)) throw new Error("Inline scripts are not allowed.");
if (/<style\b/i.test(html)) throw new Error("Inline styles are not allowed.");
if (/\son[a-z]+\s*=/i.test(html)) throw new Error("Inline event handlers are not allowed.");
if (/href="#"/.test(html.replace('href="#latest-heading"', ""))) {
  throw new Error("index.html contains a placeholder href.");
}
for (const directive of [
  "default-src 'none'",
  "script-src 'self'",
  "style-src 'self'",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'none'",
  "form-action 'none'",
]) {
  if (!html.includes(directive)) throw new Error(`Content Security Policy is missing ${directive}`);
}

const accountDeletionHtml = await fs.readFile(
  path.join(site, "account-deletion.html"),
  "utf8",
);
for (const marker of [
  'id="btn-authenticate"',
  'id="btn-delete"',
  'id="confirm-deletion"',
  'id="authenticated-identity"',
  'PRIVACY.md',
  'mailto:support@owntend.app',
]) {
  if (!accountDeletionHtml.includes(marker)) {
    throw new Error(`account-deletion.html is missing ${marker}`);
  }
}
for (const asset of [
  "account-deletion.css",
  "account-deletion-config.js",
  "account-deletion.js",
]) {
  if (!new RegExp(`${asset.replaceAll(".", "\\.")}\\?v=[a-f\\d]{40}`, "i").test(accountDeletionHtml)) {
    throw new Error(`account-deletion.html must load a revisioned ${asset} asset.`);
  }
}
if (
  accountDeletionHtml.indexOf("account-deletion-config.js") >
    accountDeletionHtml.indexOf("account-deletion.js")
) {
  throw new Error("Account-deletion public config must load before the page module.");
}
if (/<script(?![^>]*\bsrc=)/i.test(accountDeletionHtml)) {
  throw new Error("Inline scripts are not allowed on the account-deletion page.");
}
if (/<style\b/i.test(accountDeletionHtml)) {
  throw new Error("Inline styles are not allowed on the account-deletion page.");
}
if (/\son[a-z]+\s*=/i.test(accountDeletionHtml)) {
  throw new Error("Inline event handlers are not allowed on the account-deletion page.");
}
for (const directive of [
  "default-src 'none'",
  "script-src 'self'",
  "style-src 'self'",
  "connect-src https://iajvkvvvhwjdiuaufymh.supabase.co",
  "object-src 'none'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-src 'none'",
]) {
  if (!accountDeletionHtml.includes(directive)) {
    throw new Error(`Account-deletion Content Security Policy is missing ${directive}`);
  }
}
if (/['"]unsafe-(?:inline|eval)['"]/.test(accountDeletionHtml)) {
  throw new Error("Account-deletion Content Security Policy must not allow unsafe scripts or styles.");
}

const accountDeletionScript = await fs.readFile(
  path.join(site, "account-deletion.js"),
  "utf8",
);
for (const marker of [
  "/auth/v1/authorize",
  "/auth/v1/token?grant_type=pkce",
  "/auth/v1/user",
  "/functions/v1/delete-account",
  "/functions/v1/account-deletion-status",
  "recovery_key: recoveryKey",
  "expected_user_id: expectedUserId",
  "isDeletionReceipt(receipt, expectedUserId)",
  "isDeletionReceipt(payload, expectedUserId)",
  "value?.deleted === true",
  'value?.status === "deleted"',
  "value?.user_id === expectedUserId",
]) {
  if (!accountDeletionScript.includes(marker)) {
    throw new Error(`account-deletion.js is missing ${marker}`);
  }
}
for (const forbidden of ["localStorage", "setTimeout(", "console."]) {
  if (accountDeletionScript.includes(forbidden)) {
    throw new Error(`account-deletion.js contains forbidden browser behavior: ${forbidden}`);
  }
}

const accountDeletionConfigSource = await fs.readFile(
  path.join(site, "account-deletion-config.js"),
  "utf8",
);
const accountDeletionConfigMatch = accountDeletionConfigSource.match(
  /^globalThis\.OWNTEND_ACCOUNT_DELETION_CONFIG = Object\.freeze\(([\s\S]+)\);\s*$/,
);
if (!accountDeletionConfigMatch) {
  throw new Error("Generated account-deletion public config has an unexpected format.");
}
const accountDeletionConfig = JSON.parse(accountDeletionConfigMatch[1]);
validateAccountDeletionPublicConfig(
  accountDeletionConfig,
  { allowInert: true },
);

const buildStatusUiCss = await fs.readFile(path.join(site, "build-status-ui.css"), "utf8");
for (const marker of [
  "overflow-wrap: anywhere",
  ".build-phase-details",
  "max-height: none",
  ".build-progress-track.is-indeterminate",
]) {
  if (!buildStatusUiCss.includes(marker)) {
    throw new Error(`build-status-ui.css is missing ${marker}`);
  }
}

const webManifest = JSON.parse(await fs.readFile(path.join(site, "manifest.webmanifest"), "utf8"));
if (webManifest.orientation) throw new Error("PWA orientation must not be forced.");
if (webManifest.display !== "standalone") throw new Error("PWA display must remain standalone.");
if (webManifest.start_url !== "./" || webManifest.scope !== "./") {
  throw new Error("PWA start_url and scope must remain relative to VersionDeck.");
}
for (const icon of webManifest.icons || []) await fs.access(path.join(site, icon.src));
for (const shortcut of webManifest.shortcuts || []) {
  if (!/^\.\/#(?:latest-heading|releases)$/.test(shortcut.url || "")) {
    throw new Error(`Unexpected PWA shortcut URL: ${shortcut.url}`);
  }
}

const releaseManifest = JSON.parse(await fs.readFile(path.join(site, "releases.json"), "utf8"));
const releaseErrors = validateVersionDeckManifest(releaseManifest);
if (releaseErrors.length) {
  throw new Error(`Release manifest validation failed: ${releaseErrors.join(" ")}`);
}

const serviceWorker = await fs.readFile(path.join(site, "sw.js"), "utf8");
if (serviceWorker.includes("__VERSIONDECK_CACHE_REVISION__")) {
  throw new Error("Service-worker cache revision was not replaced.");
}
if (!/shell-[a-f\d]{40}/i.test(serviceWorker)) {
  throw new Error("Service-worker cache name does not contain the source revision.");
}
const builtAppShellMatch = serviceWorker.match(/const APP_SHELL = \[([\s\S]*?)\];/);
if (!builtAppShellMatch) throw new Error("Service-worker app shell is missing.");
if (builtAppShellMatch[1].includes("releases.json")) {
  throw new Error("releases.json must not be included in the service-worker app shell.");
}
for (const asset of [
  "build-status.js",
  "build-status.css",
  "build-status-ui.js",
  "build-status-ui.css",
]) {
  if (!builtAppShellMatch[1].includes(asset)) {
    throw new Error(`Service-worker app shell is missing ${asset}.`);
  }
}
if (!serviceWorker.includes('fetch(request, { cache: "no-store" })')) {
  throw new Error("Service worker must fetch releases.json without storage caching.");
}
for (const marker of [
  'relativePath === "account-deletion.html"',
  "networkOnlyAccountDeletionNavigation(request)",
  'relativePath === "" || relativePath === "index.html"',
  "Account deletion requires a network connection",
]) {
  if (!serviceWorker.includes(marker)) {
    throw new Error(`Service worker is missing account-deletion isolation: ${marker}`);
  }
}
if (builtAppShellMatch[1].includes("account-deletion")) {
  throw new Error("Account-deletion assets must not be stored in the offline app shell.");
}

const buildInfo = JSON.parse(await fs.readFile(path.join(site, "build-info.json"), "utf8"));
if (!/^[a-f\d]{40}$/i.test(buildInfo.sourceRevision || "")) {
  throw new Error("Build information does not contain a full source revision.");
}
if (buildInfo.sourceRevision !== releaseManifest.generatorCommit) {
  throw new Error("Build source revision and manifest generator commit disagree.");
}

const inventory = JSON.parse(await fs.readFile(path.join(site, "asset-manifest.json"), "utf8"));
if (inventory.revision !== buildInfo.sourceRevision) {
  throw new Error("Asset inventory revision and build source revision disagree.");
}
for (const [relativePath, expectedHash] of Object.entries(inventory.files || {})) {
  const content = await fs.readFile(path.join(site, relativePath));
  const actualHash = crypto.createHash("sha256").update(content).digest("hex");
  if (actualHash !== expectedHash) throw new Error(`Asset hash mismatch: ${relativePath}`);
}
if (inventory.files["release-diagnostics.json"]) {
  throw new Error("Release diagnostics must not be deployed with the public site.");
}

console.log(`VersionDeck static validation passed for ${site}.`);
