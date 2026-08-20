import crypto from 'node:crypto';
import fs from 'node:fs';
import fsPromises from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);

export const ANDROID_APK_ARTIFACT_SET_SCHEMA_VERSION = 1;
export const EXPECTED_ANDROID_APK_ABIS = Object.freeze([
  'arm64-v8a',
  'armeabi-v7a',
  'x86_64',
]);
export const EXPECTED_ANDROID_PACKAGE = 'app.owntend.mobile';
export const EXPECTED_ANDROID_SIGNER_SHA256 =
  '3E:98:0E:B5:BB:68:A5:19:90:E7:70:56:D4:E1:09:95:B2:E0:4F:B3:88:A7:34:42:B7:9A:46:C8:53:36:1E:51';
export const EXPECTED_PROVENANCE_WORKFLOW =
  'https://github.com/zuhak5/Owntend/.github/workflows/build-production-android.yml@refs/heads/main';

const EXPECTED_REPOSITORY = 'zuhak5/Owntend';
const EXPECTED_PREDICATE_TYPE = 'https://slsa.dev/provenance/v1';
const EXPECTED_OIDC_ISSUER = 'https://token.actions.githubusercontent.com';
const COMMIT_PATTERN = /^[a-f\d]{40}$/iu;
const SHA256_PATTERN = /^[a-f\d]{64}$/iu;
const VERSION_PATTERN = /^\d+\.\d+\.\d+$/u;
const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_DIRECTORY_SIGNATURE = 0x02014b50;
const MAX_EOCD_SEARCH = 0xffff + 22;
const COMMAND_TIMEOUT_MS = 2 * 60 * 1000;

function isPlainObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function normalizedSha(value) {
  const normalized = String(value || '')
    .replace(/^sha256:/iu, '')
    .trim()
    .toLowerCase();
  return SHA256_PATTERN.test(normalized) ? normalized : '';
}

function normalizedSigner(value) {
  const normalized = String(value || '').replace(/[^a-f\d]/giu, '').toUpperCase();
  return normalized.length === 64 ? normalized.match(/.{2}/gu).join(':') : '';
}

function arraysEqual(left, right) {
  return Array.isArray(left) &&
    Array.isArray(right) &&
    left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function expectedApkName(versionName, versionCode, abi) {
  return `Owntend-${versionName}-build-${versionCode}-${abi}.apk`;
}

function expectedSymbolName(abi) {
  return {
    'arm64-v8a': 'app.android-arm64.symbols',
    'armeabi-v7a': 'app.android-arm.symbols',
    x86_64: 'app.android-x64.symbols',
  }[abi];
}

export function validateAbiEvidenceIndex(
  index,
  { sourceSha = '', versionName = '', versionCode = '' } = {},
) {
  const errors = [];
  if (!isPlainObject(index)) return ['ABI evidence index is not an object.'];

  if (index.schema_version !== 1) errors.push('ABI evidence schema version is invalid.');
  if (index.evidence_mode !== 'protected-abi-apk-evidence') {
    errors.push('ABI evidence mode is invalid.');
  }
  if (!COMMIT_PATTERN.test(String(index.source_sha || ''))) {
    errors.push('ABI evidence source SHA is invalid.');
  }
  if (sourceSha && String(index.source_sha).toLowerCase() !== String(sourceSha).toLowerCase()) {
    errors.push('ABI evidence source SHA does not match the requested source.');
  }
  if (!VERSION_PATTERN.test(String(index.version_name || ''))) {
    errors.push('ABI evidence version name is invalid.');
  }
  if (versionName && String(index.version_name) !== String(versionName)) {
    errors.push('ABI evidence version name does not match the requested version.');
  }
  const normalizedVersionCode = String(index.version_code ?? '');
  if (!/^\d+$/u.test(normalizedVersionCode) || Number(normalizedVersionCode) < 1) {
    errors.push('ABI evidence version code is invalid.');
  }
  if (versionCode && normalizedVersionCode !== String(versionCode)) {
    errors.push('ABI evidence version code does not match the requested build.');
  }
  if (index.package !== EXPECTED_ANDROID_PACKAGE) {
    errors.push('ABI evidence package is invalid.');
  }
  if (normalizedSigner(index.expected_signer_sha256) !== EXPECTED_ANDROID_SIGNER_SHA256) {
    errors.push('ABI evidence signer policy is invalid.');
  }
  if (!arraysEqual(index.expected_abis, EXPECTED_ANDROID_APK_ABIS)) {
    errors.push('ABI evidence expected ABI set is invalid.');
  }
  if (index.universal_apk_remains_authoritative !== true) {
    errors.push('ABI evidence must keep the universal APK authoritative during P1-C.');
  }
  if (index.public_distribution_authorized !== false) {
    errors.push('ABI evidence must not authorize public split-APK distribution during P1-C.');
  }
  if (index.versiondeck_publication_authorized !== false) {
    errors.push('ABI evidence must not authorize VersionDeck split publication during P1-C.');
  }

  const records = Array.isArray(index.artifacts) ? index.artifacts : [];
  if (records.length !== EXPECTED_ANDROID_APK_ABIS.length) {
    errors.push(
      `ABI evidence must contain exactly ${EXPECTED_ANDROID_APK_ABIS.length} artifact records.`,
    );
  }

  const seenAbis = new Set();
  const seenFiles = new Set();
  const seenHashes = new Set();
  for (const record of records) {
    if (!isPlainObject(record)) {
      errors.push('ABI artifact record is not an object.');
      continue;
    }
    const abi = String(record.abi || '');
    if (!EXPECTED_ANDROID_APK_ABIS.includes(abi)) {
      errors.push(`Unexpected ABI artifact record: ${abi || '<empty>'}.`);
      continue;
    }
    if (seenAbis.has(abi)) errors.push(`Duplicate ABI artifact record: ${abi}.`);
    seenAbis.add(abi);

    const apkName = expectedApkName(index.version_name, index.version_code, abi);
    const expectedFile = `artifacts/${apkName}`;
    const expectedChecksum = `${expectedFile}.sha256`;
    const expectedBadging = `metadata/apk-badging-${abi}.txt`;
    const expectedSignature = `metadata/apk-signature-${abi}.txt`;
    const expectedSizeReport = `metadata/apk-size-report-${abi}.json`;
    const expectedSymbols = `symbols/${expectedSymbolName(abi)}`;

    if (record.file !== expectedFile) errors.push(`ABI ${abi} APK file identity is invalid.`);
    if (record.checksum_file !== expectedChecksum) {
      errors.push(`ABI ${abi} checksum file identity is invalid.`);
    }
    if (record.badging_file !== expectedBadging) {
      errors.push(`ABI ${abi} badging evidence identity is invalid.`);
    }
    if (record.signature_file !== expectedSignature) {
      errors.push(`ABI ${abi} signature evidence identity is invalid.`);
    }
    if (record.size_report_file !== expectedSizeReport) {
      errors.push(`ABI ${abi} size-report identity is invalid.`);
    }
    if (record.dart_symbols_file !== expectedSymbols) {
      errors.push(`ABI ${abi} Dart symbols identity is invalid.`);
    }

    if (seenFiles.has(record.file)) errors.push(`Duplicate ABI artifact file: ${record.file}.`);
    seenFiles.add(record.file);

    const sha256 = normalizedSha(record.sha256);
    if (!sha256) errors.push(`ABI ${abi} SHA-256 is invalid.`);
    if (sha256 && seenHashes.has(sha256)) errors.push(`Duplicate ABI artifact SHA-256: ${sha256}.`);
    if (sha256) seenHashes.add(sha256);

    if (!Number.isInteger(Number(record.total_bytes)) || Number(record.total_bytes) < 1) {
      errors.push(`ABI ${abi} size is invalid.`);
    }
    if (record.package !== EXPECTED_ANDROID_PACKAGE) errors.push(`ABI ${abi} package is invalid.`);
    if (String(record.version_name) !== String(index.version_name)) {
      errors.push(`ABI ${abi} versionName does not match the artifact set.`);
    }
    if (String(record.version_code) !== String(index.version_code)) {
      errors.push(`ABI ${abi} versionCode does not match the artifact set.`);
    }
    if (normalizedSigner(record.signer_sha256) !== EXPECTED_ANDROID_SIGNER_SHA256) {
      errors.push(`ABI ${abi} signer does not match production policy.`);
    }
    if (!arraysEqual(record.native_abis, [abi])) {
      errors.push(`ABI ${abi} native ABI declaration is invalid.`);
    }
  }

  for (const abi of EXPECTED_ANDROID_APK_ABIS) {
    if (!seenAbis.has(abi)) errors.push(`Missing ABI artifact record: ${abi}.`);
  }
  if (index.r8_mapping_file !== 'symbols/mapping.txt') {
    errors.push('ABI evidence R8 mapping identity is invalid.');
  }
  if (index.dart_obfuscation_map_file !== 'symbols/obfuscation-map.json') {
    errors.push('ABI evidence Dart obfuscation map identity is invalid.');
  }
  if (
    index.output_metadata_file != null &&
    index.output_metadata_file !== 'metadata/output-metadata-apk.json'
  ) {
    errors.push('ABI evidence output metadata identity is invalid.');
  }
  return errors;
}

function parseArguments(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) {
      throw new Error('Arguments must use --name value pairs.');
    }
    result[key.slice(2)] = value;
  }
  return result;
}

async function commandExists(command) {
  try {
    const { stdout } = await execFileAsync(process.platform === 'win32' ? 'where' : 'which', [command], {
      timeout: 15_000,
      windowsHide: true,
    });
    return stdout.split(/\r?\n/u).map((item) => item.trim()).find(Boolean) || '';
  } catch {
    return '';
  }
}

async function findAndroidTool(name) {
  const override = process.env[`${name.toUpperCase()}_PATH`];
  if (override) return override;
  const direct = await commandExists(name);
  if (direct) return direct;
  const androidHome = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT;
  if (!androidHome) throw new Error(`${name} was not found and ANDROID_HOME is unavailable.`);
  const buildToolsRoot = path.join(androidHome, 'build-tools');
  const versions = (await fsPromises.readdir(buildToolsRoot, { withFileTypes: true }))
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort((left, right) => right.localeCompare(left, undefined, { numeric: true }));
  for (const version of versions) {
    const suffix = process.platform === 'win32' ? (name === 'apksigner' ? '.bat' : '.exe') : '';
    const candidate = path.join(buildToolsRoot, version, `${name}${suffix}`);
    try {
      await fsPromises.access(candidate);
      return candidate;
    } catch {}
  }
  throw new Error(`${name} was not found in Android build tools.`);
}

async function runChecked(command, args, options = {}) {
  try {
    return await execFileAsync(command, args, {
      timeout: COMMAND_TIMEOUT_MS,
      maxBuffer: 16 * 1024 * 1024,
      windowsHide: true,
      ...options,
    });
  } catch (error) {
    const detail = String(error.stderr || error.stdout || error.message).slice(0, 4000);
    throw new Error(`${path.basename(command)} failed: ${detail}`);
  }
}

async function sha256File(filePath) {
  const hash = crypto.createHash('sha256');
  const stream = fs.createReadStream(filePath);
  for await (const chunk of stream) hash.update(chunk);
  return hash.digest('hex');
}

function findEndOfCentralDirectory(buffer) {
  const lowerBound = Math.max(0, buffer.length - MAX_EOCD_SEARCH);
  for (let offset = buffer.length - 22; offset >= lowerBound; offset -= 1) {
    if (buffer.readUInt32LE(offset) !== EOCD_SIGNATURE) continue;
    const commentLength = buffer.readUInt16LE(offset + 20);
    if (offset + 22 + commentLength === buffer.length) return offset;
  }
  throw new Error('APK ZIP end-of-central-directory record was not found.');
}

export function readApkNativeAbis(buffer) {
  const eocdOffset = findEndOfCentralDirectory(buffer);
  const diskNumber = buffer.readUInt16LE(eocdOffset + 4);
  const centralDirectoryDisk = buffer.readUInt16LE(eocdOffset + 6);
  const entriesOnDisk = buffer.readUInt16LE(eocdOffset + 8);
  const totalEntries = buffer.readUInt16LE(eocdOffset + 10);
  const centralDirectorySize = buffer.readUInt32LE(eocdOffset + 12);
  const centralDirectoryOffset = buffer.readUInt32LE(eocdOffset + 16);
  if (diskNumber !== 0 || centralDirectoryDisk !== 0 || entriesOnDisk !== totalEntries) {
    throw new Error('Multi-disk APK ZIPs are not supported.');
  }
  if (
    totalEntries === 0xffff ||
    centralDirectorySize === 0xffffffff ||
    centralDirectoryOffset === 0xffffffff
  ) {
    throw new Error('ZIP64 APKs are not supported.');
  }
  if (centralDirectoryOffset + centralDirectorySize > eocdOffset) {
    throw new Error('APK central-directory bounds are invalid.');
  }

  const abis = new Set();
  let offset = centralDirectoryOffset;
  for (let index = 0; index < totalEntries; index += 1) {
    if (offset + 46 > buffer.length || buffer.readUInt32LE(offset) !== CENTRAL_DIRECTORY_SIGNATURE) {
      throw new Error(`Invalid APK central-directory entry at index ${index}.`);
    }
    const fileNameLength = buffer.readUInt16LE(offset + 28);
    const extraLength = buffer.readUInt16LE(offset + 30);
    const commentLength = buffer.readUInt16LE(offset + 32);
    const nameStart = offset + 46;
    const nameEnd = nameStart + fileNameLength;
    const nextOffset = nameEnd + extraLength + commentLength;
    if (nextOffset > buffer.length) throw new Error('APK central-directory entry is truncated.');
    const entryName = buffer.subarray(nameStart, nameEnd).toString('utf8');
    const match = entryName.match(/^lib\/([^/]+)\//u);
    if (match) abis.add(match[1]);
    offset = nextOffset;
  }
  return [...abis].sort();
}

function parseBadging(text, abi) {
  const match = String(text).match(
    /package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'/u,
  );
  if (!match) throw new Error(`APK package metadata could not be parsed for ${abi}.`);
  if (/^application-debuggable/mu.test(text)) {
    throw new Error(`Production ABI APK is debuggable: ${abi}.`);
  }
  return { packageName: match[1], versionCode: match[2], versionName: match[3] };
}

function parseSigner(text, abi) {
  const match = String(text).match(
    /(?:Signer #\d+|V\d+(?:\.\d+)? Signer:)\s+certificate SHA-256 digest:\s*([0-9A-Fa-f:]+)/u,
  );
  if (!match) throw new Error(`APK signer SHA-256 could not be parsed for ${abi}.`);
  return normalizedSigner(match[1]);
}

export function normalizeVerifiedProvenance(jsonText, { sourceSha, artifactName, artifactSha256 }) {
  let records;
  try {
    records = JSON.parse(jsonText);
  } catch (error) {
    throw new Error(`Attestation JSON could not be parsed: ${error.message}`);
  }
  if (!Array.isArray(records) || records.length !== 1) {
    throw new Error(`Expected exactly one verified attestation, found ${Array.isArray(records) ? records.length : 0}.`);
  }
  const verification = records[0]?.verificationResult;
  if (!isPlainObject(verification)) throw new Error('Attestation verification result is missing.');
  const certificate = verification.signature?.certificate;
  if (!isPlainObject(certificate)) throw new Error('Attestation certificate is missing.');

  const expected = {
    issuer: EXPECTED_OIDC_ISSUER,
    subjectAlternativeName: EXPECTED_PROVENANCE_WORKFLOW,
    buildSignerURI: EXPECTED_PROVENANCE_WORKFLOW,
    buildConfigURI: EXPECTED_PROVENANCE_WORKFLOW,
    githubWorkflowRepository: EXPECTED_REPOSITORY,
    sourceRepositoryURI: `https://github.com/${EXPECTED_REPOSITORY}`,
    sourceRepositoryDigest: sourceSha,
    githubWorkflowSHA: sourceSha,
    buildSignerDigest: sourceSha,
    buildConfigDigest: sourceSha,
    sourceRepositoryRef: 'refs/heads/main',
    githubWorkflowRef: 'refs/heads/main',
    githubWorkflowTrigger: 'workflow_dispatch',
    buildTrigger: 'workflow_dispatch',
    githubWorkflowName: 'Build Production APK',
    runnerEnvironment: 'github-hosted',
    sourceRepositoryVisibilityAtSigning: 'public',
  };
  for (const [key, value] of Object.entries(expected)) {
    if (certificate[key] !== value) throw new Error(`Attestation certificate ${key} is invalid.`);
  }

  const statement = verification.statement;
  if (!isPlainObject(statement) || statement.predicateType !== EXPECTED_PREDICATE_TYPE) {
    throw new Error('Attestation predicate type is invalid.');
  }
  const subjects = Array.isArray(statement.subject) ? statement.subject : [];
  if (subjects.length !== 1) throw new Error('Expected exactly one attested subject.');
  if (subjects[0]?.name !== artifactName) throw new Error('Attested subject name is invalid.');
  if (normalizedSha(subjects[0]?.digest?.sha256) !== normalizedSha(artifactSha256)) {
    throw new Error('Attested subject SHA-256 is invalid.');
  }

  const buildDefinition = statement.predicate?.buildDefinition;
  const workflow = buildDefinition?.externalParameters?.workflow;
  if (
    workflow?.path !== '.github/workflows/build-production-android.yml' ||
    workflow?.ref !== 'refs/heads/main' ||
    workflow?.repository !== `https://github.com/${EXPECTED_REPOSITORY}`
  ) {
    throw new Error('Attestation workflow definition is invalid.');
  }
  const github = buildDefinition?.internalParameters?.github;
  if (github?.event_name !== 'workflow_dispatch' || github?.runner_environment !== 'github-hosted') {
    throw new Error('Attestation GitHub build parameters are invalid.');
  }
  const dependency = (buildDefinition?.resolvedDependencies || []).find(
    (item) => item?.uri === `git+https://github.com/${EXPECTED_REPOSITORY}@refs/heads/main`,
  );
  if (dependency?.digest?.gitCommit !== sourceSha) {
    throw new Error('Attestation source dependency is invalid.');
  }
  if (statement.predicate?.runDetails?.builder?.id !== EXPECTED_PROVENANCE_WORKFLOW) {
    throw new Error('Attestation builder identity is invalid.');
  }
  const runInvocationUri = certificate.runInvocationURI;
  const runMatch = String(runInvocationUri || '').match(
    /^https:\/\/github\.com\/zuhak5\/Owntend\/actions\/runs\/(\d+)\/attempts\/(\d+)$/u,
  );
  if (!runMatch) throw new Error('Attestation run invocation URI is invalid.');
  if (statement.predicate?.runDetails?.metadata?.invocationId !== runInvocationUri) {
    throw new Error('Attestation invocation IDs disagree.');
  }
  const verifiedTimestamp = verification.verifiedTimestamps?.[0]?.timestamp;
  if (!Number.isFinite(Date.parse(verifiedTimestamp))) {
    throw new Error('Attestation verified timestamp is invalid.');
  }

  return {
    policyVersion: 1,
    predicateType: EXPECTED_PREDICATE_TYPE,
    repository: EXPECTED_REPOSITORY,
    sourceRepositoryUri: `https://github.com/${EXPECTED_REPOSITORY}`,
    sourceRepositoryDigest: sourceSha,
    sourceRepositoryRef: 'refs/heads/main',
    subjectName: artifactName,
    artifactSha256: normalizedSha(artifactSha256),
    signerWorkflow: EXPECTED_PROVENANCE_WORKFLOW,
    signerDigest: sourceSha,
    workflowName: 'Build Production APK',
    workflowTrigger: 'workflow_dispatch',
    runnerEnvironment: 'github-hosted',
    runInvocationUri,
    runId: runMatch[1],
    runAttempt: runMatch[2],
    oidcIssuer: EXPECTED_OIDC_ISSUER,
    verifiedTimestamp,
  };
}

async function verifyVariant({ root, record, index, aapt2, apksigner }) {
  const abi = record.abi;
  const apkPath = path.join(root, ...record.file.split('/'));
  const checksumPath = path.join(root, ...record.checksum_file.split('/'));
  const sizeReportPath = path.join(root, ...record.size_report_file.split('/'));
  const stat = await fsPromises.stat(apkPath);
  if (!stat.isFile()) throw new Error(`ABI APK is missing: ${record.file}.`);
  const sha256 = await sha256File(apkPath);
  if (sha256 !== normalizedSha(record.sha256)) throw new Error(`ABI ${abi} APK SHA-256 mismatch.`);
  if (stat.size !== Number(record.total_bytes)) throw new Error(`ABI ${abi} APK size mismatch.`);

  const checksumLine = (await fsPromises.readFile(checksumPath, 'utf8')).replace(/^\uFEFF/u, '').trim();
  const expectedChecksum = `${sha256}  ${path.basename(apkPath)}`;
  if (checksumLine !== expectedChecksum) throw new Error(`ABI ${abi} checksum contents mismatch.`);

  const signature = await runChecked(apksigner, ['verify', '--verbose', '--print-certs', apkPath]);
  const signer = parseSigner(`${signature.stdout}\n${signature.stderr}`, abi);
  if (signer !== EXPECTED_ANDROID_SIGNER_SHA256) throw new Error(`ABI ${abi} signer is invalid.`);

  const badging = await runChecked(aapt2, ['dump', 'badging', apkPath]);
  const metadata = parseBadging(`${badging.stdout}\n${badging.stderr}`, abi);
  if (metadata.packageName !== EXPECTED_ANDROID_PACKAGE) throw new Error(`ABI ${abi} package is invalid.`);
  if (metadata.versionName !== String(index.version_name)) throw new Error(`ABI ${abi} versionName is invalid.`);
  if (metadata.versionCode !== String(index.version_code)) throw new Error(`ABI ${abi} versionCode is invalid.`);

  const apkBuffer = await fsPromises.readFile(apkPath);
  const nativeAbis = readApkNativeAbis(apkBuffer);
  if (!arraysEqual(nativeAbis, [abi])) {
    throw new Error(`ABI ${abi} APK contains unexpected native ABIs: ${nativeAbis.join(', ') || '<none>'}.`);
  }

  const sizeReport = JSON.parse(await fsPromises.readFile(sizeReportPath, 'utf8'));
  if (String(sizeReport.sourceSha).toLowerCase() !== String(index.source_sha).toLowerCase()) {
    throw new Error(`ABI ${abi} size report source SHA mismatch.`);
  }
  if (sizeReport.artifactSha256 !== sha256) throw new Error(`ABI ${abi} size report hash mismatch.`);
  if (Number(sizeReport.totalBytes) !== stat.size) throw new Error(`ABI ${abi} size report size mismatch.`);
  if (String(sizeReport.versionName) !== String(index.version_name)) {
    throw new Error(`ABI ${abi} size report versionName mismatch.`);
  }
  if (String(sizeReport.versionCode) !== String(index.version_code)) {
    throw new Error(`ABI ${abi} size report versionCode mismatch.`);
  }
  if (String(sizeReport.abi) !== abi) throw new Error(`ABI ${abi} size report ABI mismatch.`);
  const reportAbis = Object.keys(sizeReport.components?.lib?.byAbi || {}).sort();
  if (!arraysEqual(reportAbis, [abi])) throw new Error(`ABI ${abi} size report native ABI set is invalid.`);

  const provenanceArgs = [
    'attestation',
    'verify',
    apkPath,
    '--repo', EXPECTED_REPOSITORY,
    '--predicate-type', EXPECTED_PREDICATE_TYPE,
    '--source-digest', index.source_sha,
    '--source-ref', 'refs/heads/main',
    '--cert-identity', EXPECTED_PROVENANCE_WORKFLOW,
    '--signer-digest', index.source_sha,
    '--deny-self-hosted-runners',
    '--format', 'json',
  ];
  const { stdout: provenanceJson } = await runChecked('gh', provenanceArgs, {
    env: { ...process.env, GH_TOKEN: process.env.GH_TOKEN || process.env.GITHUB_TOKEN || '' },
  });
  const provenance = normalizeVerifiedProvenance(provenanceJson, {
    sourceSha: index.source_sha,
    artifactName: path.basename(apkPath),
    artifactSha256: sha256,
  });

  return {
    abi,
    file: record.file,
    checksumFile: record.checksum_file,
    sha256,
    totalBytes: stat.size,
    package: metadata.packageName,
    versionName: metadata.versionName,
    versionCode: Number(metadata.versionCode),
    signerCertificateSha256: signer,
    nativeAbis,
    sizeReportFile: record.size_report_file,
    dartSymbolsFile: record.dart_symbols_file,
    provenance,
  };
}

async function verifyArtifactSet({ root, sourceSha, versionName, versionCode }) {
  const indexPath = path.join(root, 'abi-evidence-index.json');
  const index = JSON.parse(await fsPromises.readFile(indexPath, 'utf8'));
  const errors = validateAbiEvidenceIndex(index, { sourceSha, versionName, versionCode });
  if (errors.length) throw new Error(`ABI evidence index is invalid: ${errors.join(' ')}`);

  const aapt2 = await findAndroidTool('aapt2');
  const apksigner = await findAndroidTool('apksigner');
  const variants = [];
  for (const abi of EXPECTED_ANDROID_APK_ABIS) {
    const record = index.artifacts.find((item) => item.abi === abi);
    variants.push(await verifyVariant({ root, record, index, aapt2, apksigner }));
  }
  return {
    schemaVersion: ANDROID_APK_ARTIFACT_SET_SCHEMA_VERSION,
    verificationScope: 'artifact-metadata-signing-abi-checksum-size-provenance',
    sourceSha: String(index.source_sha).toLowerCase(),
    versionName: index.version_name,
    versionCode: Number(index.version_code),
    package: EXPECTED_ANDROID_PACKAGE,
    signerCertificateSha256: EXPECTED_ANDROID_SIGNER_SHA256,
    expectedAbis: EXPECTED_ANDROID_APK_ABIS,
    universalApkRemainsAuthoritative: true,
    publicDistributionAuthorized: false,
    versionDeckPublicationAuthorized: false,
    variants,
    allArtifactsVerified: true,
  };
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const root = path.resolve(args.root || '');
  if (!args.root) throw new Error('--root is required.');
  if (!COMMIT_PATTERN.test(args['source-sha'] || '')) throw new Error('--source-sha must be a full commit SHA.');
  if (!VERSION_PATTERN.test(args['version-name'] || '')) throw new Error('--version-name must use x.y.z.');
  if (!/^\d+$/u.test(args['version-code'] || '') || Number(args['version-code']) < 1) {
    throw new Error('--version-code must be a positive integer.');
  }
  if (!args.output) throw new Error('--output is required.');

  const report = await verifyArtifactSet({
    root,
    sourceSha: args['source-sha'],
    versionName: args['version-name'],
    versionCode: args['version-code'],
  });
  const output = path.resolve(args.output);
  await fsPromises.mkdir(path.dirname(output), { recursive: true });
  await fsPromises.writeFile(output, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  process.stdout.write(
    `Verified ABI APK artifact set for ${report.versionName} (${report.versionCode}): ` +
      `${report.expectedAbis.join(', ')}.\n`,
  );
}

const invokedAsScript = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedAsScript) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
