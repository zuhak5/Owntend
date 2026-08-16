import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  ACCOUNT_DELETION_SITE_URL,
  accountDeletionConfigFromEnvironment,
  validateAccountDeletionPublicConfig,
  writeAccountDeletionConfig,
} from "./build_account_deletion_site.mjs";

const PRIVACY_POLICY_URL =
  "https://github.com/zuhak5/Owntend/blob/main/PRIVACY.md";

function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined) {
      throw new Error("Expected --source, --output, and --revision arguments.");
    }
    values[key.slice(2)] = value;
  }
  return values;
}

async function listFiles(root, current = root) {
  const files = [];
  for (const entry of await fs.readdir(current, { withFileTypes: true })) {
    const absolute = path.join(current, entry.name);
    if (entry.isDirectory()) files.push(...await listFiles(root, absolute));
    else if (entry.isFile()) files.push(path.relative(root, absolute).replaceAll(path.sep, "/"));
  }
  return files.sort();
}

async function sha256(filePath) {
  return crypto.createHash("sha256").update(await fs.readFile(filePath)).digest("hex");
}

export function parseVersionDeckTarget(pubspec) {
  const match = String(pubspec || "").match(/^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m);
  if (!match) {
    throw new Error("pubspec.yaml must contain a version in X.Y.Z+N format.");
  }
  const build = Number(match[2]);
  if (!Number.isSafeInteger(build) || build < 1) {
    throw new Error("pubspec.yaml build number must be a positive integer.");
  }
  return Object.freeze({ version: match[1], build });
}

export async function buildVersionDeckSite({
  source,
  output,
  revision,
  accountDeletionConfig,
  allowInertAccountDeletionConfig = false,
}) {
  if (!/^[a-f\d]{40}$/i.test(revision || "")) {
    throw new Error("VersionDeck build revision must be a full commit SHA.");
  }
  const publicConfig = accountDeletionConfig == null
    ? accountDeletionConfigFromEnvironment(process.env, {
      allowInert: allowInertAccountDeletionConfig,
    })
    : validateAccountDeletionPublicConfig(accountDeletionConfig, {
      allowInert: allowInertAccountDeletionConfig,
    });
  const target = parseVersionDeckTarget(
    await fs.readFile(path.resolve(source, "..", "pubspec.yaml"), "utf8"),
  );
  await fs.rm(output, { recursive: true, force: true });
  await fs.cp(source, output, { recursive: true });
  await fs.rm(path.join(output, "release-diagnostics.json"), { force: true });
  await writeAccountDeletionConfig(output, publicConfig, {
    allowInert: allowInertAccountDeletionConfig,
  });

  const accountDeletionPagePath = path.join(output, "account-deletion.html");
  const accountDeletionPage = await fs.readFile(accountDeletionPagePath, "utf8");
  if (!accountDeletionPage.includes("__ACCOUNT_DELETION_ASSET_REVISION__")) {
    throw new Error("Account-deletion asset revision placeholder is missing.");
  }
  if (!accountDeletionPage.includes(ACCOUNT_DELETION_SITE_URL)) {
    throw new Error("Account-deletion canonical URL placeholder is missing.");
  }
  if (!accountDeletionPage.includes('href="PRIVACY.md"')) {
    throw new Error("Account-deletion privacy link placeholder is missing.");
  }
  await fs.writeFile(
    accountDeletionPagePath,
    accountDeletionPage
      .replaceAll(
        "__ACCOUNT_DELETION_ASSET_REVISION__",
        revision.toLowerCase(),
      )
      .replaceAll(ACCOUNT_DELETION_SITE_URL, publicConfig.accountDeletionSiteUrl)
      .replaceAll('href="PRIVACY.md"', `href="${PRIVACY_POLICY_URL}"`),
    "utf8",
  );

  const accountDeletionScriptPath = path.join(output, "account-deletion.js");
  const accountDeletionScript = await fs.readFile(accountDeletionScriptPath, "utf8");
  if (!accountDeletionScript.includes(ACCOUNT_DELETION_SITE_URL)) {
    throw new Error("Account-deletion browser callback URL placeholder is missing.");
  }
  await fs.writeFile(
    accountDeletionScriptPath,
    accountDeletionScript.replaceAll(
      ACCOUNT_DELETION_SITE_URL,
      publicConfig.accountDeletionSiteUrl,
    ),
    "utf8",
  );

  const indexPath = path.join(output, "index.html");
  const index = await fs.readFile(indexPath, "utf8");
  const defaultSiteRoot = new URL("./", ACCOUNT_DELETION_SITE_URL).toString();
  const deployedSiteRoot = new URL(
    "./",
    publicConfig.accountDeletionSiteUrl,
  ).toString();
  if (!index.includes(defaultSiteRoot)) {
    throw new Error("VersionDeck canonical site URL placeholder is missing.");
  }
  await fs.writeFile(
    indexPath,
    index.replaceAll(defaultSiteRoot, deployedSiteRoot),
    "utf8",
  );

  const serviceWorkerPath = path.join(output, "sw.js");
  const serviceWorker = await fs.readFile(serviceWorkerPath, "utf8");
  if (!serviceWorker.includes("__VERSIONDECK_CACHE_REVISION__")) {
    throw new Error("Service-worker cache revision placeholder is missing.");
  }
  await fs.writeFile(
    serviceWorkerPath,
    serviceWorker.replaceAll("__VERSIONDECK_CACHE_REVISION__", revision),
    "utf8",
  );

  const buildInfo = {
    schemaVersion: 1,
    sourceRevision: revision.toLowerCase(),
    builtAt: new Date().toISOString(),
    target,
  };
  await fs.writeFile(
    path.join(output, "build-info.json"),
    `${JSON.stringify(buildInfo, null, 2)}\n`,
    "utf8",
  );

  const inventory = {};
  for (const relativePath of await listFiles(output)) {
    if (relativePath === "asset-manifest.json") continue;
    inventory[relativePath] = await sha256(path.join(output, relativePath));
  }
  await fs.writeFile(
    path.join(output, "asset-manifest.json"),
    `${JSON.stringify({ schemaVersion: 1, revision: revision.toLowerCase(), files: inventory }, null, 2)}\n`,
    "utf8",
  );
  return { files: Object.keys(inventory).length, revision: revision.toLowerCase() };
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
  const root = path.resolve(scriptDirectory, "..");
  const result = await buildVersionDeckSite({
    source: path.resolve(root, args.source || "download-site"),
    output: path.resolve(root, args.output || ".versiondeck-site"),
    revision: args.revision || process.env.SOURCE_SHA,
    allowInertAccountDeletionConfig:
      parseBoolean(args["allow-inert-account-deletion-config"]),
  });
  console.log(`Built VersionDeck site with ${result.files} files at revision ${result.revision}.`);
}

function parseBoolean(value) {
  if (value == null || value === "false") return false;
  if (value === "true") return true;
  throw new Error("Boolean arguments must be either true or false.");
}

const invokedAsScript = process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedAsScript) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
