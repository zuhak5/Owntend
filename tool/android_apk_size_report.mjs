import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_DIRECTORY_SIGNATURE = 0x02014b50;
const MAX_EOCD_SEARCH = 0xffff + 22;

export function componentForEntry(entryPath) {
  if (entryPath.startsWith('lib/')) return 'lib';
  if (entryPath.startsWith('assets/flutter_assets/')) return 'flutterAssets';
  if (/^classes(?:\d+)?\.dex$/u.test(entryPath)) return 'dex';
  if (entryPath === 'resources.arsc' || entryPath.startsWith('res/')) {
    return 'androidResources';
  }
  if (entryPath.startsWith('META-INF/')) return 'metaInf';
  return 'other';
}

function findEndOfCentralDirectory(buffer) {
  const lowerBound = Math.max(0, buffer.length - MAX_EOCD_SEARCH);
  for (let offset = buffer.length - 22; offset >= lowerBound; offset -= 1) {
    if (buffer.readUInt32LE(offset) !== EOCD_SIGNATURE) continue;
    const commentLength = buffer.readUInt16LE(offset + 20);
    if (offset + 22 + commentLength === buffer.length) return offset;
  }
  throw new Error('ZIP end-of-central-directory record was not found.');
}

export function readZipEntries(buffer) {
  const eocdOffset = findEndOfCentralDirectory(buffer);
  const diskNumber = buffer.readUInt16LE(eocdOffset + 4);
  const centralDirectoryDisk = buffer.readUInt16LE(eocdOffset + 6);
  const entriesOnDisk = buffer.readUInt16LE(eocdOffset + 8);
  const totalEntries = buffer.readUInt16LE(eocdOffset + 10);
  const centralDirectorySize = buffer.readUInt32LE(eocdOffset + 12);
  const centralDirectoryOffset = buffer.readUInt32LE(eocdOffset + 16);

  if (diskNumber !== 0 || centralDirectoryDisk !== 0 || entriesOnDisk !== totalEntries) {
    throw new Error('Multi-disk ZIP archives are not supported.');
  }
  if (
    totalEntries === 0xffff ||
    centralDirectorySize === 0xffffffff ||
    centralDirectoryOffset === 0xffffffff
  ) {
    throw new Error('ZIP64 APKs are not supported by this size reporter.');
  }
  if (centralDirectoryOffset + centralDirectorySize > eocdOffset) {
    throw new Error('ZIP central-directory bounds are invalid.');
  }

  const entries = [];
  let offset = centralDirectoryOffset;
  for (let index = 0; index < totalEntries; index += 1) {
    if (offset + 46 > buffer.length || buffer.readUInt32LE(offset) !== CENTRAL_DIRECTORY_SIGNATURE) {
      throw new Error(`Invalid ZIP central-directory entry at index ${index}.`);
    }
    const flags = buffer.readUInt16LE(offset + 8);
    const compressedBytes = buffer.readUInt32LE(offset + 20);
    const uncompressedBytes = buffer.readUInt32LE(offset + 24);
    const fileNameLength = buffer.readUInt16LE(offset + 28);
    const extraLength = buffer.readUInt16LE(offset + 30);
    const commentLength = buffer.readUInt16LE(offset + 32);
    const localHeaderOffset = buffer.readUInt32LE(offset + 42);
    if (
      compressedBytes === 0xffffffff ||
      uncompressedBytes === 0xffffffff ||
      localHeaderOffset === 0xffffffff
    ) {
      throw new Error('ZIP64 entry metadata is not supported by this size reporter.');
    }
    if ((flags & 0x1) !== 0) {
      throw new Error('Encrypted ZIP entries are not supported.');
    }
    const nameStart = offset + 46;
    const nameEnd = nameStart + fileNameLength;
    const nextOffset = nameEnd + extraLength + commentLength;
    if (nextOffset > buffer.length) {
      throw new Error(`ZIP central-directory entry ${index} exceeds file bounds.`);
    }
    const entryPath = buffer.subarray(nameStart, nameEnd).toString('utf8');
    entries.push({ path: entryPath, compressedBytes, uncompressedBytes });
    offset = nextOffset;
  }
  if (offset !== centralDirectoryOffset + centralDirectorySize) {
    throw new Error('ZIP central-directory size does not match parsed entries.');
  }
  return entries;
}

function emptyComponent() {
  return { compressedBytes: 0, uncompressedBytes: 0 };
}

function parseAbi(entryPath) {
  const match = /^lib\/([^/]+)\//u.exec(entryPath);
  return match?.[1] ?? null;
}

export function buildSizeReport({
  apkBuffer,
  artifactName,
  sourceSha,
  versionName,
  versionCode,
  abi,
}) {
  if (!/^[0-9a-f]{40}$/iu.test(sourceSha)) {
    throw new Error('sourceSha must be a full 40-character hexadecimal Git SHA.');
  }
  if (!/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/u.test(versionName)) {
    throw new Error(`Invalid versionName: ${versionName}`);
  }
  const numericVersionCode = Number(versionCode);
  if (!Number.isSafeInteger(numericVersionCode) || numericVersionCode < 1) {
    throw new Error(`Invalid versionCode: ${versionCode}`);
  }

  const entries = readZipEntries(apkBuffer);
  const components = {
    lib: { ...emptyComponent(), byAbi: {} },
    flutterAssets: emptyComponent(),
    dex: emptyComponent(),
    androidResources: emptyComponent(),
    metaInf: emptyComponent(),
    other: emptyComponent(),
  };
  let zipEntriesCompressedBytes = 0;
  let zipEntriesUncompressedBytes = 0;
  const knownAbis = new Set();
  const classifiedEntries = [];

  for (const entry of entries) {
    const component = componentForEntry(entry.path);
    components[component].compressedBytes += entry.compressedBytes;
    components[component].uncompressedBytes += entry.uncompressedBytes;
    zipEntriesCompressedBytes += entry.compressedBytes;
    zipEntriesUncompressedBytes += entry.uncompressedBytes;

    if (component === 'lib') {
      const entryAbi = parseAbi(entry.path) ?? 'unknown';
      knownAbis.add(entryAbi);
      components.lib.byAbi[entryAbi] ??= emptyComponent();
      components.lib.byAbi[entryAbi].compressedBytes += entry.compressedBytes;
      components.lib.byAbi[entryAbi].uncompressedBytes += entry.uncompressedBytes;
    }
    classifiedEntries.push({ ...entry, component });
  }

  components.lib.byAbi = Object.fromEntries(
    Object.entries(components.lib.byAbi).sort(([left], [right]) => left.localeCompare(right)),
  );

  const inferredAbi =
    knownAbis.size === 1 ? [...knownAbis][0] : knownAbis.size > 1 ? 'universal' : 'none';
  if (abi && abi !== inferredAbi) {
    throw new Error(`Declared ABI ${abi} does not match APK contents (${inferredAbi}).`);
  }

  const largestEntries = classifiedEntries
    .filter((entry) => !entry.path.endsWith('/'))
    .sort((left, right) =>
      right.compressedBytes - left.compressedBytes || left.path.localeCompare(right.path),
    )
    .slice(0, 20)
    .map((entry) => ({
      path: entry.path,
      component: entry.component,
      compressedBytes: entry.compressedBytes,
      uncompressedBytes: entry.uncompressedBytes,
    }));

  return {
    schemaVersion: 1,
    sourceSha: sourceSha.toLowerCase(),
    artifactName,
    artifactSha256: crypto.createHash('sha256').update(apkBuffer).digest('hex'),
    abi: abi ?? inferredAbi,
    versionName,
    versionCode: numericVersionCode,
    totalBytes: apkBuffer.length,
    zipEntryCount: entries.length,
    zipEntriesCompressedBytes,
    zipEntriesUncompressedBytes,
    components,
    largestEntries,
  };
}

function parseArgs(argv) {
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) {
      throw new Error(`Expected --name value arguments, got: ${argv.slice(index).join(' ')}`);
    }
    values.set(key.slice(2), value);
  }
  for (const required of ['apk', 'output', 'source-sha', 'version-name', 'version-code']) {
    if (!values.has(required)) throw new Error(`Missing required argument --${required}.`);
  }
  return values;
}

export async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  const apkPath = path.resolve(args.get('apk'));
  const outputPath = path.resolve(args.get('output'));
  const apkBuffer = await fs.readFile(apkPath);
  const report = buildSizeReport({
    apkBuffer,
    artifactName: path.basename(apkPath),
    sourceSha: args.get('source-sha'),
    versionName: args.get('version-name'),
    versionCode: args.get('version-code'),
    abi: args.get('abi'),
  });
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await fs.writeFile(outputPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  console.log(`Wrote deterministic APK size report: ${outputPath}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
