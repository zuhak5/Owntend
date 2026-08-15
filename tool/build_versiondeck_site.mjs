import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  accountDeletionConfigFromEnvironment,
  validateAccountDeletionPublicConfig,
  writeAccountDeletionConfig,
} from "./build_account_deletion_site.mjs";

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
  await fs.writeFile(
    accountDeletionPagePath,
    accountDeletionPage.replaceAll(
      "__ACCOUNT_DELETION_ASSET_REVISION__",
      revision.toLowerCase(),
    ),
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
