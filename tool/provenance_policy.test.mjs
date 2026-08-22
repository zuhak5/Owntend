import assert from "node:assert/strict";
import test from "node:test";

import {
  buildAndroidProvenancePolicy,
  formatGhAttestationVerifyCommand,
  verifyAttestationVerificationJson,
} from "./provenance_policy.mjs";

const ARTIFACT_SHA = "2dcb6b153230df5baa9ef6883e86572f01532b6b185b536ea71392cb8fd65caf";
const SOURCE_SHA = "6f5606925964c9794d0f1ba863ec954239a47c9b";

function policyFixture(overrides = {}) {
  return buildAndroidProvenancePolicy({
    artifactType: "apk",
    repository: "zuhak5/Owntend",
    repositoryId: "1319597440",
    repositoryOwnerId: "233116763",
    sourceDigest: SOURCE_SHA,
    sourceRef: "refs/heads/main",
    runId: "31329512924",
    runAttempt: "1",
    artifactName: "Owntend-1.5.0-build-44.apk",
    artifactSha256: ARTIFACT_SHA,
    ...overrides,
  });
}

function verificationEntry(policy, overrides = {}) {
  const record = {
    verificationResult: {
      signature: {
        certificate: {
          certificateIssuer: "CN=sigstore-intermediate,O=sigstore.dev",
          subjectAlternativeName: policy.certIdentity,
          issuer: "https://token.actions.githubusercontent.com",
          githubWorkflowTrigger: policy.workflowTrigger,
          githubWorkflowSHA: policy.sourceDigest,
          githubWorkflowName: policy.workflowName,
          githubWorkflowRepository: policy.repository,
          githubWorkflowRef: policy.sourceRef,
          buildSignerURI: policy.certIdentity,
          buildSignerDigest: policy.signerDigest,
          runnerEnvironment: policy.runnerEnvironment,
          sourceRepositoryURI: policy.repositoryUri,
          sourceRepositoryDigest: policy.sourceDigest,
          sourceRepositoryRef: policy.sourceRef,
          sourceRepositoryIdentifier: policy.repositoryId,
          sourceRepositoryOwnerURI: "https://github.com/zuhak5",
          sourceRepositoryOwnerIdentifier: policy.repositoryOwnerId,
          buildConfigURI: policy.certIdentity,
          buildConfigDigest: policy.signerDigest,
          buildTrigger: policy.workflowTrigger,
          runInvocationURI: policy.runInvocationUri,
          sourceRepositoryVisibilityAtSigning: policy.sourceRepositoryVisibilityAtSigning,
        },
      },
      verifiedTimestamps: [
        { timestamp: "2026-08-09T18:58:58Z" },
      ],
      statement: {
        _type: "https://in-toto.io/Statement/v1",
        predicateType: policy.predicateType,
        subject: [
          {
            name: policy.artifactName,
            digest: { sha256: policy.artifactSha256 },
          },
        ],
        predicate: {
          buildDefinition: {
            buildType: "https://actions.github.io/buildtypes/workflow/v1",
            externalParameters: {
              workflow: {
                path: policy.workflowPath,
                ref: policy.sourceRef,
                repository: policy.repositoryUri,
              },
            },
            internalParameters: {
              github: {
                event_name: policy.workflowTrigger,
                repository_id: policy.repositoryId,
                repository_owner_id: policy.repositoryOwnerId,
                runner_environment: policy.runnerEnvironment,
              },
            },
            resolvedDependencies: [
              {
                uri: `git+${policy.repositoryUri}@${policy.sourceRef}`,
                digest: { gitCommit: policy.sourceDigest },
              },
            ],
          },
          runDetails: {
            builder: { id: policy.certIdentity },
            metadata: { invocationId: policy.runInvocationUri },
          },
        },
      },
    },
    ...overrides,
  };
  return JSON.parse(JSON.stringify(record));
}

function verificationJson(policy, overrides = {}) {
  return JSON.stringify([verificationEntry(policy, overrides)]);
}

test("buildAndroidProvenancePolicy binds APK and AAB to the unified Shorebird rail", () => {
  const apk = policyFixture();
  const aab = buildAndroidProvenancePolicy({
    artifactType: "aab",
    repository: "zuhak5/Owntend",
    sourceDigest: SOURCE_SHA,
  });
  assert.equal(apk.workflowPath, ".github/workflows/shorebird-release-android.yml");
  assert.equal(aab.workflowPath, ".github/workflows/shorebird-release-android.yml");
  assert.equal(apk.certIdentity, aab.certIdentity);
  assert.notEqual(apk.artifactType, aab.artifactType);
});

test("verifyAttestationVerificationJson accepts the exact tuple", () => {
  const policy = policyFixture();
  const normalized = verifyAttestationVerificationJson(verificationJson(policy), policy);
  assert.equal(normalized.repository, policy.repository);
  assert.equal(normalized.sourceRepositoryDigest, policy.sourceDigest);
  assert.equal(normalized.signerWorkflow, policy.certIdentity);
  assert.equal(normalized.runInvocationUri, policy.runInvocationUri);
  assert.equal(normalized.runId, "31329512924");
  assert.equal(normalized.runAttempt, "1");
});

test("verifyAttestationVerificationJson rejects a wrong source digest", () => {
  const policy = policyFixture();
  const json = verificationJson(policy);
  const wrongPolicy = policyFixture({ sourceDigest: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" });
  assert.throws(
    () => verifyAttestationVerificationJson(json, wrongPolicy),
    /Source repository digest mismatch/,
  );
});

test("verifyAttestationVerificationJson rejects a wrong source ref", () => {
  const policy = policyFixture();
  const tampered = verificationEntry(policy);
  tampered.verificationResult.signature.certificate.sourceRepositoryRef = "refs/heads/release";
  tampered.verificationResult.signature.certificate.githubWorkflowRef = "refs/heads/release";
  tampered.verificationResult.statement.predicate.buildDefinition.externalParameters.workflow.ref =
    "refs/heads/release";
  tampered.verificationResult.statement.predicate.buildDefinition.resolvedDependencies[0].uri =
    `git+${policy.repositoryUri}@refs/heads/release`;
  assert.throws(
    () => verifyAttestationVerificationJson(JSON.stringify([tampered]), policy),
    /Source repository ref mismatch/,
  );
});

test("verifyAttestationVerificationJson rejects a wrong signer workflow identity", () => {
  const policy = policyFixture();
  const wrongPolicy = buildAndroidProvenancePolicy({
    artifactType: "apk",
    repository: "zuhak5/Owntend",
    sourceDigest: SOURCE_SHA,
    sourceRef: "refs/heads/main",
    runId: "31329512924",
    runAttempt: "1",
    artifactName: policy.artifactName,
    artifactSha256: ARTIFACT_SHA,
  });
  const tampered = verificationEntry(policy);
  tampered.verificationResult.signature.certificate.subjectAlternativeName =
    "https://github.com/zuhak5/Owntend/.github/workflows/untrusted.yml@refs/heads/main";
  assert.throws(
    () => verifyAttestationVerificationJson(JSON.stringify([tampered]), wrongPolicy),
    /Certificate identity mismatch/,
  );
});

test("verifyAttestationVerificationJson rejects a wrong repository", () => {
  const policy = policyFixture();
  const tampered = verificationEntry(policy);
  tampered.verificationResult.signature.certificate.githubWorkflowRepository = "other/repo";
  assert.throws(
    () => verifyAttestationVerificationJson(JSON.stringify([tampered]), policy),
    /Workflow repository mismatch/,
  );
});

test("verifyAttestationVerificationJson rejects a wrong workflow trigger", () => {
  const policy = policyFixture();
  const tampered = verificationEntry(policy);
  tampered.verificationResult.signature.certificate.githubWorkflowTrigger = "push";
  assert.throws(
    () => verifyAttestationVerificationJson(JSON.stringify([tampered]), policy),
    /Workflow trigger mismatch/,
  );
});

test("verifyAttestationVerificationJson rejects a wrong run invocation URI", () => {
  const policy = policyFixture();
  const tampered = verificationEntry(policy);
  tampered.verificationResult.signature.certificate.runInvocationURI =
    "https://github.com/zuhak5/Owntend/actions/runs/99999999999/attempts/1";
  assert.throws(
    () => verifyAttestationVerificationJson(JSON.stringify([tampered]), policy),
    /Run invocation URI mismatch/,
  );
});

test("verifyAttestationVerificationJson rejects ambiguous multiple attestations", () => {
  const policy = policyFixture();
  const json = JSON.stringify([verificationEntry(policy), verificationEntry(policy)]);
  assert.throws(
    () => verifyAttestationVerificationJson(json, policy),
    /Expected exactly one verified attestation/,
  );
});

test("formatGhAttestationVerifyCommand includes the exact tuple flags", () => {
  const policy = policyFixture();
  const command = formatGhAttestationVerifyCommand(policy, policy.artifactName);
  assert.match(command, /--source-digest 6f5606925964c9794d0f1ba863ec954239a47c9b/);
  assert.match(command, /--source-ref refs\/heads\/main/);
  assert.match(
    command,
    /--cert-identity https:\/\/github\.com\/zuhak5\/Owntend\/\.github\/workflows\/shorebird-release-android\.yml@refs\/heads\/main/,
  );
  assert.match(command, /--deny-self-hosted-runners/);
  assert.match(command, /--format json/);
});
