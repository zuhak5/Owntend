# Canonical toolchain and release evidence

[`config/toolchain.json`](../../config/toolchain.json) is the machine-readable source of truth. Do not copy mutable versions into new scripts or workflows without validating them against that file.

## Canonical matrix

| Component | Pin |
| --- | --- |
| Flutter / Dart | `3.47.0` stable / `^3.13.0` |
| Java / Node / Deno | Temurin `21` / `24` / `2.9.3` |
| Android | compile SDK `37`, target `36`, min `24`, build tools `36.0.0` |
| Gradle / AGP / Kotlin | `9.6.1-bin` with committed SHA-256 / `9.3.0` / `2.4.10` |
| Shorebird | CLI `1.6.119` at exact repository commit; bundled fork `3.47.1`; releases forced to canonical `3.47.0` with exact fork/engine revisions |
| Bundletool / gcloud | `1.18.3` with committed download SHA-256 / `581.0.0` |
| Sentry CLI / Supabase CLI | `2.58.6` / `2.115.0` |

The JSON file, Gradle configuration, lockfiles, and tests hold the complete hashes/revisions.

## Shorebird resolution

[`tool/install_shorebird.ps1`](../../tool/install_shorebird.ps1) creates a local `owntend-pinned` branch at the exact configured commit, validates the CLI's bundled `bin/internal/flutter.version`, bootstraps the CLI, and validates its reported version. The local branch tracks `origin/stable` only so `shorebird doctor` can report upstream freshness; every installer run forcibly returns it to the configured commit. Mutable `latest`, release branches, and an unpinned setup action are not release inputs.

CLI `1.6.119` bundles Shorebird Flutter `3.47.1`, but `3.47.0` remains supported by `shorebird flutter versions list`. [`tool/invoke_shorebird_release.ps1`](../../tool/invoke_shorebird_release.ps1) therefore passes `--flutter-version=3.47.0` from the canonical JSON. Patch builds inherit the selected base release's Flutter revision. A CLI refresh cannot silently upgrade Owntend's release Flutter; changing `releaseFlutterVersion`, its revision, or its engine is a separately reviewed full-release toolchain change.

For release evidence, `SHOREBIRD_HOME` lets [`tool/toolchain_manifest.mjs`](../../tool/toolchain_manifest.mjs) resolve the checkout commit, CLI version, Flutter revision, and cached engine revision. `--require-shorebird` makes missing or different values fatal. Ordinary validation omits that switch so developers do not need Shorebird for normal Flutter work.

[`tool/download_bundletool.ps1`](../../tool/download_bundletool.ps1) accepts the download only when its SHA-256 matches the canonical configuration. The exact tool is used solely to derive VersionDeck APKs from the canonical AAB.

## Resolved evidence

`node tool/toolchain_manifest.mjs --output-directory <dir> --enforce --require-shorebird` emits `resolved-toolchain-manifest.json`. It records technical version/platform values and policy checks, not environment variables, tokens, user data, or private paths. [`tool/collect_android_release_evidence.ps1`](../../tool/collect_android_release_evidence.ps1) hashes that manifest and binds it into production AAB evidence.

Safe validation:

```powershell
npm run test:toolchain
npm run validate:toolchain
node --test tool/shorebird.test.mjs
```

The `--require-shorebird` form additionally requires the exact installed fork and is run by Shorebird release/patch workflows.

## Controlled updates

Update the canonical JSON, installer/download validation, Gradle/lockfiles, action pins, release and patch dry-runs, evidence verifiers, dependency/security notices, documentation, and tests in one change. Reconfirm Shorebird's supported Android requirements, CLI argument behavior, signing protocol, Flutter/engine revisions, Bundletool digest, and gcloud/action releases from official upstream sources. A toolchain, native, asset, or dependency update requires a new Shorebird release; it is never patch-eligible.
