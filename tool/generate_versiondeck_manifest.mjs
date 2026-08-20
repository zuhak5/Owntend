import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { main } from "./generate_versiondeck_manifest_v5.mjs";

export * from "./generate_versiondeck_manifest_v5.mjs";

const invokedAsScript = process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedAsScript) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
