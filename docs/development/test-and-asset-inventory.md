# Canonical Runtime Asset and Test Inventory

## Overview

To guarantee that no release-critical runtime asset, client code, or intended test suite is silently omitted from validation, build artifacts, or deployment pipelines, Owntend maintains an authoritative inventory and discovery policy under [`tool/test_inventory.mjs`](../../tool/test_inventory.mjs).

## Canonical Node Test Inventory

All Node.js test suites in `tool/` are cataloged in [`tool/test_inventory.mjs`](../../tool/test_inventory.mjs):

| Test Suite | Purpose | Owner / Scope |
|---|---|---|
| `tool/account-deletion-site.test.mjs` | Account deletion browser site, PKCE OAuth, receipt validation | Account deletion web flow |
| `tool/android-lint-gate.test.mjs` | Android release lint configuration, report archiving, blocking gates | Android native release lint |
| `tool/asset-and-test-inventory.test.mjs` | Canonical test and runtime asset discovery and inventory verification | Repository governance |
| `tool/asset-provenance.test.mjs` | Asset provenance, licensing terms, and hash integrity | Asset provenance governance |
| `tool/build-status.test.mjs` | Live build status data model, quartiles, and step estimation | VersionDeck live status |
| `tool/build-status-timeline.test.mjs` | Step grouping, phase extraction, and timeline presentation | VersionDeck timeline UI |
| `tool/build-status-ui.test.mjs` | Live build progress rendering and announcement formatting | VersionDeck accessibility & UI |
| `tool/dependency-security-and-notices.test.mjs` | SPDX 2.3 SBOM, third-party notices, license allowlist | Dependency security |
| `tool/sticky-download-fix.test.mjs` | Sticky download button and responsive footer layout | VersionDeck mobile UX |
| `tool/supabase-advisors.test.mjs` | Security and performance Advisor audit, warning gates | Backend database posture |
| `tool/toolchain.test.mjs` | Canonical toolchain lock, version consistency, environment manifest | Reproducible toolchain |
| `tool/versiondeck.test.mjs` | Manifest generation, APK verification, cache policy, release filtering | VersionDeck distribution |

### Test Inventory Validation Commands

```powershell
# Validate that every *.test.mjs file in tool/ is registered
npm run validate:test-inventory

# Execute all canonical Node test suites
npm run test:all
```

## VersionDeck Runtime Asset Inventory

Every runtime asset required for VersionDeck and the web account-deletion flow is validated by [`tool/validate_versiondeck.mjs`](../../tool/validate_versiondeck.mjs) and precached in [`download-site/sw.js`](../../download-site/sw.js):
- **Core HTML/CSS**: `index.html`, `account-deletion.html`, `styles.css`, `enhancements.css`, `security.css`, `build-status.css`, `build-status-ui.css`, `build-status-timeline.css`, `sticky-download-fix.css`, `account-deletion.css`
- **Core JavaScript**: `app.js`, `build-status.js`, `build-status-ui.js`, `build-status-timeline.js`, `sticky-download-fix.js`, `manifest-schema.js`, `cache-policy.js`, `relative-time.js`, `account-deletion.js`, `account-deletion-config.js`, `sw.js`
- **Manifests and Metadata**: `manifest.webmanifest`, `releases.json`, `asset-manifest.json`, `build-info.json`, `.nojekyll`
- **Branding Assets**: `assets/versiondeck-mark.svg`, `assets/versiondeck-192.png`, `assets/versiondeck-512.png`

## Android Native Splash Generation

The Android native splash resources are generated from [`flutter_native_splash.yaml`](../../flutter_native_splash.yaml). Regenerate them through the repository wrapper, not by invoking `flutter_native_splash:create` directly:

```powershell
dart run tool/generate_native_splash.dart
```

Owntend intentionally uses the same Android 12 splash artwork in light and dark mode. The upstream generator emits byte-identical `drawable-night-*` copies even when no distinct `android_12.image_dark` is configured. Those copies survive Android resource shrinking and add duplicate APK payload. The wrapper runs the upstream generator and then removes only night assets that are byte-for-byte identical to the matching light-density asset. It refuses to prune a night asset if the bytes differ, so adding a real dark splash remains safe.

The generated-output contract is enforced by [`test/android_splash_resource_test.dart`](../../test/android_splash_resource_test.dart). To check the committed resources without regenerating them:

```powershell
dart run tool/generate_native_splash.dart --check
flutter test test/android_splash_resource_test.dart
```

## Flutter and Dart Formatting

All Dart code under `lib/` and `test/` is formatted and verified:
```powershell
dart format --output=none --set-exit-if-changed lib test
```
