import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

async function listFiles(dir) {
  const results = [];
  try {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        results.push(...await listFiles(fullPath));
      } else if (entry.isFile()) {
        results.push(fullPath);
      }
    }
  } catch (err) {
    if (err.code !== 'ENOENT') throw err;
  }
  return results;
}

export async function hashFile(filePath) {
  const buf = await fs.readFile(filePath);
  const hash = crypto.createHash('sha256').update(buf).digest('hex');
  return { hash, size: buf.length };
}

export async function validateAssetProvenance(rootDir = repositoryRoot) {
  const errors = [];
  const warnings = [];

  const configPath = path.join(rootDir, 'config/asset_provenance.json');
  let configRaw;
  try {
    configRaw = await fs.readFile(configPath, 'utf8');
  } catch (err) {
    return { valid: false, errors: [`Missing config/asset_provenance.json: ${err.message}`] };
  }

  let config;
  try {
    config = JSON.parse(configRaw);
  } catch (err) {
    return { valid: false, errors: [`Invalid JSON in config/asset_provenance.json: ${err.message}`] };
  }

  if (config.schemaVersion !== 1) {
    errors.push(`asset_provenance.json schemaVersion must be 1, found: ${config.schemaVersion}`);
  }
  if (config.legalDisposition !== 'APPROVED_FOR_DISTRIBUTION') {
    errors.push(`asset_provenance.json legalDisposition must be APPROVED_FOR_DISTRIBUTION, found: ${config.legalDisposition}`);
  }
  if (!config.reviewer) {
    errors.push('asset_provenance.json missing reviewer field');
  }

  // Check required license and notice files
  const requiredNotices = ['LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md'];
  for (const notice of requiredNotices) {
    const noticePath = path.join(rootDir, notice);
    try {
      const stat = await fs.stat(noticePath);
      if (stat.size === 0) {
        errors.push(`Required root license file is empty: ${notice}`);
      }
    } catch {
      errors.push(`Required root license file is missing: ${notice}`);
    }
  }

  // Scan disk assets
  const assetDirectories = [
    path.join(rootDir, 'assets'),
    path.join(rootDir, 'download-site/assets'),
  ];

  const diskFiles = [];
  for (const dir of assetDirectories) {
    diskFiles.push(...await listFiles(dir));
  }

  const diskAssetsMap = new Map();
  for (const absPath of diskFiles) {
    const relPath = path.relative(rootDir, absPath).replaceAll(path.sep, '/');
    const { hash, size } = await hashFile(absPath);
    diskAssetsMap.set(relPath, { hash, size, absPath });
  }

  const registryAssetsMap = new Map();
  for (const entry of (config.assets || [])) {
    if (!entry.path || !entry.sha256 || !entry.license || !entry.origin || !entry.creator) {
      errors.push(`Registry entry missing required metadata fields: ${JSON.stringify(entry)}`);
      continue;
    }
    registryAssetsMap.set(entry.path, entry);
  }

  // Check for unregistered or modified files on disk
  for (const [relPath, diskInfo] of diskAssetsMap.entries()) {
    const registryEntry = registryAssetsMap.get(relPath);
    if (!registryEntry) {
      errors.push(`Unregistered asset on disk: ${relPath} (SHA-256: ${diskInfo.hash}). Register in config/asset_provenance.json.`);
    } else {
      if (registryEntry.sha256.toLowerCase() !== diskInfo.hash.toLowerCase()) {
        errors.push(`Asset hash mismatch for ${relPath}: registry=${registryEntry.sha256}, disk=${diskInfo.hash}`);
      }
      if (registryEntry.sizeBytes !== diskInfo.size) {
        errors.push(`Asset size mismatch for ${relPath}: registry=${registryEntry.sizeBytes}, disk=${diskInfo.size}`);
      }
    }
  }

  // Check for missing registered files
  for (const [relPath, regEntry] of registryAssetsMap.entries()) {
    if (!diskAssetsMap.has(relPath)) {
      errors.push(`Registered asset missing from disk: ${relPath}`);
    }
  }

  return {
    valid: errors.length === 0,
    totalAssets: diskAssetsMap.size,
    registeredAssets: registryAssetsMap.size,
    errors,
    warnings,
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const result = await validateAssetProvenance();
  if (!result.valid) {
    console.error('Asset Provenance and License Policy Evaluation: FAILED');
    for (const err of result.errors) {
      console.error(`  [FAIL] ${err}`);
    }
    process.exit(1);
  }

  console.log(`Asset Provenance and License Policy Evaluation: PASS`);
  console.log(`  All ${result.totalAssets} visual, font, audio, and branding assets verified with matching SHA-256 hashes.`);
  console.log(`  Root LICENSE, NOTICE, and THIRD_PARTY_NOTICES.md verified.`);
}
