import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  DEFAULT_VERSIONDECK_LEASE_HOURS,
  VERSIONDECK_CONTROL_SCHEMA_VERSION,
  buildManifest,
  compareVersionBuild,
  extractBodySha,
  loadVersionDeckControl,
  normalizeRelease,
  parseChecksumText,
  selectProductionApk,
  validateVersionDeckControl,
} from "./generate_versiondeck_manifest.mjs";
import { buildVersionDeckApkProvenancePolicy } from "./versiondeck_apk_verifier.mjs";
import { formatRelativeTime } from "../download-site/relative-time.js";
import {
  VERSIONDECK_PACKAGE_NAME,
  VERSIONDECK_REPOSITORY,
  VERSIONDECK_SIGNER_SHA256,
  VersionDeckPublicationStatus,
  VersionDeckReleaseAvailabilityStatus,
  validateVersionDeckManifest,
} from "../download-site/manifest-schema.js";
import {
  RELEASE_CACHE_SCHEMA_VERSION,
  ReleaseCacheState,
  classifyReleaseCache,
} from "../download-site/cache-policy.js";

const SHA = "a".repeat(64);
const COMMIT = "b".repeat(40);
const NOW = Date.parse("2026-08-04T13:00:00Z");
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

test("VersionDeck provenance policy binds the APK to the canonical production rail", () => {
  const apkName = "Owntend-1.0.0-build-1.apk";
  const policy = buildVersionDeckApkProvenancePolicy({
    commitSha: COMMIT,
    apkAsset: { name: apkName },
    sha256: SHA,
  });

  assert.equal(policy.artifactType, "apk");
  assert.equal(policy.repository, VERSIONDECK_REPOSITORY);
  assert.equal(policy.sourceDigest, COMMIT);
  assert.equal(policy.sourceRef, "refs/heads/main");
  assert.equal(policy.workflowPath, ".github/workflows/shorebird-release-android.yml");
  assert.equal(policy.workflowName, "Shorebird Android Release");
  assert.equal(policy.workflowTrigger, "workflow_dispatch");
  assert.equal(policy.runnerEnvironment, "github-hosted");
  assert.equal(policy.artifactName, apkName);
  assert.equal(policy.artifactSha256, SHA);
});

function baseControl(overrides = {}) {
  return {
    schemaVersion: VERSIONDECK_CONTROL_SCHEMA_VERSION,
    leaseDurationHours: DEFAULT_VERSIONDECK_LEASE_HOURS,
    publication: {
      status: VersionDeckPublicationStatus.ACTIVE,
      reasonCode: null,
      message: null,
      updatedAt: null,
      ...(overrides.publication || {}),
    },
    historicalReleaseDecisions: overrides.historicalReleaseDecisions || [],
  };
}

function releaseFixture(overrides = {}) {
  const version = overrides.version || "1.3.1";
  const build = overrides.build || 16;
  const apkName = `Owntend-${version}-build-${build}.apk`;
  return {
    id: 1000 + build,
    draft: false,
    prerelease: false,
    name: `Owntend ${version} (Build ${build})`,
    tag_name: `v${version}-build.${build}`,
    published_at: "2026-08-03T10:00:00Z",
    html_url: `https://github.com/${VERSIONDECK_REPOSITORY}/releases/tag/example`,
    target_commitish: COMMIT,
    body: `## What's changed\n\n- Improved VersionDeck\n\n## Build details\n\n- SHA-256: \`${SHA}\``,
    assets: [
      {
        id: 1,
        name: apkName,
        state: "uploaded",
        size: 12_000_000,
        download_count: 43,
        digest: `sha256:${SHA}`,
        url: `https://api.github.com/repos/${VERSIONDECK_REPOSITORY}/releases/assets/1`,
        browser_download_url: `https://github.com/${VERSIONDECK_REPOSITORY}/releases/download/example/${apkName}`,
      },
      {
        id: 2,
        name: `${apkName}.sha256`,
        state: "uploaded",
        size: 100,
        url: `https://api.github.com/repos/${VERSIONDECK_REPOSITORY}/releases/assets/2`,
        browser_download_url: `https://github.com/${VERSIONDECK_REPOSITORY}/releases/download/example/${apkName}.sha256`,
      },
    ],
    ...overrides,
  };
}

function verifierFixture(overrides = {}) {
  const version = overrides.version || "1.3.1";
  const build = overrides.build || 16;
  const artifactSha256 = overrides.sha256 || SHA;
  const commitSha = overrides.commitSha || COMMIT;
  const apkName = overrides.artifactName || `Owntend-${version}-build-${build}.apk`;
  return {
    sha256: artifactSha256,
    packageName: VERSIONDECK_PACKAGE_NAME,
    version,
    build,
    signerCertificateSha256: VERSIONDECK_SIGNER_SHA256,
    commitSha,
    provenance: {
      policyVersion: 1,
      predicateType: "https://slsa.dev/provenance/v1",
      repository: VERSIONDECK_REPOSITORY,
      sourceRepositoryUri: `https://github.com/${VERSIONDECK_REPOSITORY}`,
      sourceRepositoryDigest: commitSha,
      sourceRepositoryRef: "refs/heads/main",
      sourceRepositoryIdentifier: "1319597440",
      sourceRepositoryOwnerUri: "https://github.com/zuhak5",
      sourceRepositoryOwnerIdentifier: "233116763",
      signerWorkflow: `https://github.com/${VERSIONDECK_REPOSITORY}/.github/workflows/shorebird-release-android.yml@refs/heads/main`,
      signerDigest: commitSha,
      workflowName: "Shorebird Android Release",
      workflowTrigger: "workflow_dispatch",
      runnerEnvironment: "github-hosted",
      runInvocationUri: `https://github.com/${VERSIONDECK_REPOSITORY}/actions/runs/31329512924/attempts/1`,
      runId: "31329512924",
      runAttempt: "1",
      buildConfigUri: `https://github.com/${VERSIONDECK_REPOSITORY}/.github/workflows/shorebird-release-android.yml@refs/heads/main`,
      buildConfigDigest: commitSha,
      certificateIssuer: "CN=sigstore-intermediate,O=sigstore.dev",
      oidcIssuer: "https://token.actions.githubusercontent.com",
      sourceRepositoryVisibilityAtSigning: "public",
      subjectName: apkName,
      artifactSha256,
      verifiedTimestamp: "2026-08-03T10:05:00Z",
    },
    attestationVerified: true,
    ...overrides,
  };
}

function normalizationOptions(overrides = {}) {
  return {
    readChecksumAsset: async (asset) => `${SHA}  ${asset.name.replace(/\.sha256$/, "")}`,
    verifyReleaseArtifact: async ({ version, build }) => verifierFixture({ version, build }),
    ...overrides,
  };
}

test("VersionDeck control requires valid publication state and lease", () => {
  const errors = validateVersionDeckControl({
    schemaVersion: VERSIONDECK_CONTROL_SCHEMA_VERSION,
    leaseDurationHours: 25,
    publication: { status: "disabled", reasonCode: "", message: "", updatedAt: "bad" },
    historicalReleaseDecisions: [],
  });
  assert.ok(errors.some((error) => error.includes("lease duration")));
  assert.ok(errors.some((error) => error.includes("reason code")));
  assert.ok(errors.some((error) => error.includes("message")));
  assert.ok(errors.some((error) => error.includes("update time")));
});

test("selectProductionApk requires the exact production filename", () => {
  const fixture = releaseFixture();
  fixture.assets.unshift({
    name: "Owntend-debug.apk",
    state: "uploaded",
    size: 100,
    browser_download_url: "https://github.com/example/debug.apk",
  });
  const result = selectProductionApk(fixture, "1.3.1", 16);
  assert.equal(result.asset.name, "Owntend-1.3.1-build-16.apk");
});

test("selectProductionApk rejects duplicate exact assets", () => {
  const fixture = releaseFixture();
  fixture.assets.push({ ...fixture.assets[0], id: 99 });
  const result = selectProductionApk(fixture, "1.3.1", 16);
  assert.equal(result.asset, null);
  assert.match(result.error, /exactly one production APK/);
});

test("parseChecksumText validates hash and filename", () => {
  const fileName = "Owntend-1.3.1-build-16.apk";
  assert.deepEqual(parseChecksumText(`\uFEFF${SHA}  ${fileName}\r\n`, fileName), {
    sha256: SHA,
    fileName,
  });
  assert.equal(parseChecksumText(`${SHA}  wrong.apk`, fileName), null);
});

test("extractBodySha reads a release-note SHA", () => {
  assert.equal(extractBodySha(`SHA-256: \`${SHA}\``), SHA);
});

test("normalizeRelease rejects mismatched independent hash", async () => {
  const result = await normalizeRelease(
    releaseFixture(),
    normalizationOptions({
      verifyReleaseArtifact: async () => verifierFixture({ sha256: "c".repeat(64) }),
    }),
  );
  assert.equal(result.release, null);
  assert.ok(result.errors.some((error) => error.includes("Independent APK SHA-256 disagrees")));
});

test("normalizeRelease rejects an unexpected signer", async () => {
  const result = await normalizeRelease(
    releaseFixture(),
    normalizationOptions({
      verifyReleaseArtifact: async () => verifierFixture({
        signerCertificateSha256: "AA:".repeat(31) + "AA",
      }),
    }),
  );
  assert.equal(result.release, null);
  assert.ok(result.errors.some((error) => error.includes("signer")));
});

test("normalizeRelease requires attestation verification", async () => {
  const result = await normalizeRelease(
    releaseFixture(),
    normalizationOptions({
      verifyReleaseArtifact: async () => verifierFixture({ attestationVerified: false }),
    }),
  );
  assert.equal(result.release, null);
  assert.ok(result.errors.some((error) => error.includes("attestation")));
});

test("normalizeRelease rejects a mismatched provenance tuple", async () => {
  const base = verifierFixture();
  const result = await normalizeRelease(
    releaseFixture(),
    normalizationOptions({
      verifyReleaseArtifact: async () => ({
        ...base,
        provenance: {
          ...base.provenance,
          sourceRepositoryDigest: "c".repeat(40),
        },
      }),
    }),
  );
  assert.equal(result.release, null);
  assert.ok(result.errors.some((error) => error.includes("Provenance tuple")));
});

test("buildManifest keeps prerelease separate from latest stable", async () => {
  const stable = releaseFixture({ id: 1016, build: 16 });
  const prerelease = releaseFixture({
    id: 1017,
    build: 17,
    prerelease: true,
    name: "Owntend 1.4.0 (Build 17)",
    tag_name: "v1.4.0-build.17",
    version: "1.4.0",
  });
  prerelease.assets = releaseFixture({ version: "1.4.0", build: 17 }).assets;

  const { manifest } = await buildManifest([stable, prerelease], {
    ...normalizationOptions(),
    control: baseControl(),
    generatorCommit: COMMIT,
    now: NOW,
  });

  assert.equal(manifest.publication.status, VersionDeckPublicationStatus.ACTIVE);
  assert.equal(manifest.latestStableReleaseId, stable.id);
  assert.equal(manifest.latestPrereleaseReleaseId, prerelease.id);
  assert.equal(manifest.releases[0].id, prerelease.id);
  assert.equal(manifest.releases[0].availability.status, VersionDeckReleaseAvailabilityStatus.ACTIVE);
  assert.deepEqual(validateVersionDeckManifest(manifest, { now: NOW }), []);
});

test("buildManifest can publish an explicit disabled state without releases", async () => {
  const { manifest, diagnostics } = await buildManifest([releaseFixture()], {
    control: baseControl({
      publication: {
        status: VersionDeckPublicationStatus.DISABLED,
        reasonCode: "containment",
        message: "Downloads disabled pending remediation.",
        updatedAt: "2026-08-13T00:00:00Z",
      },
    }),
    generatorCommit: COMMIT,
    now: Date.parse("2026-08-13T01:00:00Z"),
  });

  assert.equal(manifest.publication.status, VersionDeckPublicationStatus.DISABLED);
  assert.equal(manifest.releases.length, 0);
  assert.equal(manifest.latestStableReleaseId, null);
  assert.equal(diagnostics[0].type, "publication-disabled");
  assert.deepEqual(validateVersionDeckManifest(manifest, { now: Date.parse("2026-08-13T01:00:00Z") }), []);
});

test("buildManifest preserves explicit historical release dispositions", async () => {
  const historical = releaseFixture({
    id: 1001,
    version: "0.9.0",
    build: 1,
    name: "Owntend 0.9.0 (Build 1)",
    tag_name: "v0.9.0-build.1",
  });
  historical.assets = releaseFixture({ version: "0.9.0", build: 1 }).assets;

  const { manifest } = await buildManifest([historical], {
    ...normalizationOptions({
      verifyReleaseArtifact: async ({ version, build }) => verifierFixture({
        version,
        build,
        commitSha: "6".repeat(40),
      }),
    }),
    control: baseControl({
      historicalReleaseDecisions: [
        {
          releaseId: 1001,
          tag: "v0.9.0-build.1",
          commitSha: "6".repeat(40),
          status: "withdrawn",
          reasonCode: "withdrawn-prerelease",
          message: "Pre-release version withdrawn.",
          decidedAt: "2026-08-13T00:00:00Z",
        },
      ],
    }),
    generatorCommit: COMMIT,
    now: Date.parse("2026-08-13T01:00:00Z"),
  });

  assert.equal(manifest.latestStableReleaseId, null);
  assert.equal(
    manifest.releases[0].availability.status,
    VersionDeckReleaseAvailabilityStatus.WITHDRAWN,
  );
});

test("manifest validation requires exact verification evidence", async () => {
  const { manifest } = await buildManifest([releaseFixture()], {
    ...normalizationOptions(),
    control: baseControl(),
    generatorCommit: COMMIT,
    now: NOW,
  });
  manifest.releases[0].verification.signerVerified = false;
  assert.ok(validateVersionDeckManifest(manifest, { now: NOW }).some((error) =>
    error.includes("signerVerified")));
});

test("compareVersionBuild sorts highest build first", () => {
  const releases = [
    { id: 1, version: "2.0.0", build: 2, publishedAt: "2026-01-01T00:00:00Z" },
    { id: 2, version: "1.0.0", build: 3, publishedAt: "2026-01-01T00:00:00Z" },
  ];
  releases.sort(compareVersionBuild);
  assert.equal(releases[0].build, 3);
});

test("cache policy expires when the manifest lease expires", async () => {
  const { manifest } = await buildManifest([releaseFixture()], {
    ...normalizationOptions(),
    control: baseControl(),
    generatorCommit: COMMIT,
    now: NOW - 25 * 60 * 60 * 1000,
  });
  const record = {
    schemaVersion: RELEASE_CACHE_SCHEMA_VERSION,
    fetchedAt: new Date(NOW - 1 * 60 * 60 * 1000).toISOString(),
    manifest,
  };
  const policy = classifyReleaseCache(record, { now: NOW });
  assert.equal(policy.state, ReleaseCacheState.EXPIRED);
});

test("cache policy does not mutate records while advancing to expiry", async () => {
  const { manifest } = await buildManifest([releaseFixture()], {
    ...normalizationOptions(),
    control: baseControl(),
    generatorCommit: COMMIT,
    now: NOW - 7 * 60 * 60 * 1000,
  });
  const record = {
    schemaVersion: RELEASE_CACHE_SCHEMA_VERSION,
    fetchedAt: new Date(NOW - 7 * 60 * 60 * 1000).toISOString(),
    manifest,
  };
  const before = JSON.stringify(record);
  assert.equal(classifyReleaseCache(record, { now: NOW }).state, ReleaseCacheState.CACHED_STALE);
  assert.equal(
    classifyReleaseCache(record, { now: NOW + 18 * 60 * 60 * 1000 }).state,
    ReleaseCacheState.EXPIRED,
  );
  assert.equal(JSON.stringify(record), before);
});

test("relative time renders past and future values", () => {
  const now = Date.parse("2026-08-03T11:00:00Z");
  assert.equal(formatRelativeTime("2026-08-03T10:17:00Z", now, "en"), "43 minutes ago");
  assert.equal(formatRelativeTime("2026-08-03T11:02:00Z", now, "en"), "in 2 minutes");
});

test("service worker never caches releases.json", async () => {
  const serviceWorker = await fs.readFile(path.join(root, "download-site", "sw.js"), "utf8");
  const appShell = serviceWorker.match(/const APP_SHELL = \[([\s\S]*?)\];/)?.[1] || "";
  assert.doesNotMatch(appShell, /releases\.json/);
  assert.match(serviceWorker, /fetch\(request, \{ cache: "no-store" \}\)/);
});

test("committed VersionDeck control is fail-closed disabled and builds a valid manifest", async () => {
  const testNow = Date.parse("2026-08-21T14:30:00.000Z");
  const control = await loadVersionDeckControl(
    path.join(root, "tool", "versiondeck-control.json"),
    { now: testNow },
  );
  assert.equal(control.publication.status, VersionDeckPublicationStatus.DISABLED);
  assert.equal(control.publication.reasonCode, "pre-release");

  const { manifest } = await buildManifest([], {
    control,
    generatorCommit: COMMIT,
    now: testNow,
  });

  assert.equal(manifest.publication.status, VersionDeckPublicationStatus.DISABLED);
  assert.equal(manifest.releases.length, 0);
  assert.equal(manifest.latestStableReleaseId, null);
  assert.deepEqual(validateVersionDeckManifest(manifest, { now: testNow }), []);
});
