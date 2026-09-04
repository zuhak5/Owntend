import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  MAX_VERSIONDECK_MANIFEST_LEASE_MS,
  VERSIONDECK_PACKAGE_NAME,
  VERSIONDECK_PRIMARY_ABI,
  VERSIONDECK_REPOSITORY,
  VERSIONDECK_SCHEMA_VERSION,
  VERSIONDECK_SIGNER_SHA256,
  VERSIONDECK_SPLIT_ABIS,
  VersionDeckPublicationStatus,
  VersionDeckReleaseAvailabilityStatus,
  validateVersionDeckManifest,
} from "../download-site/manifest-schema.js";
import {
  assertExpectedRepository,
  fetchAllReleases,
  prepareVerificationRepository,
  readChecksumAsset,
  verifyReleaseArtifact,
} from "./versiondeck_apk_verifier.mjs";

export const VERSIONDECK_CONTROL_SCHEMA_VERSION = 1;
export const DEFAULT_VERSIONDECK_LEASE_HOURS = MAX_VERSIONDECK_MANIFEST_LEASE_MS / (60 * 60 * 1000);

const RELEASE_NAME_PATTERN = /^Owntend\s+(\d+\.\d+\.\d+)\s+\(Build\s+(\d+)\)$/i;
const TAG_PATTERN = /^v(\d+\.\d+\.\d+)-build\.(\d+)$/i;
const UNIVERSAL_APK_PATTERN = /^Owntend-(\d+\.\d+\.\d+)-build-(\d+)\.apk$/i;
const SHA256_PATTERN = /^[a-f\d]{64}$/i;
const COMMIT_PATTERN = /^[a-f\d]{40}$/i;
const MAX_APK_SIZE_BYTES = 1024 * 1024 * 1024;
const FUTURE_CLOCK_SKEW_MS = 5 * 60 * 1000;

function normalizedSha(value) {
  const normalized = String(value || "").replace(/^sha256:/i, "").replace(/[^a-f\d]/gi, "").toLowerCase();
  return SHA256_PATTERN.test(normalized) ? normalized : "";
}
function normalizedSigner(value) {
  const normalized = String(value || "").replace(/[^a-f\d]/gi, "").toUpperCase();
  return normalized.length === 64 ? normalized.match(/.{2}/g).join(":") : "";
}
function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
function isValidDate(value, now = Date.now()) {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && parsed <= now + FUTURE_CLOCK_SKEW_MS;
}
function optionalShortText(value) {
  return value == null || (typeof value === "string" && value.length > 0 && value.length <= 240);
}
function defaultVersionDeckControl() {
  return {
    schemaVersion: VERSIONDECK_CONTROL_SCHEMA_VERSION,
    leaseDurationHours: DEFAULT_VERSIONDECK_LEASE_HOURS,
    publication: { status: VersionDeckPublicationStatus.ACTIVE, reasonCode: null, message: null, updatedAt: null },
    historicalReleaseDecisions: [],
  };
}

export function parseVersion(value) {
  const parts = String(value || "").split(".").map(Number);
  return parts.length === 3 && parts.every((part) => Number.isInteger(part) && part >= 0) ? parts : null;
}
export function compareVersionBuild(left, right) {
  const leftParts = parseVersion(left.version) ?? [0, 0, 0];
  const rightParts = parseVersion(right.version) ?? [0, 0, 0];
  for (let index = 0; index < 3; index += 1) if (rightParts[index] !== leftParts[index]) return rightParts[index] - leftParts[index];
  if (right.build !== left.build) return right.build - left.build;
  const dateDifference = Date.parse(right.publishedAt) - Date.parse(left.publishedAt);
  return dateDifference || Number(right.id) - Number(left.id);
}
export function extractBodySha(body) {
  return normalizedSha(String(body || "").match(/SHA-256:\s*`?([a-f\d]{64})`?/i)?.[1]);
}
export function parseChecksumText(value, expectedFileName) {
  const line = String(value || "").replace(/^\uFEFF/, "").split(/\r?\n/).map((item) => item.trim()).find(Boolean);
  const match = line?.match(/^([a-f\d]{64})\s+\*?(.+)$/i);
  if (!match || match[2].trim() !== expectedFileName) return null;
  const sha256 = normalizedSha(match[1]);
  return sha256 ? { sha256, fileName: expectedFileName } : null;
}
export function summarizeReleaseBody(body) {
  const cleaned = String(body || "").replace(/##\s*Build details[\s\S]*/i, "").replace(/##\s*What's changed/i, "").trim();
  const ignored = /^(included|notes|changes|what's changed|build details)$/i;
  const changelog = cleaned.split(/\r?\n/).map((line) => line.replace(/^[-*#\s]+/, "").trim())
    .filter(Boolean).filter((line) => !ignored.test(line) && !/^Owntend\s+\d/i.test(line))
    .map((line) => line.slice(0, 500)).slice(0, 50);
  return { summary: (changelog.slice(0, 2).join(" ") || "Signed production build of Owntend for Android.").slice(0, 240), changelog };
}

export function validateReleaseShape(release) {
  if (!release || typeof release !== "object") return ["Release is not an object."];
  const errors = [];
  if (!Number.isInteger(release.id)) errors.push("Release ID is missing or invalid.");
  if (release.draft) errors.push("Draft releases are not eligible.");
  const published = Date.parse(release.published_at);
  if (!Number.isFinite(published)) errors.push("published_at is missing or invalid.");
  if (published > Date.now() + FUTURE_CLOCK_SKEW_MS) errors.push("published_at is in the future.");
  const nameMatch = String(release.name || "").match(RELEASE_NAME_PATTERN);
  const tagMatch = String(release.tag_name || "").match(TAG_PATTERN);
  if (!nameMatch) errors.push("Release title must match 'Owntend X.Y.Z (Build N)'.");
  if (!tagMatch) errors.push("Release tag must match 'vX.Y.Z-build.N'.");
  if (nameMatch && tagMatch && (nameMatch[1] !== tagMatch[1] || nameMatch[2] !== tagMatch[2])) errors.push("Release title and tag disagree.");
  if (!String(release.html_url || "").startsWith(`https://github.com/${VERSIONDECK_REPOSITORY}/releases/`)) errors.push("Release URL is outside the expected repository.");
  return errors;
}

function validateAsset(asset, expectedName) {
  if (!asset) return `Expected exactly one production APK named ${expectedName}; found 0.`;
  if (asset.state !== "uploaded") return `${expectedName} is not uploaded.`;
  if (!Number.isInteger(asset.size) || asset.size < 1 || asset.size > MAX_APK_SIZE_BYTES) return `${expectedName} size is invalid.`;
  if (!String(asset.browser_download_url || "").startsWith("https://github.com/")) return `${expectedName} URL is invalid.`;
  return null;
}

export function selectProductionApk(release, version, build) {
  const expectedName = `Owntend-${version}-build-${build}.apk`;
  const exact = (release.assets || []).filter((asset) => asset?.name === expectedName);
  if (exact.length !== 1) return { asset: null, error: `Expected exactly one production APK named ${expectedName}; found ${exact.length}.` };
  const match = exact[0].name.match(UNIVERSAL_APK_PATTERN);
  if (!match || match[1] !== version || match[2] !== String(build)) return { asset: null, error: "APK filename does not match release metadata." };
  const error = validateAsset(exact[0], expectedName);
  return error ? { asset: null, error } : { asset: exact[0], error: null };
}

export function selectProductionApkVariants(release, version, build) {
  const candidates = [];
  const errors = [];
  for (const abi of VERSIONDECK_SPLIT_ABIS) {
    const name = `Owntend-${version}-build-${build}-${abi}.apk`;
    const exact = (release.assets || []).filter((asset) => asset?.name === name);
    if (exact.length !== 1) errors.push(`Expected exactly one ABI APK named ${name}; found ${exact.length}.`);
    else {
      const error = validateAsset(exact[0], name);
      if (error) errors.push(error);
      else candidates.push({ abi, asset: exact[0] });
    }
  }
  const prefix = `Owntend-${version}-build-${build}-`;
  const recognizedNames = new Set(VERSIONDECK_SPLIT_ABIS.map((abi) => `${prefix}${abi}.apk`));
  const unexpected = (release.assets || []).filter((asset) =>
    typeof asset?.name === "string" && asset.name.startsWith(prefix) && asset.name.endsWith(".apk") && !recognizedNames.has(asset.name));
  if (unexpected.length) errors.push(`Unexpected ABI APK assets: ${unexpected.map((asset) => asset.name).join(", ")}.`);
  return { variants: errors.length ? null : candidates, errors };
}

function selectChecksum(release, apkName) {
  const expectedName = `${apkName}.sha256`;
  const exact = (release.assets || []).filter((asset) => asset?.name === expectedName);
  if (exact.length !== 1) return { asset: null, error: `Expected exactly one checksum named ${expectedName}.` };
  const asset = exact[0];
  if (asset.state !== "uploaded") return { asset: null, error: "Checksum is not uploaded." };
  if (!String(asset.browser_download_url || "").startsWith("https://github.com/")) return { asset: null, error: "Checksum URL is invalid." };
  return { asset, error: null };
}

export function validateVersionDeckControl(control, { now = Date.now() } = {}) {
  if (!isPlainObject(control)) return ["VersionDeck control is not an object."];
  const errors = [];
  if (control.schemaVersion !== VERSIONDECK_CONTROL_SCHEMA_VERSION) errors.push("VersionDeck control schema is invalid.");
  if (!Number.isInteger(control.leaseDurationHours) || control.leaseDurationHours < 1 || control.leaseDurationHours > DEFAULT_VERSIONDECK_LEASE_HOURS) errors.push("VersionDeck control lease duration is invalid.");
  if (!isPlainObject(control.publication)) errors.push("VersionDeck publication control is missing.");
  else {
    if (![VersionDeckPublicationStatus.ACTIVE, VersionDeckPublicationStatus.DISABLED].includes(control.publication.status)) errors.push("VersionDeck publication status is invalid.");
    if (!optionalShortText(control.publication.reasonCode)) errors.push("VersionDeck publication reason is invalid.");
    if (!optionalShortText(control.publication.message)) errors.push("VersionDeck publication message is invalid.");
    if (control.publication.updatedAt != null && !isValidDate(control.publication.updatedAt, now)) errors.push("VersionDeck publication update time is invalid.");
    if (control.publication.status === VersionDeckPublicationStatus.DISABLED) {
      if (!control.publication.reasonCode) errors.push("Disabled publication requires a reason code.");
      if (!control.publication.message) errors.push("Disabled publication requires a message.");
      if (!isValidDate(control.publication.updatedAt, now)) errors.push("Disabled publication requires an update time.");
    }
  }
  if (!Array.isArray(control.historicalReleaseDecisions)) errors.push("Historical release decisions must be an array.");
  else {
    const releaseIds = new Set(); const tags = new Set();
    for (const decision of control.historicalReleaseDecisions) {
      if (!isPlainObject(decision)) { errors.push("Historical release decision is invalid."); continue; }
      if (!Number.isInteger(decision.releaseId) || decision.releaseId < 1) errors.push("Historical release decision ID is invalid.");
      else if (releaseIds.has(decision.releaseId)) errors.push(`Historical release decision ${decision.releaseId} is duplicated.`); else releaseIds.add(decision.releaseId);
      if (!TAG_PATTERN.test(decision.tag || "")) errors.push("Historical release decision tag is invalid.");
      else if (tags.has(decision.tag)) errors.push(`Historical release decision ${decision.tag} is duplicated.`); else tags.add(decision.tag);
      if (!COMMIT_PATTERN.test(decision.commitSha || "")) errors.push("Historical release decision commit SHA is invalid.");
      if (!["withdrawn", "superseded", "historical-trust"].includes(decision.status)) errors.push("Historical release decision status is invalid.");
      if (typeof decision.reasonCode !== "string" || !decision.reasonCode || decision.reasonCode.length > 240) errors.push("Historical release decision reason is invalid.");
      if (typeof decision.message !== "string" || !decision.message || decision.message.length > 240) errors.push("Historical release decision message is invalid.");
      if (!isValidDate(decision.decidedAt, now)) errors.push("Historical release decision time is invalid.");
      if (decision.status === "superseded") {
        if (!Number.isInteger(decision.supersededByReleaseId) || decision.supersededByReleaseId < 1 || decision.supersededByReleaseId === decision.releaseId) errors.push("Superseded historical release decision target is invalid.");
      } else if (decision.supersededByReleaseId != null) errors.push("Unexpected superseded target for historical release decision.");
    }
  }
  return errors;
}

function normalizeVersionDeckControl(control, { now = Date.now() } = {}) {
  const resolved = control == null ? defaultVersionDeckControl() : control;
  const errors = validateVersionDeckControl(resolved, { now });
  if (errors.length) throw new Error(`VersionDeck control is invalid: ${errors.join(" ")}`);
  return resolved;
}
export async function loadVersionDeckControl(controlPath, { now = Date.now() } = {}) {
  return normalizeVersionDeckControl(JSON.parse(await fs.readFile(controlPath, "utf8")), { now });
}
export function resolveHistoricalReleaseDecision(release, control) {
  const match = (control?.historicalReleaseDecisions || []).find((decision) => decision.releaseId === release.id || decision.tag === release.tag_name);
  if (!match) return null;
  if (match.releaseId !== release.id || match.tag !== release.tag_name) throw new Error("Historical release decision does not exactly match the release ID and tag.");
  return match;
}
function buildReleaseAvailability(decision, commitSha) {
  if (!decision) return { status: VersionDeckReleaseAvailabilityStatus.ACTIVE };
  if (decision.commitSha.toLowerCase() !== String(commitSha).toLowerCase()) throw new Error("Historical release decision commit does not match the verified release commit.");
  if (decision.status === "historical-trust") return { status: VersionDeckReleaseAvailabilityStatus.ACTIVE, reasonCode: decision.reasonCode, message: decision.message, decidedAt: decision.decidedAt };
  if (decision.status === "withdrawn") return { status: VersionDeckReleaseAvailabilityStatus.WITHDRAWN, reasonCode: decision.reasonCode, message: decision.message, decidedAt: decision.decidedAt };
  return { status: VersionDeckReleaseAvailabilityStatus.SUPERSEDED, reasonCode: decision.reasonCode, message: decision.message, decidedAt: decision.decidedAt, supersededByReleaseId: decision.supersededByReleaseId };
}
function buildManifestPublication(publication) {
  return { status: publication.status, reasonCode: publication.reasonCode ?? null, message: publication.message ?? null, updatedAt: publication.updatedAt ?? null };
}
function makeVerification(evidence, now) {
  return {
    status: "verified",
    verifiedAt: new Date(now).toISOString(),
    signerCertificateSha256: VERSIONDECK_SIGNER_SHA256,
    attestationRepository: VERSIONDECK_REPOSITORY,
    provenance: evidence.provenance,
    apkSha256Verified: true,
    checksumAssetVerified: true,
    githubDigestVerified: true,
    packageNameVerified: true,
    versionVerified: true,
    buildVerified: true,
    signerVerified: true,
    commitVerified: true,
    attestationVerified: true,
  };
}

async function verifyAssetRecord({ release, asset, abi, version, build, historicalDecision, options, now, bodySha }) {
  const errors = [];
  const checksumResult = selectChecksum(release, asset.name);
  if (checksumResult.error) errors.push(checksumResult.error);
  if (!checksumResult.asset) return { record: null, evidence: null, errors };
  let checksum = null;
  try {
    if (typeof options.readChecksumAsset !== "function") throw new Error("reader unavailable");
    checksum = parseChecksumText(await options.readChecksumAsset(checksumResult.asset), asset.name);
    if (!checksum) errors.push(`Checksum asset contents are invalid for ${asset.name}.`);
  } catch (error) { errors.push(`Checksum asset could not be read for ${asset.name}: ${error.message}`); }
  const githubDigest = normalizedSha(asset.digest);
  const asserted = [githubDigest, checksum?.sha256, ...(bodySha ? [bodySha] : [])].filter(Boolean);
  if (!githubDigest) errors.push(`GitHub asset digest is missing for ${asset.name}.`);
  if (!checksum?.sha256) errors.push(`Checksum SHA-256 is missing for ${asset.name}.`);
  if (new Set(asserted).size > 1) errors.push(`Release SHA-256 sources disagree for ${asset.name}.`);
  let evidence = null;
  try {
    if (typeof options.verifyReleaseArtifact !== "function") throw new Error("verifier unavailable");
    evidence = await options.verifyReleaseArtifact({ release, apkAsset: asset, version, build, historicalDecision, expectedAbi: abi });
  } catch (error) { errors.push(`Independent APK verification failed for ${asset.name}: ${error.message}`); }
  const localSha = normalizedSha(evidence?.sha256);
  if (!localSha) errors.push(`Independent APK SHA-256 is missing for ${asset.name}.`);
  if (localSha && asserted.some((sha) => sha !== localSha)) errors.push(`Independent APK SHA-256 disagrees with release metadata for ${asset.name}.`);
  if (evidence?.packageName !== VERSIONDECK_PACKAGE_NAME) errors.push(`APK package is unexpected for ${asset.name}.`);
  if (evidence?.version !== version) errors.push(`APK version is unexpected for ${asset.name}.`);
  if (Number(evidence?.build) !== build) errors.push(`APK build is unexpected for ${asset.name}.`);
  if (evidence?.abi && evidence.abi !== abi) errors.push(`APK ABI evidence is unexpected for ${asset.name}.`);
  if (normalizedSigner(evidence?.signerCertificateSha256) !== VERSIONDECK_SIGNER_SHA256) errors.push(`APK signer does not match production policy for ${asset.name}.`);
  if (!COMMIT_PATTERN.test(evidence?.commitSha || "")) errors.push(`Release commit is invalid for ${asset.name}.`);
  if (evidence?.attestationVerified !== true) errors.push(`Provenance attestation did not verify for ${asset.name}.`);
  if (!isPlainObject(evidence?.provenance)) errors.push(`Provenance tuple is missing for ${asset.name}.`);
  if (evidence?.provenance?.artifactSha256 !== localSha) errors.push(`Provenance tuple SHA-256 is unexpected for ${asset.name}.`);
  if (evidence?.provenance?.subjectName !== asset.name) errors.push(`Provenance tuple subject name is unexpected for ${asset.name}.`);
  if (evidence?.provenance?.sourceRepositoryDigest !== evidence?.commitSha) errors.push(`Provenance tuple source digest disagrees with the release commit for ${asset.name}.`);
  if (errors.length) return { record: null, evidence, errors };
  return {
    evidence,
    errors: [],
    record: {
      abi,
      apk: { name: asset.name, url: asset.browser_download_url, size: asset.size, downloadCount: Number(asset.download_count) || 0, sha256: localSha },
      checksum: { name: checksumResult.asset.name, url: checksumResult.asset.browser_download_url },
      verification: makeVerification(evidence, now),
    },
  };
}

export async function normalizeRelease(release, options = {}) {
  const now = options.now ?? Date.now();
  const errors = validateReleaseShape(release);
  const tagMatch = String(release.tag_name || "").match(TAG_PATTERN);
  if (!tagMatch) return { release: null, errors };
  const version = tagMatch[1]; const build = Number(tagMatch[2]);
  const historicalDecision = options.historicalDecision ?? null;
  const split = selectProductionApkVariants(release, version, build);
  const hasAnySplitName = (release.assets || []).some((asset) =>
    VERSIONDECK_SPLIT_ABIS.some((abi) => asset?.name === `Owntend-${version}-build-${build}-${abi}.apk`));
  let records = [];
  let distributionMode = "universal";
  if (hasAnySplitName) {
    errors.push(...split.errors);
    if (!split.variants) return { release: null, errors };
    distributionMode = "abi";
    for (const { abi, asset } of split.variants) {
      const verified = await verifyAssetRecord({ release, asset, abi, version, build, historicalDecision, options, now, bodySha: "" });
      errors.push(...verified.errors);
      if (verified.record) records.push({ ...verified.record, evidence: verified.evidence });
    }
  } else {
    const apkResult = selectProductionApk(release, version, build);
    if (apkResult.error) errors.push(apkResult.error);
    if (!apkResult.asset) return { release: null, errors };
    const verified = await verifyAssetRecord({ release, asset: apkResult.asset, abi: "universal", version, build, historicalDecision, options, now, bodySha: extractBodySha(release.body) });
    errors.push(...verified.errors);
    if (verified.record) records.push({ ...verified.record, evidence: verified.evidence });
  }
  const commitShas = new Set(records.map((record) => record.evidence?.commitSha?.toLowerCase()).filter(Boolean));
  if (commitShas.size !== 1) errors.push("Verified APK variants do not share one release commit.");
  const commitSha = [...commitShas][0] || "";
  let availability = null;
  try { availability = buildReleaseAvailability(historicalDecision, commitSha); } catch (error) { errors.push(error.message); }
  if (errors.length) return { release: null, errors };
  const cleanRecords = records.map(({ evidence, ...record }) => record);
  const primary = distributionMode === "abi"
    ? cleanRecords.find((record) => record.abi === VERSIONDECK_PRIMARY_ABI)
    : cleanRecords[0];
  const text = summarizeReleaseBody(release.body);
  const normalized = {
    id: release.id,
    tag: release.tag_name,
    version,
    build,
    prerelease: Boolean(release.prerelease),
    publishedAt: new Date(release.published_at).toISOString(),
    releaseUrl: release.html_url,
    commitSha,
    availability,
    ...text,
    distributionMode,
    apk: primary.apk,
    checksum: primary.checksum,
    verification: primary.verification,
  };
  if (distributionMode === "abi") {
    normalized.primaryAbi = VERSIONDECK_PRIMARY_ABI;
    normalized.apkVariants = cleanRecords;
  }
  return { errors: [], release: normalized };
}

export async function buildManifest(rawReleases, options = {}) {
  const now = options.now ?? Date.now();
  const control = normalizeVersionDeckControl(options.control, { now });
  const generatedAt = new Date(now).toISOString();
  const leaseExpiresAt = new Date(Date.parse(generatedAt) + control.leaseDurationHours * 60 * 60 * 1000).toISOString();
  const publication = buildManifestPublication(control.publication);
  const generatorCommit = String(options.generatorCommit || process.env.VERSIONDECK_GENERATOR_COMMIT || "");
  const base = {
    schemaVersion: VERSIONDECK_SCHEMA_VERSION,
    generatedAt,
    leaseExpiresAt,
    generatorCommit,
    repository: VERSIONDECK_REPOSITORY,
    package: { name: VERSIONDECK_PACKAGE_NAME, signerCertificateSha256: VERSIONDECK_SIGNER_SHA256 },
    publication,
  };
  const diagnostics = [];
  if (publication.status === VersionDeckPublicationStatus.DISABLED) {
    const manifest = { ...base, latestStableReleaseId: null, latestPrereleaseReleaseId: null, releases: [] };
    const errors = validateVersionDeckManifest(manifest, { now });
    if (errors.length) throw new Error(`Generated manifest is invalid: ${errors.join(" ")}`);
    diagnostics.push({ type: "publication-disabled", reasonCode: publication.reasonCode, message: publication.message, updatedAt: publication.updatedAt });
    return { manifest, diagnostics };
  }
  const releases = [];
  for (const raw of rawReleases) {
    if (raw?.draft) continue;
    const historicalDecision = resolveHistoricalReleaseDecision(raw, control);
    const result = await normalizeRelease(raw, { ...options, historicalDecision });
    if (result.release) releases.push(result.release);
    else diagnostics.push({ id: raw?.id ?? null, tag: raw?.tag_name ?? "", errors: result.errors });
  }
  releases.sort(compareVersionBuild);
  const manifest = {
    ...base,
    latestStableReleaseId: releases.find((item) => !item.prerelease && item.availability.status === VersionDeckReleaseAvailabilityStatus.ACTIVE)?.id ?? null,
    latestPrereleaseReleaseId: releases.find((item) => item.prerelease && item.availability.status === VersionDeckReleaseAvailabilityStatus.ACTIVE)?.id ?? null,
    releases,
  };
  const errors = validateVersionDeckManifest(manifest, { now });
  if (errors.length) throw new Error(`Generated manifest is invalid: ${errors.join(" ")}`);
  return { manifest, diagnostics };
}

function newest(rawReleases, prerelease) {
  return rawReleases.filter((release) => !release.draft && Boolean(release.prerelease) === prerelease)
    .filter((release) => Number.isFinite(Date.parse(release.published_at)))
    .sort((left, right) => Date.parse(right.published_at) - Date.parse(left.published_at))[0] ?? null;
}
function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index]; const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined) throw new Error("Arguments must use --name value pairs.");
    values[key.slice(2)] = value;
  }
  return values;
}

export async function main(argv = process.argv.slice(2)) {
  const args = parseArguments(argv);
  const repository = process.env.GITHUB_REPOSITORY || VERSIONDECK_REPOSITORY;
  assertExpectedRepository(repository);
  const generatorCommit = process.env.VERSIONDECK_GENERATOR_COMMIT || "";
  if (!COMMIT_PATTERN.test(generatorCommit)) throw new Error("VERSIONDECK_GENERATOR_COMMIT must be a full main commit SHA.");
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const control = await loadVersionDeckControl(path.resolve(root, args.control || "tool/versiondeck-control.json"));
  const publicationMode = args["publication-mode"] || "verified";
  if (!["verified", "disabled"].includes(publicationMode)) throw new Error("Publication mode must be either verified or disabled.");
  if (publicationMode === "disabled" && control.publication.status !== VersionDeckPublicationStatus.DISABLED) throw new Error("Disabled publication mode requires a disabled VersionDeck control state.");
  if (publicationMode === "verified" && control.publication.status !== VersionDeckPublicationStatus.ACTIVE) throw new Error("Verified publication mode requires an active VersionDeck control state.");
  const checkedOutCommit = await prepareVerificationRepository();
  if (checkedOutCommit !== generatorCommit.toLowerCase()) throw new Error("Checked-out source does not match VERSIONDECK_GENERATOR_COMMIT.");
  let result;
  if (publicationMode === "verified") {
    const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
    if (!token) throw new Error("GITHUB_TOKEN or GH_TOKEN is required.");
    const rawReleases = await fetchAllReleases(repository, token);
    result = await buildManifest(rawReleases, {
      control,
      generatorCommit,
      readChecksumAsset: (asset) => readChecksumAsset(asset, token),
      verifyReleaseArtifact: (context) => verifyReleaseArtifact(context, token),
    });
    for (const prerelease of [false, true]) {
      const latest = newest(rawReleases, prerelease);
      if (latest && !result.manifest.releases.some((release) => release.id === latest.id)) throw new Error(`Newest ${prerelease ? "prerelease" : "stable release"} failed verification.`);
    }
    if (rawReleases.some((release) => !release.draft) && !result.manifest.releases.length) throw new Error("Published releases exist, but none passed VersionDeck verification.");
  } else {
    result = await buildManifest([], { control, generatorCommit });
  }
  const diagnosticsDirectory = path.join(root, ".versiondeck-diagnostics");
  await fs.mkdir(diagnosticsDirectory, { recursive: true });
  await fs.writeFile(path.resolve(root, args.output || "download-site/releases.json"), `${JSON.stringify(result.manifest, null, 2)}\n`);
  await fs.writeFile(
    path.resolve(diagnosticsDirectory, args["diagnostics-output"] || "release-diagnostics.json"),
    `${JSON.stringify({ generatedAt: result.manifest.generatedAt, diagnostics: result.diagnostics }, null, 2)}\n`,
  );
  console.log(`Generated ${publicationMode === "disabled" ? "disabled " : ""}VersionDeck schema ${result.manifest.schemaVersion} with ${result.manifest.releases.length} verified release(s).`);
}

const invokedAsScript = process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedAsScript) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
