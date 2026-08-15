# Canonical Toolchain Specification and Evidence Manifest

## Overview

To guarantee deterministic, reproducible, and verifiable builds across development, CI validation, standalone Android APK releases, Google Play Android App Bundle (AAB) releases, and VersionDeck verification, Owntend defines a single authoritative machine-readable toolchain configuration in [`config/toolchain.json`](../../config/toolchain.json).

Prior to this specification, different release rails exhibited toolchain drift (for example, workflow Flutter pins and the Android compile SDK diverged from the canonical configuration). This specification eliminates floating selectors, aligns all rails to exact canonical versions, and enforces resolved toolchain policy checks during evidence collection.

## Canonical Toolchain Matrix

The canonical toolchain definition in [`config/toolchain.json`](../../config/toolchain.json) defines exact versions for every layer of the build stack:

| Component | Canonical Version / Spec | Configuration Source |
|---|---|---|
| **Flutter SDK** | `3.47.0` (channel: `stable`) | [`config/toolchain.json`](../../config/toolchain.json), [`pubspec.yaml`](../../pubspec.yaml) (`>=3.47.0`) |
| **Dart SDK** | `^3.13.0` | [`config/toolchain.json`](../../config/toolchain.json), [`pubspec.yaml`](../../pubspec.yaml) |
| **Java Development Kit (JDK)** | `17` (distribution: `temurin`) | [`config/toolchain.json`](../../config/toolchain.json), [`android/app/build.gradle.kts`](../../android/app/build.gradle.kts) (`JavaVersion.VERSION_17`) |
| **Node.js** | `24` | [`config/toolchain.json`](../../config/toolchain.json), [`package.json`](../../package.json) |
| **Deno** | `2.9.3` | [`config/toolchain.json`](../../config/toolchain.json) |
| **Android Compile SDK** | `37` | [`config/toolchain.json`](../../config/toolchain.json), [`android/app/build.gradle.kts`](../../android/app/build.gradle.kts) |
| **Android Target SDK** | `36` | [`config/toolchain.json`](../../config/toolchain.json), [`android/app/build.gradle.kts`](../../android/app/build.gradle.kts) |
| **Android Min SDK** | `24` | [`config/toolchain.json`](../../config/toolchain.json), [`android/app/build.gradle.kts`](../../android/app/build.gradle.kts) |
| **Android Build Tools** | `36.0.0` | [`config/toolchain.json`](../../config/toolchain.json) |
| **Android Gradle Plugin (AGP)** | `9.3.0` | [`config/toolchain.json`](../../config/toolchain.json), [`android/settings.gradle.kts`](../../android/settings.gradle.kts) |
| **Kotlin Plugin** | `2.4.10` | [`config/toolchain.json`](../../config/toolchain.json), [`android/settings.gradle.kts`](../../android/settings.gradle.kts) |
| **Gradle Distribution** | `9.6.1-bin` | [`config/toolchain.json`](../../config/toolchain.json), [`android/gradle/wrapper/gradle-wrapper.properties`](../../android/gradle/wrapper/gradle-wrapper.properties) |
| **Gradle Wrapper SHA-256** | `9c0f7faeeb306cb14e4279a3e084ca6b596894089a0638e68a07c945a32c9e14` | [`config/toolchain.json`](../../config/toolchain.json), [`android/gradle/wrapper/gradle-wrapper.properties`](../../android/gradle/wrapper/gradle-wrapper.properties) |
| **Sentry CLI** | `2.58.6` | [`config/toolchain.json`](../../config/toolchain.json), [`package.json`](../../package.json) |
| **Supabase CLI** | `2.114.0` | [`config/toolchain.json`](../../config/toolchain.json), [`package.json`](../../package.json) |

## Resolved Toolchain Manifest (`resolved-toolchain-manifest.json`)

During release artifact packaging and CI validation, [`tool/toolchain_manifest.mjs`](../../tool/toolchain_manifest.mjs) collects the exact runtime environment and compares resolved tool versions against canonical policy.

### Manifest Structure

```json
{
  "schemaVersion": 1,
  "generatedAtUtc": "2026-08-14T01:25:04.000Z",
  "sourceSha": "0123456789abcdef0123456789abcdef01234567",
  "canonicalToolchain": { ... },
  "resolvedToolchain": {
    "runner": {
      "platform": "win32",
      "release": "10.0.26100",
      "arch": "x64",
      "type": "Windows_NT"
    },
    "flutter": {
      "version": "3.47.0",
      "channel": "stable"
    },
    "dart": {
      "version": "3.13.0"
    },
    "java": {
      "version": "17.0.14"
    },
    "node": {
      "version": "24.11.1",
      "npmVersion": "11.1.0"
    },
    "deno": {
      "version": "2.9.3"
    },
    "android": {
      "compileSdkVersion": 37,
      "targetSdkVersion": 36,
      "agpVersion": "9.3.0",
      "kotlinVersion": "2.4.10",
      "gradleDistribution": "9.6.1-bin",
      "gradleDistributionSha256": "9c0f7faeeb306cb14e4279a3e084ca6b596894089a0638e68a07c945a32c9e14"
    }
  },
  "policyEvaluation": {
    "status": "PASS",
    "checks": [
      { "name": "Android Gradle Plugin (AGP)", "expected": "9.3.0", "actual": "9.3.0", "pass": true },
      { "name": "Kotlin Plugin", "expected": "2.4.10", "actual": "2.4.10", "pass": true },
      { "name": "Gradle Distribution", "expected": "9.6.1-bin", "actual": "9.6.1-bin", "pass": true },
      { "name": "Gradle Distribution SHA-256", "expected": "9c0f...", "actual": "9c0f...", "pass": true },
      { "name": "Android compileSdk", "expected": 37, "actual": 37, "pass": true },
      { "name": "Android targetSdk", "expected": 36, "actual": 36, "pass": true },
      { "name": "Node.js Version", "expected": "^24", "actual": "24.11.1", "pass": true }
    ],
    "errors": []
  }
}
```

### Privacy and Redaction Constraints

- No secrets, auth tokens, API keys, or private signing credentials are ever collected or stored in the manifest.
- Absolute paths are sanitized to replace user profile directories (`%USERPROFILE%` / `~/`) and normalize path separators.
- Environment variables are excluded from the manifest.

## Evidence Binding and Validation

The release evidence collector script [`tool/collect_android_release_evidence.ps1`](../../tool/collect_android_release_evidence.ps1):
1. Runs `node tool/toolchain_manifest.mjs --output-directory <dir> --enforce`.
2. Computes the SHA-256 hash of `resolved-toolchain-manifest.json`.
3. Records `toolchain_manifest_file`, `toolchain_manifest_sha256`, and `toolchain_policy_verified: true` in `release-evidence-summary.json`.
4. Attaches the manifest to the immutable release evidence archive (`Owntend-production-apk-provenance-*` / `Owntend-production-aab-evidence-*`).

## Verification Commands

```powershell
# Run toolchain unit tests
npm run test:toolchain

# Run toolchain policy evaluation in enforcing mode
npm run validate:toolchain
```

## Controlled Toolchain Update Workflow

To update any toolchain component:
1. Open a dedicated change modifying [`config/toolchain.json`](../../config/toolchain.json) with updated versions and reviewer metadata.
2. Synchronize all associated lockfiles and repository configs (`pubspec.yaml`, `android/build.gradle.kts`, `android/settings.gradle.kts`, `android/gradle/wrapper/gradle-wrapper.properties`).
3. Run `npm run test:toolchain` and `npm run validate:toolchain`.
