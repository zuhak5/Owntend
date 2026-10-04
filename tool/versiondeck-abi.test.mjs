import assert from "node:assert/strict";
import fs from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";
import { enhanceAbiDownloads } from "../download-site/abi-downloads.js";
import {
  normalizeRelease,
  selectProductionApkVariants,
} from "./generate_versiondeck_manifest.mjs";
import {
  VERSIONDECK_PRIMARY_ABI,
  VERSIONDECK_REPOSITORY,
  VERSIONDECK_SIGNER_SHA256,
  VERSIONDECK_SPLIT_ABIS,
  validateVersionDeckManifest,
  classifyVersionDeckManifest,
  VersionDeckManifestState,
  VersionDeckReleaseAvailabilityStatus,
} from "../download-site/manifest-schema.js";
import { RELEASE_CACHE_SCHEMA_VERSION, ReleaseCacheState, classifyReleaseCache } from "../download-site/cache-policy.js";

const SHA_BY_ABI = Object.freeze({
  "arm64-v8a": "1".repeat(64),
  "armeabi-v7a": "2".repeat(64),
  "x86_64": "3".repeat(64),
});
const COMMIT = "a".repeat(40);
const VERSION = "1.0.0";
const BUILD = 4;
const NOW = Date.parse("2026-08-20T14:00:00Z");

function asset(name, id, sha = "") {
  return {
    id,
    name,
    state: "uploaded",
    size: 30_000_000 + id,
    download_count: id,
    digest: sha ? `sha256:${sha}` : undefined,
    url: `https://api.github.com/repos/${VERSIONDECK_REPOSITORY}/releases/assets/${id}`,
    browser_download_url: `https://github.com/${VERSIONDECK_REPOSITORY}/releases/download/v1/${name}`,
  };
}

function splitRelease() {
  const assets = [];
  let id = 10;
  for (const abi of VERSIONDECK_SPLIT_ABIS) {
    const name = `Owntend-${VERSION}-build-${BUILD}-${abi}.apk`;
    assets.push(asset(name, id++, SHA_BY_ABI[abi]));
    assets.push(asset(`${name}.sha256`, id++));
  }
  return {
    id: 2004,
    draft: false,
    prerelease: false,
    name: `Owntend ${VERSION} (Build ${BUILD})`,
    tag_name: `v${VERSION}-build.${BUILD}`,
    published_at: "2026-08-20T13:50:00Z",
    html_url: `https://github.com/${VERSIONDECK_REPOSITORY}/releases/tag/v1.0.0-build.4`,
    body: "## What's changed\n\n- Smaller architecture-specific APK downloads",
    assets,
  };
}

function provenance(abi, sha) {
  const name = `Owntend-${VERSION}-build-${BUILD}-${abi}.apk`;
  return {
    policyVersion: 1,
    predicateType: "https://slsa.dev/provenance/v1",
    repository: VERSIONDECK_REPOSITORY,
    sourceRepositoryUri: `https://github.com/${VERSIONDECK_REPOSITORY}`,
    sourceRepositoryDigest: COMMIT,
    sourceRepositoryRef: "refs/heads/main",
    sourceRepositoryIdentifier: "1334767666",
    sourceRepositoryOwnerUri: "https://github.com/zuhak5",
    sourceRepositoryOwnerIdentifier: "233116763",
    signerWorkflow: `https://github.com/${VERSIONDECK_REPOSITORY}/.github/workflows/shorebird-release-android.yml@refs/heads/main`,
    signerDigest: COMMIT,
    workflowName: "Shorebird Android Release",
    workflowTrigger: "workflow_dispatch",
    runnerEnvironment: "github-hosted",
    runInvocationUri: `https://github.com/${VERSIONDECK_REPOSITORY}/actions/runs/32373934674/attempts/1`,
    runId: "32373934674",
    runAttempt: "1",
    buildConfigUri: `https://github.com/${VERSIONDECK_REPOSITORY}/.github/workflows/shorebird-release-android.yml@refs/heads/main`,
    buildConfigDigest: COMMIT,
    certificateIssuer: "CN=sigstore-intermediate,O=sigstore.dev",
    oidcIssuer: "https://token.actions.githubusercontent.com",
    sourceRepositoryVisibilityAtSigning: "public",
    subjectName: name,
    artifactSha256: sha,
    verifiedTimestamp: "2026-08-20T13:55:00Z",
  };
}

function verifier(abi) {
  const sha = SHA_BY_ABI[abi];
  return {
    sha256: sha,
    packageName: "app.owntend.mobile",
    version: VERSION,
    build: BUILD,
    signerCertificateSha256: VERSIONDECK_SIGNER_SHA256,
    commitSha: COMMIT,
    attestationVerified: true,
    abi,
    nativeAbis: [abi],
    provenance: provenance(abi, sha),
  };
}

function normalizationOptions() {
  return {
    now: NOW,
    readChecksumAsset: async (checksumAsset) => {
      const apkName = checksumAsset.name.replace(/\.sha256$/, "");
      const abi = VERSIONDECK_SPLIT_ABIS.find((candidate) => apkName.endsWith(`-${candidate}.apk`));
      return `${SHA_BY_ABI[abi]}  ${apkName}`;
    },
    verifyReleaseArtifact: async ({ expectedAbi }) => verifier(expectedAbi),
  };
}

test("split selector requires exactly the three supported ABI APKs", () => {
  const result = selectProductionApkVariants(splitRelease(), VERSION, BUILD);
  assert.deepEqual(result.errors, []);
  assert.deepEqual(result.variants.map((item) => item.abi), VERSIONDECK_SPLIT_ABIS);
});

test("split selector rejects a missing ABI instead of falling back", () => {
  const release = splitRelease();
  release.assets = release.assets.filter((item) => !item.name.includes("x86_64"));
  const result = selectProductionApkVariants(release, VERSION, BUILD);
  assert.equal(result.variants, null);
  assert.ok(result.errors.some((error) => error.includes("x86_64")));
});

test("split selector rejects an unexpected fourth ABI", () => {
  const release = splitRelease();
  release.assets.push(asset(`Owntend-${VERSION}-build-${BUILD}-riscv64.apk`, 99, "4".repeat(64)));
  const result = selectProductionApkVariants(release, VERSION, BUILD);
  assert.equal(result.variants, null);
  assert.ok(result.errors.some((error) => error.includes("Unexpected ABI APK")));
});

test("normalization verifies every ABI and aliases ARM64 for backward UI compatibility", async () => {
  const calls = [];
  const options = normalizationOptions();
  const result = await normalizeRelease(splitRelease(), {
    ...options,
    verifyReleaseArtifact: async (context) => {
      calls.push(context.expectedAbi);
      return verifier(context.expectedAbi);
    },
  });
  assert.deepEqual(result.errors, []);
  assert.equal(result.release.distributionMode, "abi");
  assert.equal(result.release.primaryAbi, VERSIONDECK_PRIMARY_ABI);
  assert.deepEqual(calls, VERSIONDECK_SPLIT_ABIS);
  assert.equal(result.release.apkVariants.length, 3);
  assert.deepEqual(result.release.apk, result.release.apkVariants[0].apk);
  assert.deepEqual(result.release.checksum, result.release.apkVariants[0].checksum);
  assert.deepEqual(result.release.verification, result.release.apkVariants[0].verification);
});

test("schema fails closed if primary alias or a variant is tampered", async () => {
  const normalized = await normalizeRelease(splitRelease(), normalizationOptions());
  const manifest = JSON.parse(JSON.stringify({
    schemaVersion: 1,
    generatedAt: "2026-08-20T13:56:00Z",
    leaseExpiresAt: "2026-08-21T13:56:00Z",
    generatorCommit: COMMIT,
    repository: VERSIONDECK_REPOSITORY,
    package: {
      name: "app.owntend.mobile",
      signerCertificateSha256: VERSIONDECK_SIGNER_SHA256,
    },
    publication: { status: "active", reasonCode: null, message: null, updatedAt: null },
    latestStableReleaseId: normalized.release.id,
    latestPrereleaseReleaseId: null,
    releases: [normalized.release],
  }));
  assert.deepEqual(validateVersionDeckManifest(manifest, { now: NOW }), []);

  manifest.releases[0].apk.sha256 = "f".repeat(64);
  assert.ok(validateVersionDeckManifest(manifest, { now: NOW }).some((error) => error.includes("primary apk alias")));
});

test("ABI download UI never guesses CPU architecture from user agent", async () => {
  const source = await fs.readFile(new URL("../download-site/abi-downloads.js", import.meta.url), "utf8");
  assert.match(source, /VersionDeck does not guess device architecture/);
  assert.doesNotMatch(source, /userAgent|userAgentData|navigator\.platform/i);
  for (const abi of VERSIONDECK_SPLIT_ABIS) assert.match(source, new RegExp(abi.replace("-", "\\-")));
});

test("ABI chooser never restores downloads for an unavailable release", async (t) => {
  const normalized = await normalizeRelease(splitRelease(), normalizationOptions());
  const release = normalized.release;
  release.availability = {
    status: "withdrawn", reasonCode: "operator_withdrawal",
    message: "Withdrawn", decidedAt: "2026-08-20T13:56:00Z",
    supersededByReleaseId: null,
  };
  const manifest = {
    schemaVersion: 1,
    generatedAt: "2026-08-20T13:56:00Z",
    leaseExpiresAt: "2026-08-21T13:56:00Z",
    generatorCommit: COMMIT,
    repository: VERSIONDECK_REPOSITORY,
    package: { name: "app.owntend.mobile", signerCertificateSha256: VERSIONDECK_SIGNER_SHA256 },
    publication: { status: "active", reasonCode: null, message: null, updatedAt: null },
    latestStableReleaseId: null,
    latestPrereleaseReleaseId: null,
    releases: [release],
  };
  assert.deepEqual(validateVersionDeckManifest(manifest, { now: NOW }), []);
  const createdLinks = [];
  const links = { querySelector: () => null, append: () => {} };
  const disabledPrimary = { textContent: "Withdrawn", title: "Withdrawn" };
  const card = {
    dataset: { releaseId: String(release.id) },
    querySelector: (selector) => ({
      ".release-title": { textContent: `Owntend ${release.version}` },
      ".release-meta": { textContent: `Build ${release.build}` },
      ".archive-download": disabledPrimary,
      ".release-links": links,
    })[selector] ?? null,
  };
  const originalDocument = globalThis.document;
  t.after(() => {
    if (originalDocument === undefined) delete globalThis.document;
    else globalThis.document = originalDocument;
  });
  t.mock.method(Date, "now", () => NOW);
  globalThis.document = {
    querySelector: () => null,
    querySelectorAll: () => [card],
    createElement: (tag) => {
      const node = { dataset: {}, append: () => {} };
      if (tag === "a") createdLinks.push(node);
      return node;
    },
  };
  await enhanceAbiDownloads(manifest);
  assert.equal(createdLinks.filter((link) => link.href).length, 0);
  assert.equal(disabledPrimary.textContent, "Withdrawn");
  release.availability = {
    status: "superseded", reasonCode: "replaced_by_newer_build", message: "Superseded",
    decidedAt: "2026-08-20T13:56:00Z", supersededByReleaseId: release.id + 1,
  };
  const successor = structuredClone(normalized.release);
  successor.id = release.id + 1;
  successor.availability = { status: "active", reasonCode: null, message: null, decidedAt: null, supersededByReleaseId: null };
  manifest.releases.push(successor);
  assert.deepEqual(validateVersionDeckManifest(manifest, { now: NOW }), []);
  await enhanceAbiDownloads(manifest);
  assert.equal(createdLinks.filter((link) => link.href).length, 0);
  release.availability = { status: "active", reasonCode: null, message: null, decidedAt: null, supersededByReleaseId: null };
  manifest.publication = { status: "disabled", reasonCode: "operator_disabled", message: "Disabled", updatedAt: "2026-08-20T13:56:00Z" };
  assert.deepEqual(validateVersionDeckManifest(manifest, { now: NOW }), []);
  await enhanceAbiDownloads(manifest);
  assert.equal(createdLinks.filter((link) => link.href).length, 0);
});

// Run the actual app renderer and registered event handlers with a minimal DOM.
// No network, timers or browser globals escape this isolated VM context.
async function loadedPage(manifest) {
  const documentEvents = new Map();
  const windowEvents = new Map();
  const timers = new Map();
  let nextTimer = 0;
  let now = NOW;
  class Element {
    constructor(tag = "div") {
      this.tagName = tag.toUpperCase();
      this.dataset = {};
      this.children = [];
      this.attributes = new Map();
      this.className = "";
      this.classList = { add() {}, remove() {} };
      this.style = {};
      this.hidden = false;
    }
    set textContent(value) { this._text = value; this.children = []; }
    get textContent() { return this._text || this.children.map((node) => typeof node === "string" ? node : node.textContent).join(""); }
    append(...nodes) { for (const node of nodes) { this.children.push(node); if (typeof node === "object") node.parentElement = this; } }
    replaceChildren(...nodes) { this.children = []; this.append(...nodes); }
    insertBefore(node) { this.append(node); }
    setAttribute(name, value) { this.attributes.set(name, value); }
    removeAttribute(name) {
      this.attributes.delete(name);
      if (name === "href") delete this.href;
      if (name.startsWith("data-")) delete this.dataset[name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())];
    }
    getAttribute(name) { return this.attributes.get(name); }
    addEventListener() {}
    closest(selector) { return selector === "[data-download-link]" && this.dataset.downloadLink ? this : this.parentElement?.closest(selector) ?? null; }
    matches(selector) {
      if (selector === "[data-download-link]") return this.dataset.downloadLink === "true";
      if (selector === "[data-abi-chooser]") return this.dataset.abiChooser === "true";
      return selector.startsWith(".") && this.className.split(" ").includes(selector.slice(1).split(":")[0]);
    }
    querySelectorAll(selector) {
      return this.children.filter((node) => typeof node === "object").flatMap((node) => [
        ...(node.matches(selector) ? [node] : []), ...node.querySelectorAll(selector),
      ]);
    }
    querySelector(selector) { return this.querySelectorAll(selector)[0] ?? null; }
  }
  const nodes = new Map();
  const ids = ["latest-card", "release-list", "release-count", "release-template", "refresh-button", "sticky-download", "sticky-version", "sticky-download-link", "toast", "release-status", "stale-banner", "stale-banner-text", "update-notice", "update-button"];
  for (const id of ids) nodes.set(`#${id}`, new Element());
  nodes.get("#release-template").content = {
    cloneNode() {
      const fragment = new Element();
      const card = new Element(); card.className = "release-card";
      for (const className of ["release-title", "release-label", "release-meta", "release-summary", "archive-download", "release-details", "release-toggle", "release-links", "release-exact-date", "release-changes", "release-hash-copy", "release-verification"]) {
        const node = new Element(); node.className = className; card.append(node);
      }
      // Template selectors can evolve without making unrelated layout details
      // part of the test contract; download state is always the real app code.
      const query = card.querySelector.bind(card);
      card.querySelector = (selector) => { const found = query(selector); if (found) return found; const node = new Element(); node.className = selector.slice(1); card.append(node); return node; };
      fragment.append(card);
      fragment.querySelector = (selector) => selector === ".release-card" ? card : card.querySelector(selector);
      return fragment;
    },
  };
  const document = {
    hidden: false, body: new Element(),
    querySelector(selector) {
      const [id, descendant] = selector.split(" ");
      if (descendant) return nodes.get(id)?.querySelector(descendant) ?? null;
      return nodes.get(id) ?? null;
    },
    querySelectorAll(selector) {
      if (selector.startsWith("#")) { const [id, descendant] = selector.split(" "); return nodes.get(id)?.querySelectorAll(descendant) ?? []; }
      return [...nodes.values()].flatMap((node) => [...(node.matches(selector) ? [node] : []), ...node.querySelectorAll(selector)]);
    },
    createElement: (tag) => new Element(tag),
    createTextNode: (text) => text,
    addEventListener(name, handler) { documentEvents.set(name, handler); },
  };
  const context = vm.createContext({
    document, window: { addEventListener(name, handler) { windowEvents.set(name, handler); } },
    navigator: {}, console, Intl, AbortController,
    Date: class extends Date { static now() { return now; } },
    setTimeout(handler, delay) { const id = ++nextTimer; timers.set(id, { handler, delay }); return id; },
    clearTimeout(id) { timers.delete(id); }, setInterval() { return 0; }, clearInterval() {},
    requestAnimationFrame(handler) { handler(); },
    fetch: () => new Promise(() => {}),
    createRelativeTimeElement: () => new Element("time"), formatExactDateTime: () => "date", updateRelativeTimeElements() {},
    VersionDeckManifestState, VersionDeckReleaseAvailabilityStatus,
    classifyVersionDeckManifest: (value) => classifyVersionDeckManifest(value, { now }), validateVersionDeckManifest,
    RELEASE_CACHE_SCHEMA_VERSION, ReleaseCacheState, classifyReleaseCache,
    VERSIONDECK_PRIMARY_ABI, VERSIONDECK_SPLIT_ABIS,
  });
  const abiSource = await fs.readFile(new URL("../download-site/abi-downloads.js", import.meta.url), "utf8");
  vm.runInContext("globalThis.enhanceAbiDownloads = (() => {\n" + abiSource.replace(/^import\s*\{[\s\S]*?\}\s*from\s*"[^"]+";/gm, "").replace("export function enhanceAbiDownloads", "function enhanceAbiDownloads") + "\nreturn enhanceAbiDownloads; })();", context);
  const source = await fs.readFile(new URL("../download-site/app.js", import.meta.url), "utf8");
  vm.runInContext(source.replace(/^import\s*\{[\s\S]*?\}\s*from\s*"[^"]+";/gm, "") + "\nglobalThis.testRender = renderManifest;", context);
  context.testRender(manifest);
  return { document, nodes, documentEvents, windowEvents, timers, advance() { now = Date.parse(manifest.leaseExpiresAt) + 1; } };
}

test("loaded page revokes every download on expiry, resume and activation", async () => {
  const normalized = await normalizeRelease(splitRelease(), normalizationOptions());
  const manifest = {
    schemaVersion: 1, generatedAt: "2026-08-20T13:56:00Z", leaseExpiresAt: "2026-08-21T13:56:00Z",
    generatorCommit: COMMIT, repository: VERSIONDECK_REPOSITORY,
    package: { name: "app.owntend.mobile", signerCertificateSha256: VERSIONDECK_SIGNER_SHA256 },
    publication: { status: "active", reasonCode: null, message: null, updatedAt: null },
    latestStableReleaseId: normalized.release.id, latestPrereleaseReleaseId: null, releases: [normalized.release],
  };
  for (const trigger of ["click", "auxclick", "contextmenu", "pageshow", "visibilitychange", "timer"]) {
    const page = await loadedPage(manifest);
    const links = page.document.querySelectorAll("[data-download-link]");
    assert.ok(links.length >= 5, "primary, sticky, archive and checksum controls rendered");
    assert.equal(links.filter((link) => link.dataset.apkAbi).length, 6, "latest and archive ABI variants share the render authority");
    assert.ok(links.every((link) => link.href));
    page.advance();
    let prevented = false;
    if (["click", "auxclick", "contextmenu"].includes(trigger)) {
      page.documentEvents.get(trigger)?.({ target: links[0], preventDefault() { prevented = true; }, stopPropagation() {} });
      assert.equal(prevented, true, `${trigger} must block expired authority`);
    } else if (trigger === "timer") {
      for (const { handler } of [...page.timers.values()]) handler();
    } else (trigger === "pageshow" ? page.windowEvents : page.documentEvents).get(trigger)?.();
    assert.ok(links.every((link) => !link.href), `${trigger} removes all download hrefs`);
    assert.equal(page.nodes.get("#sticky-download").hidden, true);
  }
});
