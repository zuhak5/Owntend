export const VERSIONDECK_SCHEMA_VERSION = 1;
export const VERSIONDECK_REPOSITORY = "zuhak5/Owntend";
export const VERSIONDECK_PACKAGE_NAME = "app.owntend.mobile";
export const VERSIONDECK_SIGNER_SHA256 =
  "3E:98:0E:B5:BB:68:A5:19:90:E7:70:56:D4:E1:09:95:B2:E0:4F:B3:88:A7:34:42:B7:9A:46:C8:53:36:1E:51";
export const VERSIONDECK_PROVENANCE_POLICY_VERSION = 1;
export const MAX_VERSIONDECK_MANIFEST_LEASE_MS = 24 * 60 * 60 * 1000;
export const VERSIONDECK_PRIMARY_ABI = "arm64-v8a";
export const VERSIONDECK_SPLIT_ABIS = Object.freeze([
  "arm64-v8a",
  "armeabi-v7a",
  "x86_64",
]);

export const VersionDeckPublicationStatus = Object.freeze({
  ACTIVE: "active",
  DISABLED: "disabled",
});
export const VersionDeckReleaseAvailabilityStatus = Object.freeze({
  ACTIVE: "active",
  WITHDRAWN: "withdrawn",
  SUPERSEDED: "superseded",
  REVOKED: "revoked",
  SUSPENDED: "suspended",
});
export const VersionDeckManifestState = Object.freeze({
  ACTIVE: "active",
  DISABLED: "disabled",
  EXPIRED: "expired",
  INVALID: "invalid",
});

const MAX_RELEASES = 200;
const MAX_SUMMARY_LENGTH = 280;
const MAX_CHANGELOG_ITEMS = 50;
const MAX_CHANGELOG_ITEM_LENGTH = 500;
const MAX_APK_SIZE_BYTES = 1024 * 1024 * 1024;
const MAX_STATE_TEXT_LENGTH = 240;
const FUTURE_CLOCK_SKEW_MS = 5 * 60 * 1000;
const SHA256_PATTERN = /^[a-f\d]{64}$/i;
const COMMIT_PATTERN = /^[a-f\d]{40}$/i;
const DIGIT_PATTERN = /^\d+$/;
const VERSION_PATTERN = /^\d+\.\d+\.\d+$/;
const SIGNER_PATTERN = /^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$/;
const DOWNLOAD_HOSTS = new Set([
  "owntend.app",
  "releases.owntend.app",
  "github.com",
  "objects.githubusercontent.com",
  "release-assets.githubusercontent.com",
]);
const GITHUB_TOKEN_ACTIONS_ISSUER = "https://token.actions.githubusercontent.com";

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
function parseDate(value) {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}
function isValidDate(value, now) {
  const parsed = parseDate(value);
  return Number.isFinite(parsed) && parsed <= now + FUTURE_CLOCK_SKEW_MS;
}
function validateUrl(value, allowedHosts, requiredPathPrefix = "") {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && allowedHosts.has(url.hostname) &&
      (!requiredPathPrefix || url.pathname.startsWith(requiredPathPrefix));
  } catch {
    return false;
  }
}
function validateOptionalStateText(value) {
  return value == null || (typeof value === "string" && value.length <= MAX_STATE_TEXT_LENGTH);
}
function expectedProvenanceWorkflow(repository) {
  return `https://github.com/${repository}/.github/workflows/shorebird-release-android.yml@refs/heads/main`;
}
function compareVersionBuild(left, right) {
  if (right.build !== left.build) return right.build - left.build;
  const leftParts = left.version.split(".").map(Number);
  const rightParts = right.version.split(".").map(Number);
  for (let index = 0; index < 3; index += 1) {
    if (rightParts[index] !== leftParts[index]) return rightParts[index] - leftParts[index];
  }
  return parseDate(right.publishedAt) - parseDate(left.publishedAt);
}

function validateProvenance(provenance, release, apk, label, now, errors) {
  const expectedWorkflow = expectedProvenanceWorkflow(VERSIONDECK_REPOSITORY);
  if (!isPlainObject(provenance)) {
    errors.push(`${label} provenance tuple is missing.`);
    return;
  }
  const exact = [
    [provenance.policyVersion, VERSIONDECK_PROVENANCE_POLICY_VERSION, "policy version"],
    [provenance.predicateType, "https://slsa.dev/provenance/v1", "predicate type"],
    [provenance.repository, VERSIONDECK_REPOSITORY, "repository"],
    [provenance.sourceRepositoryUri, `https://github.com/${VERSIONDECK_REPOSITORY}`, "source repository URI"],
    [provenance.sourceRepositoryDigest, release.commitSha, "source digest"],
    [provenance.sourceRepositoryRef, "refs/heads/main", "source ref"],
    [provenance.subjectName, apk.name, "subject name"],
    [provenance.artifactSha256, apk.sha256, "artifact SHA-256"],
    [provenance.signerWorkflow, expectedWorkflow, "signer workflow"],
    [provenance.signerDigest, release.commitSha, "signer digest"],
    [provenance.workflowName, "Shorebird Android Release", "workflow name"],
    [provenance.workflowTrigger, "workflow_dispatch", "workflow trigger"],
    [provenance.runnerEnvironment, "github-hosted", "runner environment"],
    [provenance.buildConfigUri, expectedWorkflow, "build-config URI"],
    [provenance.buildConfigDigest, release.commitSha, "build-config digest"],
    [provenance.oidcIssuer, GITHUB_TOKEN_ACTIONS_ISSUER, "OIDC issuer"],
    [provenance.sourceRepositoryVisibilityAtSigning, "public", "visibility"],
  ];
  for (const [actual, expected, description] of exact) {
    if (actual !== expected) errors.push(`${label} provenance ${description} is invalid.`);
  }
  if (!isValidDate(provenance.verifiedTimestamp, now)) {
    errors.push(`${label} provenance verification timestamp is invalid.`);
  }
  if (!DIGIT_PATTERN.test(String(provenance.runId || ""))) {
    errors.push(`${label} provenance run ID is invalid.`);
  }
  if (!DIGIT_PATTERN.test(String(provenance.runAttempt || ""))) {
    errors.push(`${label} provenance run attempt is invalid.`);
  }
  if (!validateUrl(
    provenance.runInvocationUri,
    new Set(["github.com"]),
    `/${VERSIONDECK_REPOSITORY}/actions/runs/`,
  )) {
    errors.push(`${label} provenance run URI is invalid.`);
  } else if (
    provenance.runInvocationUri !==
      `https://github.com/${VERSIONDECK_REPOSITORY}/actions/runs/${provenance.runId}/attempts/${provenance.runAttempt}`
  ) {
    errors.push(`${label} provenance run URI disagrees with run identifiers.`);
  }
  if (typeof provenance.sourceRepositoryIdentifier !== "string" ||
      !DIGIT_PATTERN.test(provenance.sourceRepositoryIdentifier)) {
    errors.push(`${label} provenance source repository identifier is invalid.`);
  }
  if (typeof provenance.sourceRepositoryOwnerIdentifier !== "string" ||
      !DIGIT_PATTERN.test(provenance.sourceRepositoryOwnerIdentifier)) {
    errors.push(`${label} provenance source repository owner identifier is invalid.`);
  }
  if (!validateUrl(provenance.sourceRepositoryOwnerUri, new Set(["github.com"]), "/zuhak5")) {
    errors.push(`${label} provenance source repository owner URI is invalid.`);
  }
}

function validateArtifactRecord({ apk, checksum, verification }, release, expectedName, label, now, errors) {
  if (!isPlainObject(apk) || apk.name !== expectedName) {
    errors.push(`${label} APK name does not match release metadata.`);
    return;
  }
  if (!validateUrl(apk.url, DOWNLOAD_HOSTS)) errors.push(`${label} has an invalid APK URL.`);
  if (!Number.isInteger(apk.size) || apk.size < 1 || apk.size > MAX_APK_SIZE_BYTES) {
    errors.push(`${label} has an invalid APK size.`);
  }
  if (!Number.isInteger(apk.downloadCount) || apk.downloadCount < 0) {
    errors.push(`${label} has an invalid download count.`);
  }
  if (!SHA256_PATTERN.test(apk.sha256 || "")) errors.push(`${label} has an invalid APK SHA-256.`);
  if (!isPlainObject(checksum) || checksum.name !== `${expectedName}.sha256`) {
    errors.push(`${label} checksum name does not match the APK.`);
  } else if (!validateUrl(checksum.url, DOWNLOAD_HOSTS)) {
    errors.push(`${label} has an invalid checksum URL.`);
  }
  if (!isPlainObject(verification) || verification.status !== "verified") {
    errors.push(`${label} is not verified.`);
    return;
  }
  if (!isValidDate(verification.verifiedAt, now)) errors.push(`${label} verification time is invalid.`);
  if (verification.signerCertificateSha256 !== VERSIONDECK_SIGNER_SHA256) {
    errors.push(`${label} signer verification does not match policy.`);
  }
  if (verification.attestationRepository !== VERSIONDECK_REPOSITORY) {
    errors.push(`${label} attestation repository is invalid.`);
  }
  validateProvenance(verification.provenance, release, apk, label, now, errors);
  for (const property of [
    "apkSha256Verified",
    "checksumAssetVerified",
    "githubDigestVerified",
    "packageNameVerified",
    "versionVerified",
    "buildVerified",
    "signerVerified",
    "commitVerified",
    "attestationVerified",
  ]) {
    if (verification[property] !== true) errors.push(`${label} verification flag ${property} is not true.`);
  }
}

function validateDistribution(release, releaseLabel, now, errors) {
  const universalName = `Owntend-${release.version}-build-${release.build}.apk`;
  const mode = release.distributionMode || "universal";
  if (mode === "universal") {
    validateArtifactRecord(release, release, universalName, releaseLabel, now, errors);
    if (release.apkVariants != null && (!Array.isArray(release.apkVariants) || release.apkVariants.length)) {
      errors.push(`${releaseLabel} universal distribution must not publish ABI variants.`);
    }
    return;
  }
  if (mode !== "abi") {
    errors.push(`${releaseLabel} distribution mode is invalid.`);
    return;
  }
  if (release.primaryAbi !== VERSIONDECK_PRIMARY_ABI) {
    errors.push(`${releaseLabel} primary ABI must be ${VERSIONDECK_PRIMARY_ABI}.`);
  }
  if (!Array.isArray(release.apkVariants) || release.apkVariants.length !== VERSIONDECK_SPLIT_ABIS.length) {
    errors.push(`${releaseLabel} must contain exactly three ABI variants.`);
    return;
  }
  const seen = new Set();
  for (const variant of release.apkVariants) {
    const abi = variant?.abi;
    const label = `${releaseLabel} ${abi || "ABI"}`;
    if (!VERSIONDECK_SPLIT_ABIS.includes(abi) || seen.has(abi)) {
      errors.push(`${releaseLabel} has a missing, duplicate, or unexpected ABI variant.`);
      continue;
    }
    seen.add(abi);
    validateArtifactRecord(
      variant,
      release,
      `Owntend-${release.version}-build-${release.build}-${abi}.apk`,
      label,
      now,
      errors,
    );
  }
  for (const abi of VERSIONDECK_SPLIT_ABIS) {
    if (!seen.has(abi)) errors.push(`${releaseLabel} is missing ABI variant ${abi}.`);
  }
  const primary = release.apkVariants.find((variant) => variant.abi === VERSIONDECK_PRIMARY_ABI);
  if (primary) {
    for (const field of ["apk", "checksum", "verification"]) {
      if (JSON.stringify(release[field]) !== JSON.stringify(primary[field])) {
        errors.push(`${releaseLabel} primary ${field} alias does not match ${VERSIONDECK_PRIMARY_ABI}.`);
      }
    }
  }
}

export function validateVersionDeckManifest(manifest, { now = Date.now() } = {}) {
  const errors = [];
  if (!isPlainObject(manifest)) return ["Manifest is not an object."];
  if (manifest.schemaVersion !== VERSIONDECK_SCHEMA_VERSION) errors.push("Unsupported release manifest schema.");
  if (manifest.repository !== VERSIONDECK_REPOSITORY) errors.push("Unexpected release repository.");
  if (!isValidDate(manifest.generatedAt, now)) errors.push("Manifest generation time is invalid.");
  if (!COMMIT_PATTERN.test(manifest.generatorCommit || "")) errors.push("Manifest generator commit is invalid.");
  const generatedAt = parseDate(manifest.generatedAt);
  const leaseExpiresAt = parseDate(manifest.leaseExpiresAt);
  if (!Number.isFinite(leaseExpiresAt)) errors.push("Manifest trust lease expiry is invalid.");
  else if (Number.isFinite(generatedAt)) {
    if (leaseExpiresAt <= generatedAt) errors.push("Manifest trust lease must end after generation.");
    if (leaseExpiresAt - generatedAt > MAX_VERSIONDECK_MANIFEST_LEASE_MS + FUTURE_CLOCK_SKEW_MS) {
      errors.push("Manifest trust lease exceeds the maximum duration.");
    }
  }
  if (manifest.package?.name !== VERSIONDECK_PACKAGE_NAME) errors.push("Unexpected production package identity.");
  if (manifest.package?.signerCertificateSha256 !== VERSIONDECK_SIGNER_SHA256) {
    errors.push("Unexpected production signer fingerprint.");
  }
  if (!SIGNER_PATTERN.test(manifest.package?.signerCertificateSha256 || "")) {
    errors.push("Production signer fingerprint has invalid formatting.");
  }
  if (!isPlainObject(manifest.publication)) errors.push("Manifest publication state is missing.");
  else {
    const status = manifest.publication.status;
    if (![VersionDeckPublicationStatus.ACTIVE, VersionDeckPublicationStatus.DISABLED].includes(status)) {
      errors.push("Manifest publication status is invalid.");
    }
    if (!validateOptionalStateText(manifest.publication.reasonCode)) errors.push("Manifest publication reason is invalid.");
    if (!validateOptionalStateText(manifest.publication.message)) errors.push("Manifest publication message is invalid.");
    if (manifest.publication.updatedAt != null && !isValidDate(manifest.publication.updatedAt, now)) {
      errors.push("Manifest publication update time is invalid.");
    }
    if (status === VersionDeckPublicationStatus.DISABLED) {
      if (!manifest.publication.reasonCode) errors.push("Disabled manifests must record a publication reason.");
      if (!manifest.publication.message) errors.push("Disabled manifests must record a publication message.");
      if (!isValidDate(manifest.publication.updatedAt, now)) errors.push("Disabled manifests must record a publication update time.");
    }
  }
  if (!Array.isArray(manifest.releases)) {
    errors.push("Release list is missing.");
    return errors;
  }
  if (manifest.releases.length > MAX_RELEASES) errors.push(`Release list exceeds ${MAX_RELEASES} entries.`);
  const ids = new Set();
  const supersededTargets = [];
  for (const release of manifest.releases) {
    if (!isPlainObject(release)) { errors.push("Release entry is not an object."); continue; }
    const label = Number.isInteger(release.id) ? `Release ${release.id}` : "Release";
    if (!Number.isInteger(release.id) || release.id < 1 || ids.has(release.id)) errors.push(`${label} has a missing or duplicated ID.`);
    else ids.add(release.id);
    if (!VERSION_PATTERN.test(release.version || "")) errors.push(`${label} has an invalid version.`);
    if (!Number.isInteger(release.build) || release.build < 1) errors.push(`${label} has an invalid build number.`);
    if (release.tag !== `v${release.version}-build.${release.build}`) errors.push(`${label} tag does not match version and build.`);
    if (typeof release.prerelease !== "boolean") errors.push(`${label} prerelease flag is invalid.`);
    if (!isValidDate(release.publishedAt, now)) errors.push(`${label} has an invalid publication time.`);
    if (!validateUrl(release.releaseUrl, new Set(["github.com"]), `/${VERSIONDECK_REPOSITORY}/releases/`)) {
      errors.push(`${label} has an invalid release URL.`);
    }
    if (!COMMIT_PATTERN.test(release.commitSha || "")) errors.push(`${label} has an invalid release commit.`);
    if (typeof release.summary !== "string" || release.summary.length > MAX_SUMMARY_LENGTH) errors.push(`${label} has an invalid summary.`);
    if (!Array.isArray(release.changelog) || release.changelog.length > MAX_CHANGELOG_ITEMS ||
        release.changelog.some((item) => typeof item !== "string" || item.length > MAX_CHANGELOG_ITEM_LENGTH)) {
      errors.push(`${label} has an invalid changelog.`);
    }
    const availability = release.availability;
    if (!isPlainObject(availability)) errors.push(`${label} availability is missing.`);
    else {
      if (!Object.values(VersionDeckReleaseAvailabilityStatus).includes(availability.status)) errors.push(`${label} availability status is invalid.`);
      if (!validateOptionalStateText(availability.reasonCode)) errors.push(`${label} availability reason is invalid.`);
      if (!validateOptionalStateText(availability.message)) errors.push(`${label} availability message is invalid.`);
      if (availability.decidedAt != null && !isValidDate(availability.decidedAt, now)) errors.push(`${label} availability decision time is invalid.`);
      if (availability.status === VersionDeckReleaseAvailabilityStatus.SUPERSEDED) {
        if (!Number.isInteger(availability.supersededByReleaseId) || availability.supersededByReleaseId < 1 ||
            availability.supersededByReleaseId === release.id) errors.push(`${label} superseded target is invalid.`);
        else supersededTargets.push([label, availability.supersededByReleaseId]);
      } else if (availability.supersededByReleaseId != null) errors.push(`${label} has an unexpected superseded target.`);
    }
    validateDistribution(release, label, now, errors);
  }
  for (const [label, target] of supersededTargets) if (!ids.has(target)) errors.push(`${label} superseded target does not exist in the manifest.`);
  for (let index = 1; index < manifest.releases.length; index += 1) {
    if (compareVersionBuild(manifest.releases[index - 1], manifest.releases[index]) > 0) {
      errors.push("Release list is not sorted by descending build and version."); break;
    }
  }
  const stable = manifest.latestStableReleaseId;
  if (stable !== null && !manifest.releases.some((release) => release.id === stable && !release.prerelease && release.availability?.status === VersionDeckReleaseAvailabilityStatus.ACTIVE)) {
    errors.push("Latest stable release does not reference an active stable release.");
  }
  const prerelease = manifest.latestPrereleaseReleaseId;
  if (prerelease !== null && !manifest.releases.some((release) => release.id === prerelease && release.prerelease && release.availability?.status === VersionDeckReleaseAvailabilityStatus.ACTIVE)) {
    errors.push("Latest prerelease does not reference an active prerelease.");
  }
  if (manifest.publication?.status === VersionDeckPublicationStatus.DISABLED && (stable !== null || prerelease !== null)) {
    errors.push("Disabled manifests must not advertise active latest releases.");
  }
  return errors;
}

export function classifyVersionDeckManifest(manifest, { now = Date.now() } = {}) {
  const errors = validateVersionDeckManifest(manifest, { now });
  if (errors.length) return { state: VersionDeckManifestState.INVALID, errors, leaseExpiresAt: Number.NaN };
  const leaseExpiresAt = parseDate(manifest.leaseExpiresAt);
  if (!Number.isFinite(leaseExpiresAt) || leaseExpiresAt <= now) {
    return { state: VersionDeckManifestState.EXPIRED, errors: [], leaseExpiresAt };
  }
  return {
    state: manifest.publication.status === VersionDeckPublicationStatus.DISABLED
      ? VersionDeckManifestState.DISABLED
      : VersionDeckManifestState.ACTIVE,
    errors: [],
    leaseExpiresAt,
  };
}
