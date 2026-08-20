import assert from "node:assert/strict";
import fs from "node:fs/promises";
import test from "node:test";
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
} from "../download-site/manifest-schema.js";

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
    signerWorkflow: `https://github.com/${VERSIONDECK_REPOSITORY}/.github/workflows/build-production-android.yml@refs/heads/main`,
    signerDigest: COMMIT,
    workflowName: "Build Production APK",
    workflowTrigger: "workflow_dispatch",
    runnerEnvironment: "github-hosted",
    runInvocationUri: `https://github.com/${VERSIONDECK_REPOSITORY}/actions/runs/32373934674/attempts/1`,
    runId: "32373934674",
    runAttempt: "1",
    buildConfigUri: `https://github.com/${VERSIONDECK_REPOSITORY}/.github/workflows/build-production-android.yml@refs/heads/main`,
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
  const manifest = {
    schemaVersion: 5,
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
  };
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
