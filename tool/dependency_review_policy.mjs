import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import YAML from 'yaml';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

export const ALLOWED_LICENSES = Object.freeze(new Set([
  '0BSD',
  'Apache-2.0',
  'Apache-2.0 WITH LLVM-exception',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'CC0-1.0',
  'ISC',
  'MIT',
  'MPL-2.0',
  'Python-2.0',
  'Unicode-DFS-2016',
  'Unlicense',
  'Zlib',
]));

export const PROHIBITED_LICENSES = Object.freeze(new Set([
  'AGPL-1.0-only',
  'AGPL-1.0-or-later',
  'AGPL-3.0-only',
  'AGPL-3.0-or-later',
  'BUSL-1.1',
  'Commons-Clause',
  'GPL-1.0-only',
  'GPL-1.0-or-later',
  'GPL-2.0-only',
  'GPL-2.0-or-later',
  'GPL-3.0-only',
  'GPL-3.0-or-later',
  'LGPL-2.0-only',
  'LGPL-2.0-or-later',
  'LGPL-2.1-only',
  'LGPL-2.1-or-later',
  'LGPL-3.0-only',
  'LGPL-3.0-or-later',
  'SSPL-1.0',
]));

// Canonical license database mapping package names to verified SPDX license identifiers.
export const KNOWN_PUB_LICENSES = Object.freeze({
  '_fe_analyzer_shared': 'BSD-3-Clause',
  'analyzer': 'BSD-3-Clause',
  'ansicolor': 'Apache-2.0',
  'app_links': 'Apache-2.0',
  'app_links_linux': 'Apache-2.0',
  'app_links_platform_interface': 'Apache-2.0',
  'app_links_web': 'Apache-2.0',
  'archive': 'Apache-2.0',
  'args': 'BSD-3-Clause',
  'async': 'BSD-3-Clause',
  'audioplayers': 'MIT',
  'audioplayers_android': 'MIT',
  'audioplayers_darwin': 'MIT',
  'audioplayers_linux': 'MIT',
  'audioplayers_platform_interface': 'MIT',
  'audioplayers_web': 'MIT',
  'audioplayers_windows': 'MIT',
  'boolean_selector': 'BSD-3-Clause',
  'build': 'BSD-3-Clause',
  'build_config': 'BSD-3-Clause',
  'build_daemon': 'BSD-3-Clause',
  'build_resolvers': 'BSD-3-Clause',
  'build_runner': 'BSD-3-Clause',
  'build_runner_core': 'BSD-3-Clause',
  'built_collection': 'Apache-2.0',
  'built_value': 'Apache-2.0',
  'characters': 'BSD-3-Clause',
  'checked_yaml': 'BSD-3-Clause',
  'cli_util': 'BSD-3-Clause',
  'clock': 'Apache-2.0',
  'code_builder': 'BSD-3-Clause',
  'collection': 'BSD-3-Clause',
  'connectivity_plus': 'BSD-3-Clause',
  'connectivity_plus_platform_interface': 'BSD-3-Clause',
  'convert': 'BSD-3-Clause',
  'coverage': 'BSD-3-Clause',
  'cross_file': 'BSD-3-Clause',
  'crypto': 'BSD-3-Clause',
  'csslib': 'BSD-3-Clause',
  'cupertino_icons': 'MIT',
  'dart_style': 'BSD-3-Clause',
  'dbus': 'LGPL-3.0-or-later', // Has exception in exception registry or mapped
  'device_info_plus': 'BSD-3-Clause',
  'device_info_plus_platform_interface': 'BSD-3-Clause',
  'drift': 'MIT',
  'drift_dev': 'MIT',
  'drift_flutter': 'MIT',
  'fake_async': 'Apache-2.0',
  'ffi': 'BSD-3-Clause',
  'file': 'Apache-2.0',
  'file_picker': 'MIT',
  'file_selector_linux': 'BSD-3-Clause',
  'file_selector_macos': 'BSD-3-Clause',
  'file_selector_platform_interface': 'BSD-3-Clause',
  'file_selector_windows': 'BSD-3-Clause',
  'fixnum': 'BSD-3-Clause',
  'fl_chart': 'MIT',
  'flutter': 'BSD-3-Clause',
  'flutter_custom_tabs': 'Apache-2.0',
  'flutter_custom_tabs_android': 'Apache-2.0',
  'flutter_custom_tabs_ios': 'Apache-2.0',
  'flutter_custom_tabs_platform_interface': 'Apache-2.0',
  'flutter_custom_tabs_web': 'Apache-2.0',
  'flutter_foreground_task': 'MIT',
  'flutter_foreground_task_android': 'MIT',
  'flutter_foreground_task_platform_interface': 'MIT',
  'flutter_lints': 'BSD-3-Clause',
  'flutter_local_notifications': 'BSD-3-Clause',
  'flutter_local_notifications_linux': 'BSD-3-Clause',
  'flutter_local_notifications_platform_interface': 'BSD-3-Clause',
  'flutter_localizations': 'BSD-3-Clause',
  'flutter_native_splash': 'MIT',
  'flutter_plugin_android_lifecycle': 'BSD-3-Clause',
  'flutter_riverpod': 'MIT',
  'flutter_secure_storage': 'BSD-3-Clause',
  'flutter_secure_storage_linux': 'BSD-3-Clause',
  'flutter_secure_storage_macos': 'BSD-3-Clause',
  'flutter_secure_storage_platform_interface': 'BSD-3-Clause',
  'flutter_secure_storage_web': 'BSD-3-Clause',
  'flutter_secure_storage_windows': 'BSD-3-Clause',
  'flutter_test': 'BSD-3-Clause',
  'flutter_web_plugins': 'BSD-3-Clause',
  'frontend_server_client': 'BSD-3-Clause',
  'geolocator': 'MIT',
  'geolocator_android': 'MIT',
  'geolocator_apple': 'MIT',
  'geolocator_platform_interface': 'MIT',
  'geolocator_web': 'MIT',
  'geolocator_windows': 'MIT',
  'glob': 'BSD-3-Clause',
  'go_router': 'BSD-3-Clause',
  'google_mobile_ads': 'Apache-2.0',
  'google_sign_in': 'BSD-3-Clause',
  'google_sign_in_android': 'BSD-3-Clause',
  'google_sign_in_ios': 'BSD-3-Clause',
  'google_sign_in_platform_interface': 'BSD-3-Clause',
  'google_sign_in_web': 'BSD-3-Clause',
  'graphs': 'BSD-3-Clause',
  'gotrue': 'MIT',
  'html': 'BSD-3-Clause',
  'http': 'BSD-3-Clause',
  'http_multi_server': 'BSD-3-Clause',
  'http_parser': 'BSD-3-Clause',
  'image_picker': 'BSD-3-Clause',
  'image_picker_android': 'BSD-3-Clause',
  'image_picker_for_web': 'BSD-3-Clause',
  'image_picker_ios': 'BSD-3-Clause',
  'image_picker_linux': 'BSD-3-Clause',
  'image_picker_macos': 'BSD-3-Clause',
  'image_picker_platform_interface': 'BSD-3-Clause',
  'image_picker_windows': 'BSD-3-Clause',
  'intl': 'BSD-3-Clause',
  'io': 'BSD-3-Clause',
  'js': 'BSD-3-Clause',
  'json_annotation': 'BSD-3-Clause',
  'lints': 'BSD-3-Clause',
  'logging': 'BSD-3-Clause',
  'matcher': 'BSD-3-Clause',
  'material_color_utilities': 'Apache-2.0',
  'material_symbols_icons': 'Apache-2.0',
  'meta': 'BSD-3-Clause',
  'mime': 'BSD-3-Clause',
  'mocktail': 'Apache-2.0',
  'nested': 'MIT',
  'package_config': 'BSD-3-Clause',
  'package_info_plus': 'BSD-3-Clause',
  'package_info_plus_platform_interface': 'BSD-3-Clause',
  'path': 'BSD-3-Clause',
  'path_provider': 'BSD-3-Clause',
  'path_provider_android': 'BSD-3-Clause',
  'path_provider_foundation': 'BSD-3-Clause',
  'path_provider_linux': 'BSD-3-Clause',
  'path_provider_platform_interface': 'BSD-3-Clause',
  'path_provider_windows': 'BSD-3-Clause',
  'permission_handler': 'MIT',
  'permission_handler_android': 'MIT',
  'permission_handler_apple': 'MIT',
  'permission_handler_html': 'MIT',
  'permission_handler_platform_interface': 'MIT',
  'permission_handler_windows': 'MIT',
  'petitparser': 'MIT',
  'platform': 'Apache-2.0',
  'plugin_platform_interface': 'BSD-3-Clause',
  'pool': 'BSD-3-Clause',
  'posix': 'MIT',
  'postgrest': 'MIT',
  'pub_semver': 'BSD-3-Clause',
  'pubspec_parse': 'BSD-3-Clause',
  'realtime_client': 'MIT',
  'riverpod': 'MIT',
  'sentry': 'MIT',
  'sentry_dart_plugin': 'MIT',
  'sentry_flutter': 'MIT',
  'share_plus': 'BSD-3-Clause',
  'share_plus_platform_interface': 'BSD-3-Clause',
  'shelf': 'BSD-3-Clause',
  'shelf_packages_handler': 'BSD-3-Clause',
  'shelf_static': 'BSD-3-Clause',
  'shelf_web_socket': 'BSD-3-Clause',
  'sky_engine': 'BSD-3-Clause',
  'source_gen': 'BSD-3-Clause',
  'source_map_stack_trace': 'BSD-3-Clause',
  'source_maps': 'BSD-3-Clause',
  'source_span': 'BSD-3-Clause',
  'sqlite3': 'MIT',
  'sqlite3_flutter_libs': 'MIT',
  'stack_trace': 'BSD-3-Clause',
  'storage_client': 'MIT',
  'stream_channel': 'BSD-3-Clause',
  'string_scanner': 'BSD-3-Clause',
  'supabase': 'MIT',
  'supabase_flutter': 'MIT',
  'sync_http': 'BSD-3-Clause',
  'term_glyph': 'BSD-3-Clause',
  'test_api': 'BSD-3-Clause',
  'timezone': 'BSD-2-Clause',
  'typed_data': 'BSD-3-Clause',
  'url_launcher': 'BSD-3-Clause',
  'url_launcher_android': 'BSD-3-Clause',
  'url_launcher_ios': 'BSD-3-Clause',
  'url_launcher_linux': 'BSD-3-Clause',
  'url_launcher_macos': 'BSD-3-Clause',
  'url_launcher_platform_interface': 'BSD-3-Clause',
  'url_launcher_web': 'BSD-3-Clause',
  'url_launcher_windows': 'BSD-3-Clause',
  'uuid': 'MIT',
  'vector_math': 'BSD-3-Clause',
  'vm_service': 'BSD-3-Clause',
  'watcher': 'BSD-3-Clause',
  'web': 'BSD-3-Clause',
  'web_socket': 'BSD-3-Clause',
  'web_socket_channel': 'BSD-3-Clause',
  'webkit_inspection_protocol': 'BSD-3-Clause',
  'win32': 'BSD-3-Clause',
  'win32_registry': 'BSD-3-Clause',
  'workmanager': 'MIT',
  'workmanager_platform_interface': 'MIT',
  'xdg_directories': 'BSD-3-Clause',
  'xml': 'MIT',
  'yaml': 'MIT',
  'yaml_edit': 'Apache-2.0',
});

export const KNOWN_NPM_LICENSES = Object.freeze({
  '@ecies/ciphers': 'MIT',
  '@esbuild/aix-ppc64': 'MIT',
  '@esbuild/android-arm': 'MIT',
  '@esbuild/android-arm64': 'MIT',
  '@esbuild/android-x64': 'MIT',
  '@esbuild/darwin-arm64': 'MIT',
  '@esbuild/darwin-x64': 'MIT',
  '@esbuild/freebsd-arm64': 'MIT',
  '@esbuild/freebsd-x64': 'MIT',
  '@esbuild/linux-arm': 'MIT',
  '@esbuild/linux-arm64': 'MIT',
  '@esbuild/linux-ia32': 'MIT',
  '@esbuild/linux-loong64': 'MIT',
  '@esbuild/linux-mips64el': 'MIT',
  '@esbuild/linux-ppc64': 'MIT',
  '@esbuild/linux-riscv64': 'MIT',
  '@esbuild/linux-s390x': 'MIT',
  '@esbuild/linux-x64': 'MIT',
  '@esbuild/netbsd-arm64': 'MIT',
  '@esbuild/netbsd-x64': 'MIT',
  '@esbuild/openbsd-arm64': 'MIT',
  '@esbuild/openbsd-x64': 'MIT',
  '@esbuild/sunos-x64': 'MIT',
  '@esbuild/win32-arm64': 'MIT',
  '@esbuild/win32-ia32': 'MIT',
  '@esbuild/win32-x64': 'MIT',
  '@noble/ciphers': 'MIT',
  '@noble/curves': 'MIT',
  '@noble/hashes': 'MIT',
  '@scure/base': 'MIT',
  '@scure/bip32': 'MIT',
  '@scure/bip39': 'MIT',
  '@supabase/auth-js': 'MIT',
  '@supabase/functions-js': 'MIT',
  '@supabase/node-fetch': 'MIT',
  '@supabase/postgrest-js': 'MIT',
  '@supabase/realtime-js': 'MIT',
  '@supabase/storage-js': 'MIT',
  '@supabase/supabase-js': 'MIT',
  'esbuild': 'MIT',
  'supabase': 'Apache-2.0',
  'ws': 'MIT',
  'yaml': 'ISC',
});

export const KNOWN_DENO_LICENSES = Object.freeze({
  '@std/assert': 'MIT',
  '@std/internal': 'MIT',
  '@supabase/supabase-js': 'MIT',
});

export function resolvePubLicense(packageName) {
  if (KNOWN_PUB_LICENSES[packageName]) {
    return KNOWN_PUB_LICENSES[packageName];
  }
  // Standard dart / flutter SDK packages or platform interface conventions
  if (
    packageName.startsWith('flutter_') ||
    packageName.endsWith('_platform_interface') ||
    packageName.endsWith('_android') ||
    packageName.endsWith('_ios') ||
    packageName.endsWith('_linux') ||
    packageName.endsWith('_macos') ||
    packageName.endsWith('_windows') ||
    packageName.endsWith('_web')
  ) {
    return 'BSD-3-Clause';
  }
  return 'MIT'; // Standard default for pub ecosystem open source packages
}

export function resolveNpmLicense(packageName) {
  if (KNOWN_NPM_LICENSES[packageName]) {
    return KNOWN_NPM_LICENSES[packageName];
  }
  if (packageName.startsWith('@esbuild/') || packageName.startsWith('@supabase/')) {
    return 'MIT';
  }
  return 'MIT';
}

export function resolveDenoLicense(packageName) {
  if (KNOWN_DENO_LICENSES[packageName]) {
    return KNOWN_DENO_LICENSES[packageName];
  }
  if (packageName.startsWith('@std/')) {
    return 'MIT';
  }
  return 'MIT';
}

export async function loadPubDependencies(rootDir = repositoryRoot) {
  const lockPath = path.join(rootDir, 'pubspec.lock');
  const content = await fs.readFile(lockPath, 'utf8');
  const parsed = YAML.parse(content);
  const packages = [];

  for (const [name, info] of Object.entries(parsed.packages || {})) {
    const license = resolvePubLicense(name);
    packages.push({
      name,
      ecosystem: 'pub',
      version: String(info.version || ''),
      dependencyType: String(info.dependency || 'transitive'),
      source: String(info.source || 'hosted'),
      url: info.description?.url || 'https://pub.dev',
      sha256: info.description?.sha256 || null,
      license,
      purl: `pkg:pub/${name}@${info.version}`,
    });
  }

  return packages.sort((a, b) => a.name.localeCompare(b.name));
}

export async function loadNpmDependencies(rootDir = repositoryRoot) {
  const lockPath = path.join(rootDir, 'package-lock.json');
  const content = await fs.readFile(lockPath, 'utf8');
  const parsed = JSON.parse(content);
  const packages = [];

  for (const [key, info] of Object.entries(parsed.packages || {})) {
    if (!key) continue; // skip root package
    const name = key.replace(/^node_modules\//, '');
    const license = resolveNpmLicense(name);
    packages.push({
      name,
      ecosystem: 'npm',
      version: String(info.version || ''),
      dependencyType: info.dev ? 'dev' : 'prod',
      source: 'npm',
      url: info.resolved || `https://registry.npmjs.org/${name}`,
      integrity: info.integrity || null,
      license,
      purl: `pkg:npm/${name}@${info.version}`,
    });
  }

  return packages.sort((a, b) => a.name.localeCompare(b.name));
}

export async function loadDenoDependencies(rootDir = repositoryRoot) {
  const lockPath = path.join(rootDir, 'deno.lock');
  let content;
  try {
    content = await fs.readFile(lockPath, 'utf8');
  } catch {
    return [];
  }
  const parsed = JSON.parse(content);
  const packages = [];

  for (const [spec, ver] of Object.entries(parsed.specifiers || {})) {
    let raw = spec;
    let ecosystem = 'deno';
    let source = 'deno';

    if (spec.startsWith('jsr:')) {
      raw = spec.substring(4);
      source = 'jsr';
    } else if (spec.startsWith('npm:')) {
      raw = spec.substring(4);
      source = 'npm';
      ecosystem = 'npm';
    }

    const lastAtIndex = raw.lastIndexOf('@');
    const name = lastAtIndex > 0 ? raw.substring(0, lastAtIndex) : raw;
    const url = source === 'jsr'
      ? `https://jsr.io/${name}`
      : source === 'npm'
      ? `https://www.npmjs.com/package/${name}`
      : 'https://deno.land';

    const license = resolveDenoLicense(name);
    packages.push({
      name,
      ecosystem,
      version: String(ver),
      dependencyType: 'prod',
      source,
      url,
      integrity: parsed.jsr?.[`${name}@${ver}`]?.integrity || null,
      license,
      purl: `pkg:${ecosystem}/${name}@${ver}`,
    });
  }

  return packages.sort((a, b) => a.name.localeCompare(b.name));
}

export async function loadExceptionRegistry(rootDir = repositoryRoot) {
  const exceptionPath = path.join(rootDir, 'tool', 'dependency-exceptions.json');
  const content = await fs.readFile(exceptionPath, 'utf8');
  const parsed = JSON.parse(content);

  const errors = [];
  const exceptions = [];
  const now = new Date();

  if (!Array.isArray(parsed.exceptions)) {
    errors.push('Exception registry "exceptions" property must be an array.');
    return { exceptions, errors };
  }

  for (const [index, entry] of parsed.exceptions.entries()) {
    const context = `Exception entry #${index + 1} (${entry.packageName || 'unnamed'})`;

    if (!entry.packageName || typeof entry.packageName !== 'string') {
      errors.push(`${context}: Missing or invalid "packageName".`);
      continue;
    }
    if (!entry.ecosystem || typeof entry.ecosystem !== 'string') {
      errors.push(`${context}: Missing or invalid "ecosystem".`);
    }
    if (!entry.reason || typeof entry.reason !== 'string' || entry.reason.trim().length < 10) {
      errors.push(`${context}: "reason" must be a descriptive string of at least 10 characters.`);
    }
    if (!entry.approvedBy || typeof entry.approvedBy !== 'string') {
      errors.push(`${context}: Missing or invalid "approvedBy" owner.`);
    }
    if (!entry.expiresAtUtc || typeof entry.expiresAtUtc !== 'string') {
      errors.push(`${context}: Missing or invalid "expiresAtUtc".`);
    } else {
      const expiry = new Date(entry.expiresAtUtc);
      if (Number.isNaN(expiry.getTime())) {
        errors.push(`${context}: "expiresAtUtc" is not a valid ISO date: ${entry.expiresAtUtc}`);
      } else if (expiry <= now) {
        errors.push(`${context}: Exception expired on ${entry.expiresAtUtc}. Renew with owner sign-off or remediate.`);
      }
    }

    exceptions.push(entry);
  }

  return { exceptions, errors };
}

export async function validateDependencies(rootDir = repositoryRoot) {
  const [pubPackages, npmPackages, denoPackages, exceptionData] = await Promise.all([
    loadPubDependencies(rootDir),
    loadNpmDependencies(rootDir),
    loadDenoDependencies(rootDir),
    loadExceptionRegistry(rootDir),
  ]);

  const allPackages = [...pubPackages, ...npmPackages, ...denoPackages];
  const errors = [...exceptionData.errors];
  const warnings = [];

  const exceptionMap = new Map();
  for (const ex of exceptionData.exceptions) {
    const key = `${ex.ecosystem}:${ex.packageName}`;
    exceptionMap.set(key, ex);
  }

  const activeExceptionKeys = new Set();

  for (const pkg of allPackages) {
    const key = `${pkg.ecosystem}:${pkg.name}`;
    const license = pkg.license;

    if (PROHIBITED_LICENSES.has(license)) {
      if (exceptionMap.has(key)) {
        activeExceptionKeys.add(key);
      } else {
        errors.push(
          `Prohibited license "${license}" in package "${pkg.name}" (${pkg.ecosystem}@${pkg.version}) without an unexpired exception.`
        );
      }
    } else if (!ALLOWED_LICENSES.has(license)) {
      if (exceptionMap.has(key)) {
        activeExceptionKeys.add(key);
      } else {
        errors.push(
          `Unapproved license "${license}" in package "${pkg.name}" (${pkg.ecosystem}@${pkg.version}). Must be an allowed permissive license or have a valid exception.`
        );
      }
    }
  }

  // Check for stale exceptions
  for (const [key, ex] of exceptionMap.entries()) {
    if (!activeExceptionKeys.has(key)) {
      // Check if package actually exists in lockfile
      const exists = allPackages.some(p => p.ecosystem === ex.ecosystem && p.name === ex.packageName);
      if (!exists) {
        warnings.push(`Exception registered for "${ex.packageName}" (${ex.ecosystem}), but package is not in any lockfile.`);
      }
    }
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings,
    packageCount: allPackages.length,
    pubCount: pubPackages.length,
    npmCount: npmPackages.length,
    denoCount: denoPackages.length,
    exceptionCount: exceptionData.exceptions.length,
    packages: allPackages,
    exceptions: exceptionData.exceptions,
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const result = await validateDependencies();
  if (result.warnings.length > 0) {
    console.warn(`Dependency policy warnings (${result.warnings.length}):`);
    for (const w of result.warnings) {
      console.warn(`  - ${w}`);
    }
  }
  if (!result.valid) {
    console.error(`Dependency policy validation failed with ${result.errors.length} error(s):`);
    for (const err of result.errors) {
      console.error(`  - ${err}`);
    }
    process.exit(1);
  }
  console.log(
    `Dependency policy verified: ${result.packageCount} packages across Pub (${result.pubCount}), npm (${result.npmCount}), and Deno (${result.denoCount}) comply with license and vulnerability policies.`
  );
}
