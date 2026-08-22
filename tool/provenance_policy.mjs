import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);

export const ANDROID_PROVENANCE_POLICY_VERSION = 1;
export const GITHUB_OIDC_ISSUER = "https://token.actions.githubusercontent.com";
export const SLSA_PROVENANCE_PREDICATE_TYPE = "https://slsa.dev/provenance/v1";

const COMMAND_TIMEOUT_MS = 2 * 60 * 1000;
const COMMIT_PATTERN = /^[a-f\d]{40}$/i;
const DIGIT_PATTERN = /^\d+$/;
const REPOSITORY_PATTERN = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA256_PATTERN = /^[a-f\d]{64}$/i;
const SOURCE_REF_PATTERN = /^refs\/heads\/[A-Za-z0-9._/-]+$/;

const ARTIFACT_POLICIES = Object.freeze({
  apk: Object.freeze({
    artifactType: "apk",
    workflowName: "Shorebird Android Release",
    workflowPath: ".github/workflows/shorebird-release-android.yml",
  }),
  aab: Object.freeze({
    artifactType: "aab",
    workflowName: "Shorebird Android Release",
    workflowPath: ".github/workflows/shorebird-release-android.yml",
  }),
});

function normalizeCommit(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return COMMIT_PATTERN.test(normalized) ? normalized : "";
}

function normalizeRepository(value) {
  const normalized = String(value || "").trim();
  return REPOSITORY_PATTERN.test(normalized) ? normalized : "";
}

function normalizeSha256(value) {
  const normalized = String(value || "")
    .trim()
    .replace(/^sha256:/i, "")
    .toLowerCase();
  return SHA256_PATTERN.test(normalized) ? normalized : "";
}

function normalizeSourceRef(value) {
  const normalized = String(value || "").trim();
  return SOURCE_REF_PATTERN.test(normalized) ? normalized : "";
}

function normalizeDigits(value) {
  const normalized = String(value || "").trim();
  return DIGIT_PATTERN.test(normalized) ? normalized : "";
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function assertString(value, label) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${label} is missing.`);
  }
  return value.trim();
}

function assertExact(actual, expected, label) {
  if (expected == null || expected === "") return;
  if (actual !== expected) {
    throw new Error(`${label} mismatch. Expected ${expected}, got ${actual || "<empty>"}.`);
  }
}

function assertUriPrefix(value, prefix, label) {
  if (typeof value !== "string" || !value.startsWith(prefix)) {
    throw new Error(`${label} is invalid.`);
  }
}

function parseInvocationUri(value, repository) {
  const match = String(value || "").match(
    new RegExp(`^https://github\\.com/${escapeForRegex(repository)}/actions/runs/(\\d+)/attempts/(\\d+)$`),
  );
  if (!match) {
    throw new Error("Run invocation URI is invalid.");
  }
  return { runId: match[1], runAttempt: match[2] };
}

function escapeForRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined) {
      throw new Error(
        "Expected --artifact-path, --workflow-context, --release-evidence, " +
          "--attestation-output, and --verification-output arguments.",
      );
    }
    values[key.slice(2)] = value;
  }
  return values;
}

async function runChecked(command, args, options = {}) {
  try {
    return await execFileAsync(command, args, {
      timeout: COMMAND_TIMEOUT_MS,
      maxBuffer: 8 * 1024 * 1024,
      windowsHide: true,
      ...options,
    });
  } catch (error) {
    const detail = String(error.stderr || error.stdout || error.message).slice(0, 2000);
    throw new Error(`${path.basename(command)} failed: ${detail}`);
  }
}

function repositoryUri(repository) {
  return `https://github.com/${repository}`;
}

export function buildAndroidProvenancePolicy({
  artifactType,
  repository,
  sourceDigest,
  sourceRef = "refs/heads/main",
  repositoryId = "",
  repositoryOwnerId = "",
  runId = "",
  runAttempt = "",
  runnerEnvironment = "github-hosted",
  workflowTrigger = "workflow_dispatch",
  sourceRepositoryVisibilityAtSigning = "public",
  artifactName = "",
  artifactSha256 = "",
} = {}) {
  const rail = ARTIFACT_POLICIES[artifactType];
  if (!rail) {
    throw new Error(`Unsupported artifact type ${artifactType}.`);
  }

  const normalizedRepository = normalizeRepository(repository);
  if (!normalizedRepository) {
    throw new Error("Repository must match owner/name.");
  }
  const normalizedSourceDigest = normalizeCommit(sourceDigest);
  if (!normalizedSourceDigest) {
    throw new Error("Source digest must be a full commit SHA.");
  }
  const normalizedSourceRef = normalizeSourceRef(sourceRef);
  if (!normalizedSourceRef) {
    throw new Error("Source ref must be a full refs/heads/* value.");
  }
  const normalizedRunId = runId ? normalizeDigits(runId) : "";
  const normalizedRunAttempt = runAttempt ? normalizeDigits(runAttempt) : "";
  if ((normalizedRunId && !normalizedRunAttempt) || (!normalizedRunId && normalizedRunAttempt)) {
    throw new Error("Run ID and run attempt must be provided together.");
  }

  const repoUri = repositoryUri(normalizedRepository);
  const certIdentity = `${repoUri}/${rail.workflowPath}@${normalizedSourceRef}`;
  const runInvocationUri = normalizedRunId
    ? `${repoUri}/actions/runs/${normalizedRunId}/attempts/${normalizedRunAttempt}`
    : "";

  return Object.freeze({
    policyVersion: ANDROID_PROVENANCE_POLICY_VERSION,
    artifactType: rail.artifactType,
    repository: normalizedRepository,
    repositoryUri: repoUri,
    repositoryId: normalizeDigits(repositoryId),
    repositoryOwnerId: normalizeDigits(repositoryOwnerId),
    sourceDigest: normalizedSourceDigest,
    sourceRef: normalizedSourceRef,
    predicateType: SLSA_PROVENANCE_PREDICATE_TYPE,
    workflowName: rail.workflowName,
    workflowPath: rail.workflowPath,
    certIdentity,
    signerWorkflow: `${normalizedRepository}/${rail.workflowPath}`,
    signerDigest: normalizedSourceDigest,
    workflowTrigger,
    runnerEnvironment,
    runInvocationUri,
    artifactName: String(artifactName || "").trim(),
    artifactSha256: normalizeSha256(artifactSha256),
    sourceRepositoryVisibilityAtSigning,
  });
}

export function buildGhAttestationVerifyArgs(policy, artifactPath, { formatJson = false } = {}) {
  const args = [
    "attestation",
    "verify",
    artifactPath,
    "--repo",
    policy.repository,
    "--predicate-type",
    policy.predicateType,
    "--source-digest",
    policy.sourceDigest,
    "--source-ref",
    policy.sourceRef,
    "--cert-identity",
    policy.certIdentity,
    "--signer-digest",
    policy.signerDigest,
    "--deny-self-hosted-runners",
  ];
  if (formatJson) args.push("--format", "json");
  return args;
}

export function formatGhAttestationVerifyCommand(
  policy,
  artifactReference,
  { formatJson = true } = {},
) {
  const lines = [
    `gh attestation verify ${artifactReference} \\`,
    `  --repo ${policy.repository} \\`,
    `  --predicate-type ${policy.predicateType} \\`,
    `  --source-digest ${policy.sourceDigest} \\`,
    `  --source-ref ${policy.sourceRef} \\`,
    `  --cert-identity ${policy.certIdentity} \\`,
    `  --signer-digest ${policy.signerDigest} \\`,
  ];
  if (formatJson) {
    lines.push("  --deny-self-hosted-runners \\", "  --format json");
  } else {
    lines.push("  --deny-self-hosted-runners");
  }
  return lines.join("\n");
}

function normalizeVerifiedAttestationRecord(record, policy) {
  if (!isPlainObject(record)) {
    throw new Error("Verified attestation entry is not an object.");
  }
  const verificationResult = record.verificationResult;
  if (!isPlainObject(verificationResult)) {
    throw new Error("Verification result is missing.");
  }

  const certificate = verificationResult.signature?.certificate;
  if (!isPlainObject(certificate)) {
    throw new Error("Verification certificate is missing.");
  }

  assertExact(certificate.issuer, GITHUB_OIDC_ISSUER, "OIDC issuer");
  assertExact(certificate.subjectAlternativeName, policy.certIdentity, "Certificate identity");
  assertExact(certificate.buildSignerURI, policy.certIdentity, "Build signer URI");
  assertExact(certificate.buildConfigURI, policy.certIdentity, "Build config URI");
  assertExact(certificate.githubWorkflowRepository, policy.repository, "Workflow repository");
  assertExact(certificate.sourceRepositoryURI, policy.repositoryUri, "Source repository URI");
  assertExact(certificate.sourceRepositoryDigest, policy.sourceDigest, "Source repository digest");
  assertExact(certificate.githubWorkflowSHA, policy.sourceDigest, "Workflow SHA");
  assertExact(certificate.buildSignerDigest, policy.signerDigest, "Signer digest");
  assertExact(certificate.buildConfigDigest, policy.signerDigest, "Build config digest");
  assertExact(certificate.sourceRepositoryRef, policy.sourceRef, "Source repository ref");
  assertExact(certificate.githubWorkflowRef, policy.sourceRef, "Workflow ref");
  assertExact(certificate.githubWorkflowTrigger, policy.workflowTrigger, "Workflow trigger");
  assertExact(certificate.buildTrigger, policy.workflowTrigger, "Build trigger");
  assertExact(certificate.githubWorkflowName, policy.workflowName, "Workflow name");
  assertExact(certificate.runnerEnvironment, policy.runnerEnvironment, "Runner environment");
  assertExact(
    certificate.sourceRepositoryVisibilityAtSigning,
    policy.sourceRepositoryVisibilityAtSigning,
    "Source visibility at signing",
  );
  if (policy.repositoryId) {
    assertExact(
      certificate.sourceRepositoryIdentifier,
      policy.repositoryId,
      "Source repository identifier",
    );
  }
  if (policy.repositoryOwnerId) {
    assertExact(
      certificate.sourceRepositoryOwnerIdentifier,
      policy.repositoryOwnerId,
      "Source repository owner identifier",
    );
  }

  const invocation = parseInvocationUri(certificate.runInvocationURI, policy.repository);
  if (policy.runInvocationUri) {
    assertExact(certificate.runInvocationURI, policy.runInvocationUri, "Run invocation URI");
  }

  const verifiedTimestamps = verificationResult.verifiedTimestamps;
  if (!Array.isArray(verifiedTimestamps) || verifiedTimestamps.length === 0) {
    throw new Error("Verified attestation timestamps are missing.");
  }
  const verifiedTimestamp = assertString(
    verifiedTimestamps[0]?.timestamp,
    "Verified attestation timestamp",
  );

  const statement = verificationResult.statement;
  if (!isPlainObject(statement)) {
    throw new Error("Provenance statement is missing.");
  }
  assertExact(statement.predicateType, policy.predicateType, "Predicate type");

  if (!Array.isArray(statement.subject) || statement.subject.length !== 1) {
    throw new Error("Expected exactly one attested subject.");
  }
  const subject = statement.subject[0];
  const subjectName = assertString(subject?.name, "Attested subject name");
  const subjectSha256 = normalizeSha256(subject?.digest?.sha256);
  if (!subjectSha256) {
    throw new Error("Attested subject SHA-256 is missing.");
  }
  assertExact(subjectName, policy.artifactName, "Attested subject name");
  assertExact(subjectSha256, policy.artifactSha256, "Attested subject SHA-256");

  const predicate = statement.predicate;
  if (!isPlainObject(predicate)) {
    throw new Error("Provenance predicate is missing.");
  }
  const buildDefinition = predicate.buildDefinition;
  if (!isPlainObject(buildDefinition)) {
    throw new Error("Provenance build definition is missing.");
  }
  const workflow = buildDefinition.externalParameters?.workflow;
  if (!isPlainObject(workflow)) {
    throw new Error("Provenance workflow parameters are missing.");
  }
  assertExact(workflow.path, policy.workflowPath, "Workflow path");
  assertExact(workflow.ref, policy.sourceRef, "Workflow ref in predicate");
  assertExact(workflow.repository, policy.repositoryUri, "Workflow repository URI");

  const github = buildDefinition.internalParameters?.github;
  if (!isPlainObject(github)) {
    throw new Error("GitHub internal provenance parameters are missing.");
  }
  assertExact(github.event_name, policy.workflowTrigger, "Predicate event name");
  assertExact(github.runner_environment, policy.runnerEnvironment, "Predicate runner environment");
  if (policy.repositoryId) {
    assertExact(github.repository_id, policy.repositoryId, "Predicate repository identifier");
  }
  if (policy.repositoryOwnerId) {
    assertExact(
      github.repository_owner_id,
      policy.repositoryOwnerId,
      "Predicate repository owner identifier",
    );
  }

  const expectedDependencyUri = `git+${policy.repositoryUri}@${policy.sourceRef}`;
  const dependencies = Array.isArray(buildDefinition.resolvedDependencies)
    ? buildDefinition.resolvedDependencies
    : [];
  const dependency = dependencies.find((item) =>
    isPlainObject(item) && item.uri === expectedDependencyUri);
  if (!dependency) {
    throw new Error("Exact source dependency was not recorded in the provenance predicate.");
  }
  assertExact(
    dependency.digest?.gitCommit,
    policy.sourceDigest,
    "Source dependency git commit",
  );

  const builderId = predicate.runDetails?.builder?.id;
  assertExact(builderId, policy.certIdentity, "Builder identity");
  const invocationId = predicate.runDetails?.metadata?.invocationId;
  if (policy.runInvocationUri) {
    assertExact(invocationId, policy.runInvocationUri, "Predicate invocation ID");
  } else {
    parseInvocationUri(assertString(invocationId, "Predicate invocation ID"), policy.repository);
  }

  return {
    policyVersion: policy.policyVersion,
    predicateType: policy.predicateType,
    repository: policy.repository,
    sourceRepositoryUri: policy.repositoryUri,
    sourceRepositoryDigest: policy.sourceDigest,
    sourceRepositoryRef: policy.sourceRef,
    sourceRepositoryIdentifier: certificate.sourceRepositoryIdentifier || "",
    sourceRepositoryOwnerUri: certificate.sourceRepositoryOwnerURI || "",
    sourceRepositoryOwnerIdentifier: certificate.sourceRepositoryOwnerIdentifier || "",
    signerWorkflow: policy.certIdentity,
    signerDigest: policy.signerDigest,
    workflowName: policy.workflowName,
    workflowTrigger: policy.workflowTrigger,
    runnerEnvironment: policy.runnerEnvironment,
    runInvocationUri: certificate.runInvocationURI,
    runId: invocation.runId,
    runAttempt: invocation.runAttempt,
    buildConfigUri: certificate.buildConfigURI,
    buildConfigDigest: certificate.buildConfigDigest,
    certificateIssuer: certificate.certificateIssuer || "",
    oidcIssuer: certificate.issuer,
    sourceRepositoryVisibilityAtSigning: certificate.sourceRepositoryVisibilityAtSigning || "",
    subjectName,
    artifactSha256: subjectSha256,
    verifiedTimestamp,
  };
}

export function verifyAttestationVerificationJson(jsonText, policy) {
  let entries;
  try {
    entries = JSON.parse(jsonText);
  } catch (error) {
    throw new Error(`Attestation JSON could not be parsed: ${error.message}`);
  }
  if (!Array.isArray(entries)) {
    throw new Error("Attestation verification output must be a JSON array.");
  }
  if (entries.length !== 1) {
    throw new Error(`Expected exactly one verified attestation, found ${entries.length}.`);
  }
  return normalizeVerifiedAttestationRecord(entries[0], policy);
}

async function verifyForWorkflow({
  artifactPath,
  workflowContextPath,
  releaseEvidencePath,
  attestationOutputPath,
  verificationOutputPath,
}) {
  const workflowContext = JSON.parse(await fs.readFile(workflowContextPath, "utf8"));
  const releaseEvidence = JSON.parse(await fs.readFile(releaseEvidencePath, "utf8"));
  if (!isPlainObject(workflowContext)) {
    throw new Error("Workflow context is invalid.");
  }
  if (!isPlainObject(releaseEvidence)) {
    throw new Error("Release evidence summary is invalid.");
  }

  const policy = buildAndroidProvenancePolicy({
    artifactType: assertString(workflowContext.artifact_type, "Workflow context artifact type"),
    repository: assertString(workflowContext.repository, "Workflow context repository"),
    repositoryId: workflowContext.repository_id || "",
    repositoryOwnerId: workflowContext.repository_owner_id || "",
    sourceDigest: assertString(workflowContext.source_sha, "Workflow context source SHA"),
    sourceRef: assertString(workflowContext.source_ref, "Workflow context source ref"),
    runId: assertString(workflowContext.run_id, "Workflow context run ID"),
    runAttempt: assertString(workflowContext.run_attempt, "Workflow context run attempt"),
    runnerEnvironment: assertString(
      workflowContext.runner_environment,
      "Workflow context runner environment",
    ),
    workflowTrigger: assertString(
      workflowContext.event_name,
      "Workflow context event name",
    ),
    sourceRepositoryVisibilityAtSigning: assertString(
      workflowContext.source_repository_visibility,
      "Workflow context source repository visibility",
    ),
    artifactName: assertString(releaseEvidence.artifact_file, "Release evidence artifact file"),
    artifactSha256: assertString(
      releaseEvidence.artifact_sha256,
      "Release evidence artifact SHA-256",
    ),
  });

  const { stdout } = await runChecked("gh", buildGhAttestationVerifyArgs(policy, artifactPath, {
    formatJson: true,
  }), {
    env: { ...process.env, GH_TOKEN: process.env.GH_TOKEN || process.env.GITHUB_TOKEN || "" },
  });

  const normalized = verifyAttestationVerificationJson(stdout, policy);
  await fs.writeFile(attestationOutputPath, `${stdout.trim()}\n`);
  await fs.writeFile(verificationOutputPath, `${JSON.stringify(normalized, null, 2)}\n`);
  return normalized;
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const artifactPath = path.resolve(assertString(args["artifact-path"], "Artifact path"));
  const workflowContextPath = path.resolve(
    assertString(args["workflow-context"], "Workflow context path"),
  );
  const releaseEvidencePath = path.resolve(
    assertString(args["release-evidence"], "Release evidence path"),
  );
  const attestationOutputPath = path.resolve(
    assertString(args["attestation-output"], "Attestation output path"),
  );
  const verificationOutputPath = path.resolve(
    assertString(args["verification-output"], "Verification output path"),
  );

  const normalized = await verifyForWorkflow({
    artifactPath,
    workflowContextPath,
    releaseEvidencePath,
    attestationOutputPath,
    verificationOutputPath,
  });
  process.stdout.write(
    `Verified ${normalized.subjectName} provenance tuple for ` +
      `${normalized.sourceRepositoryDigest} via ${normalized.runInvocationUri}.\n`,
  );
}

const invokedAsScript = process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedAsScript) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
