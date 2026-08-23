import fs from 'node:fs';
import fsPromises from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

export const SHOREBIRD_PATCH_EVIDENCE_SCHEMA_VERSION = 1;
export const VALID_FLAVORS = Object.freeze(['dev', 'staging', 'prod']);
export const VALID_TRACKS = Object.freeze(['staging', 'stable']);

const COMMIT_PATTERN = /^[a-f\d]{40}$/iu;
const RELEASE_VERSION_PATTERN = /^\d+\.\d+\.\d+\+\d+$/u;

export function verifyShorebirdPatchEvidence(evidence, options = {}) {
  const issues = [];

  if (!evidence || typeof evidence !== 'object' || Array.isArray(evidence)) {
    return {
      isValid: false,
      issues: ['Patch evidence must be a non-empty object.'],
    };
  }

  if (evidence.schemaVersion !== SHOREBIRD_PATCH_EVIDENCE_SCHEMA_VERSION) {
    issues.push(
      `Unsupported schemaVersion: expected ${SHOREBIRD_PATCH_EVIDENCE_SCHEMA_VERSION}, received ${evidence.schemaVersion}.`,
    );
  }

  if (!evidence.releaseVersion || !RELEASE_VERSION_PATTERN.test(String(evidence.releaseVersion))) {
    issues.push(`Invalid releaseVersion: "${evidence.releaseVersion}". Expected format: x.y.z+n.`);
  }

  if (!Number.isInteger(evidence.patchNumber) || evidence.patchNumber < 1) {
    issues.push(`Invalid patchNumber: "${evidence.patchNumber}". Expected positive integer.`);
  }

  if (!VALID_FLAVORS.includes(evidence.flavor)) {
    issues.push(`Invalid flavor: "${evidence.flavor}". Expected one of: ${VALID_FLAVORS.join(', ')}.`);
  }

  if (!VALID_TRACKS.includes(evidence.track)) {
    issues.push(`Invalid track: "${evidence.track}". Expected one of: ${VALID_TRACKS.join(', ')}.`);
  }

  if (!evidence.candidateSha || !COMMIT_PATTERN.test(String(evidence.candidateSha))) {
    issues.push(`Invalid candidateSha: "${evidence.candidateSha}". Expected 40-character hex SHA.`);
  }

  if (!evidence.releaseBaseSha || !COMMIT_PATTERN.test(String(evidence.releaseBaseSha))) {
    issues.push(`Invalid releaseBaseSha: "${evidence.releaseBaseSha}". Expected 40-character hex SHA.`);
  }

  if (typeof evidence.sentrySymbolsUploaded !== 'boolean') {
    issues.push('sentrySymbolsUploaded must be a boolean flag.');
  }

  if (options.requireSentrySymbols && evidence.sentrySymbolsUploaded !== true) {
    issues.push('Sentry symbols must be uploaded before promoting patch to stable track.');
  }

  return {
    isValid: issues.length === 0,
    issues,
  };
}

async function main() {
  const args = process.argv.slice(2);
  const evidencePath = args[0];

  if (!evidencePath) {
    console.error('Usage: node tool/verify_shorebird_patch_evidence.mjs <path-to-patch-evidence.json>');
    process.exit(1);
  }

  try {
    const raw = await fsPromises.readFile(path.resolve(evidencePath), 'utf8');
    const data = JSON.parse(raw);
    const result = verifyShorebirdPatchEvidence(data);

    if (!result.isValid) {
      console.error('Shorebird patch evidence verification failed:');
      for (const issue of result.issues) {
        console.error(` - ${issue}`);
      }
      process.exit(1);
    }

    console.log('Shorebird patch evidence verified successfully.');
    process.exit(0);
  } catch (error) {
    console.error(`Error reading patch evidence: ${error.message}`);
    process.exit(1);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
