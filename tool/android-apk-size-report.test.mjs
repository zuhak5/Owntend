import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  buildSizeReport,
  componentForEntry,
  main,
  readZipEntries,
} from './android_apk_size_report.mjs';

function createFixtureZip(entries) {
  const localChunks = [];
  const centralChunks = [];
  let localOffset = 0;

  for (const entry of entries) {
    const name = Buffer.from(entry.path, 'utf8');
    const data = Buffer.from(entry.data ?? '', 'utf8');
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0, 6);
    local.writeUInt16LE(0, 8);
    local.writeUInt32LE(0, 14);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    localChunks.push(local, name, data);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0, 8);
    central.writeUInt16LE(0, 10);
    central.writeUInt32LE(0, 16);
    central.writeUInt32LE(data.length, 20);
    central.writeUInt32LE(data.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE(0, 38);
    central.writeUInt32LE(localOffset, 42);
    centralChunks.push(central, name);

    localOffset += local.length + name.length + data.length;
  }

  const localData = Buffer.concat(localChunks);
  const centralData = Buffer.concat(centralChunks);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(centralData.length, 12);
  eocd.writeUInt32LE(localData.length, 16);
  eocd.writeUInt16LE(0, 20);
  return Buffer.concat([localData, centralData, eocd]);
}

test('classifies every APK path into exactly one component', () => {
  const fixtures = [
    ['lib/arm64-v8a/libapp.so', 'lib'],
    ['assets/flutter_assets/AssetManifest.bin', 'flutterAssets'],
    ['classes.dex', 'dex'],
    ['classes2.dex', 'dex'],
    ['res/drawable/splash.xml', 'androidResources'],
    ['resources.arsc', 'androidResources'],
    ['META-INF/MANIFEST.MF', 'metaInf'],
    ['AndroidManifest.xml', 'other'],
    ['unknown/path.bin', 'other'],
  ];
  for (const [entryPath, expected] of fixtures) {
    assert.equal(componentForEntry(entryPath), expected, entryPath);
  }
});

test('reports deterministic totals without double counting', () => {
  const apkBuffer = createFixtureZip([
    { path: 'lib/arm64-v8a/libapp.so', data: 'native' },
    { path: 'assets/flutter_assets/a.txt', data: 'asset' },
    { path: 'classes.dex', data: 'dex' },
    { path: 'res/a.xml', data: 'resource' },
    { path: 'META-INF/MANIFEST.MF', data: 'meta' },
    { path: 'AndroidManifest.xml', data: 'manifest' },
  ]);
  assert.equal(readZipEntries(apkBuffer).length, 6);

  const input = {
    apkBuffer,
    artifactName: 'fixture.apk',
    sourceSha: '0123456789abcdef0123456789abcdef01234567',
    versionName: '1.0.0',
    versionCode: 2,
    abi: 'arm64-v8a',
  };
  const first = buildSizeReport(input);
  const second = buildSizeReport(input);
  assert.deepEqual(first, second);
  assert.equal(first.totalBytes, apkBuffer.length);
  assert.equal(first.zipEntryCount, 6);

  const compressedTotal = Object.values(first.components).reduce(
    (sum, component) => sum + component.compressedBytes,
    0,
  );
  const uncompressedTotal = Object.values(first.components).reduce(
    (sum, component) => sum + component.uncompressedBytes,
    0,
  );
  assert.equal(compressedTotal, first.zipEntriesCompressedBytes);
  assert.equal(uncompressedTotal, first.zipEntriesUncompressedBytes);
  assert.deepEqual(Object.keys(first.components.lib.byAbi), ['arm64-v8a']);
});

test('CLI writes byte-identical JSON for the same APK', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'owntend-apk-size-'));
  try {
    const apkPath = path.join(directory, 'fixture.apk');
    const firstPath = path.join(directory, 'first.json');
    const secondPath = path.join(directory, 'second.json');
    await fs.writeFile(
      apkPath,
      createFixtureZip([{ path: 'lib/arm64-v8a/libapp.so', data: 'native' }]),
    );
    const commonArgs = [
      '--apk', apkPath,
      '--source-sha', '0123456789abcdef0123456789abcdef01234567',
      '--version-name', '1.0.0',
      '--version-code', '2',
      '--abi', 'arm64-v8a',
    ];
    await main([...commonArgs, '--output', firstPath]);
    await main([...commonArgs, '--output', secondPath]);
    assert.deepEqual(await fs.readFile(firstPath), await fs.readFile(secondPath));
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test('release evidence integrates APK size reporting without replacing trust checks', async () => {
  const collector = await fs.readFile(
    new URL('./collect_android_release_evidence.ps1', import.meta.url),
    'utf8',
  );
  assert.match(collector, /android_apk_size_report\.mjs/u);
  assert.match(collector, /apk-size-report\.json/u);
  assert.match(collector, /artifactSha256/u);
  assert.match(collector, /totalBytes/u);
  assert.match(collector, /apksigner|release artifact|artifact_sha256/iu);
});
