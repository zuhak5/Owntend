import crypto from "node:crypto";
import fs from "node:fs";
import fsPromises from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  VERSIONDECK_PACKAGE_NAME,
  VERSIONDECK_REPOSITORY,
} from "../download-site/manifest-schema.js";
import {
  buildAndroidProvenancePolicy,
  buildGhAttestationVerifyArgs,
  verifyAttestationVerificationJson,
} from "./provenance_policy.mjs";

const execFileAsync = promisify(execFile);
const MAX_APK_SIZE_BYTES = 1024 * 1024 * 1024;
const COMMAND_TIMEOUT_MS = 2 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 5 * 60 * 1000;
const COMMIT_PATTERN = /^[a-f\d]{40}$/i;

function normalizedSigner(value) {
  const normalized = String(value || "").replace(/[^a-f\d]/gi, "").toUpperCase();
  return normalized.length === 64 ? normalized.match(/.{2}/g).join(":") : "";
}

async function githubFetch(url, token, accept = "application/vnd.github+json") {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      headers: {
        Accept: accept,
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "Owntend-VersionDeck-Manifest",
      },
      redirect: "follow",
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`GitHub request failed (${response.status}): ${await response.text()}`);
    }
    return response;
  } finally {
    clearTimeout(timeout);
  }
}

export async function fetchAllReleases(repository, token) {
  const releases = [];
  let url = `https://api.github.com/repos/${repository}/releases?per_page=100&page=1`;
  while (url) {
    const response = await githubFetch(url, token);
    releases.push(...(await response.json()));
    const next = (response.headers.get("link") || "")
      .split(",")
      .map((part) => part.trim())
      .find((part) => part.endsWith('rel="next"'));
    url = next?.match(/<([^>]+)>/)?.[1] || "";
  }
  return releases;
}

export async function readChecksumAsset(asset, token) {
  const response = await githubFetch(asset.url, token, "application/octet-stream");
  return response.text();
}

async function downloadAsset(asset, token, destination) {
  const response = await githubFetch(asset.url, token, "application/octet-stream");
  if (!response.body) throw new Error("GitHub asset response did not include a body.");
  const file = await fsPromises.open(destination, "w", 0o600);
  const hash = crypto.createHash("sha256");
  let total = 0;
  try {
    for await (const chunk of response.body) {
      total += chunk.byteLength;
      if (total > MAX_APK_SIZE_BYTES) throw new Error("APK exceeds the maximum allowed size.");
      hash.update(chunk);
      await file.write(chunk);
    }
  } finally {
    await file.close();
  }
  if (total !== asset.size) {
    throw new Error(`Downloaded APK size ${total} does not match GitHub asset size ${asset.size}.`);
  }
  return hash.digest("hex");
}

async function commandExists(command) {
  try {
    await execFileAsync(process.platform === "win32" ? "where" : "which", [command]);
    return command;
  } catch {
    return "";
  }
}

async function findAndroidTool(name) {
  const override = process.env[`${name.toUpperCase()}_PATH`];
  if (override) return override;
  const direct = await commandExists(name);
  if (direct) return direct;
  const androidHome = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT;
  if (!androidHome) throw new Error(`${name} was not found and ANDROID_HOME is unavailable.`);
  const versions = (await fsPromises.readdir(path.join(androidHome, "build-tools"), {
    withFileTypes: true,
  }))
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort((left, right) => right.localeCompare(left, undefined, { numeric: true }));
  for (const version of versions) {
    const suffix = process.platform === "win32" ? (name === "apksigner" ? ".bat" : ".exe") : "";
    const candidate = path.join(androidHome, "build-tools", version, `${name}${suffix}`);
    if (fs.existsSync(candidate)) return candidate;
  }
  throw new Error(`${name} was not found in Android build tools.`);
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

async function isCurrentMainAncestor(commitSha) {
  try {
    await runChecked("git", ["merge-base", "--is-ancestor", commitSha, "origin/main"]);
    return true;
  } catch {
    return false;
  }
}

async function resolveReleaseCommit(tag, historicalDecision) {
  const { stdout } = await runChecked("git", ["rev-parse", `${tag}^{commit}`]);
  const commitSha = stdout.trim().toLowerCase();
  if (!COMMIT_PATTERN.test(commitSha)) throw new Error("Release tag did not resolve to a commit.");
  if (await isCurrentMainAncestor(commitSha)) return commitSha;

  if (!historicalDecision) {
    throw new Error(
      "Release commit is not an ancestor of current main and no explicit historical decision exists.",
    );
  }
  if (historicalDecision.tag !== tag) {
    throw new Error("Historical release decision does not match the release tag.");
  }
  if (String(historicalDecision.commitSha || "").toLowerCase() !== commitSha) {
    throw new Error("Historical release decision does not match the release commit.");
  }
  return commitSha;
}

export function buildVersionDeckApkProvenancePolicy({ commitSha, apkAsset, sha256 }) {
  return buildAndroidProvenancePolicy({
    artifactType: "apk",
    repository: VERSIONDECK_REPOSITORY,
    sourceDigest: commitSha,
    sourceRef: "refs/heads/main",
    workflowTrigger: "workflow_dispatch",
    runnerEnvironment: "github-hosted",
    sourceRepositoryVisibilityAtSigning: "public",
    artifactName: apkAsset?.name || "",
    artifactSha256: sha256,
  });
}

export async function verifyReleaseArtifact({ release, apkAsset, historicalDecision }, token) {
  const temporaryDirectory = await fsPromises.mkdtemp(path.join(os.tmpdir(), "versiondeck-"));
  const apkPath = path.join(temporaryDirectory, apkAsset.name);
  try {
    const sha256 = await downloadAsset(apkAsset, token, apkPath);
    const apksigner = await findAndroidTool("apksigner");
    const aapt2 = await findAndroidTool("aapt2");

    const signature = await runChecked(apksigner, ["verify", "--verbose", "--print-certs", apkPath]);
    const signerMatch = `${signature.stdout}\n${signature.stderr}`.match(
      /(?:Signer #\d+|V\d+(?:\.\d+)? Signer:)\s+certificate SHA-256 digest:\s*([0-9A-Fa-f:]+)/,
    );
    if (!signerMatch) throw new Error("APK signer SHA-256 could not be extracted.");

    const badging = await runChecked(aapt2, ["dump", "badging", apkPath]);
    const packageMatch = badging.stdout.match(
      /package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'/,
    );
    if (!packageMatch) throw new Error("APK package metadata could not be extracted.");
    if (/^application-debuggable/m.test(badging.stdout)) throw new Error("APK is debuggable.");

    const commitSha = await resolveReleaseCommit(release.tag_name, historicalDecision);
    const provenancePolicy = buildVersionDeckApkProvenancePolicy({
      commitSha,
      apkAsset,
      sha256,
    });
    const { stdout: attestationJson } = await runChecked(
      "gh",
      buildGhAttestationVerifyArgs(provenancePolicy, apkPath, { formatJson: true }),
      {
        env: { ...process.env, GH_TOKEN: token },
      },
    );
    const provenance = verifyAttestationVerificationJson(attestationJson, provenancePolicy);

    return {
      sha256,
      packageName: packageMatch[1],
      version: packageMatch[3],
      build: Number(packageMatch[2]),
      signerCertificateSha256: normalizedSigner(signerMatch[1]),
      commitSha,
      attestationVerified: true,
      provenance,
    };
  } finally {
    await fsPromises.rm(temporaryDirectory, { recursive: true, force: true });
  }
}

export async function prepareVerificationRepository() {
  await runChecked("git", ["fetch", "origin", "main", "--tags", "--force"]);
  const { stdout } = await runChecked("git", ["rev-parse", "HEAD"]);
  const current = stdout.trim().toLowerCase();
  if (!COMMIT_PATTERN.test(current)) throw new Error("Checked-out source commit is invalid.");
  return current;
}

export function assertExpectedRepository(repository) {
  if (repository !== VERSIONDECK_REPOSITORY) {
    throw new Error(`VersionDeck may only verify releases for ${VERSIONDECK_REPOSITORY}.`);
  }
  if (VERSIONDECK_PACKAGE_NAME !== "app.owntend.mobile") {
    throw new Error("VersionDeck package policy is invalid.");
  }
}
