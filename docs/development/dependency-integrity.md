# Dependency Integrity Policy

## Scope

This document covers the Gradle distribution, Dart/Flutter packages, exact
Shorebird/Flutter-engine checkout, Bundletool binary, immutable Actions, Google
Cloud authentication, and Sentry CLI supply-chain surfaces.

## Gradle distribution checksum

`android/gradle/wrapper/gradle-wrapper.properties` contains a
`distributionSha256Sum` for the pinned Gradle binary distribution. The Gradle
wrapper verifies this checksum before the distribution is unpacked. A mismatch
fails the build before Gradle is used.

The current pinned version and checksum:

- Distribution: `gradle-9.6.1-bin.zip`
- SHA-256 (`distributionSha256Sum`):
  `9c0f7faeeb306cb14e4279a3e084ca6b596894089a0638e68a07c945a32c9e14`
- Checksum source: `https://services.gradle.org/distributions/gradle-9.6.1-bin.zip.sha256`
  (retrieved 2026-08-14, cross-referenced with the Gradle 9.6.1 release notes)

The Gradle wrapper JAR (`gradle-wrapper.jar`), `gradlew`, and `gradlew.bat`
are listed in `android/.gitignore` and are injected by the Flutter SDK. The
injected bytes vary between Flutter SDK versions; the distribution checksum is
the stable, SDK-version-independent integrity control. The JAR is not tracked
in version control.

> [!WARNING]
> Never relax `distributionSha256Sum` or use a blanket-permissive trust
> exception for production builds. If the distribution cannot be fetched, that
> is a blocking build failure, not a reason to bypass the check.

## Gradle dependency verification

Gradle artifact verification metadata (`gradle/verification-metadata.xml`) was
evaluated during review. The current project delegates all Android
dependencies to the Google and Maven Central repositories through Flutter's
Gradle plugin infrastructure. Flutter injects plugin dependencies via
`settings.gradle.kts` at build time, and the resolved coordinates change with
Flutter and plugin updates. Generating strict verification metadata for these
injected artifacts creates an unresolvable maintenance burden that would block
every plugin update without providing meaningful security benefit beyond the
distribution checksum already enforced.

The decision to defer artifact-level Gradle verification metadata is recorded
here as a reviewed disposition. It must be reconsidered if:

- Owntend adds direct Gradle dependencies outside the Flutter plugin
  infrastructure.
- The Flutter plugin resolution mechanism changes to a reproducible
  lockfile-compatible form.
- A supply-chain incident targets Gradle artifact repositories used in this
  project.

## Pub lockfile enforcement

`pubspec.lock` is the authoritative resolved package manifest. It must remain
unchanged through every validation, production build, and Sentry publication
step.

All production-relevant pub invocations use `flutter pub get --enforce-lockfile`
(or the equivalent `dart pub get --enforce-lockfile`). This flag fails
immediately if:

- `pubspec.lock` does not exactly satisfy the current `pubspec.yaml` constraints.
- Any hosted package's content hash differs from what was recorded at lock time.

After every enforced `pub get`, the build script checks
`git status --porcelain pubspec.lock` and fails if the file was mutated. This
detects any tool or SDK step that silently updates the lock during the build.

Affected enforcement points:

| Surface | Enforcement |
| --- | --- |
| `validate-flutter.yml` | `--enforce-lockfile` + unchanged check |
| `shorebird-release-android.yml` | `--enforce-lockfile` + unchanged check before the one canonical AAB build |
| `shorebird-patch-android.yml` | `--enforce-lockfile` + unchanged check before dry-run/publication |

Local developer `flutter pub get` does not require the flag. See
[Getting Started](getting-started.md) for the development workflow.

## Updating pub dependencies

To update a dependency:

1. Modify `pubspec.yaml` with the intended version constraint.
2. Run `flutter pub get` (without `--enforce-lockfile`) locally to produce an
   updated `pubspec.lock`.
3. Review the diff to confirm only intended packages changed.
4. Commit both `pubspec.yaml` and `pubspec.lock` together.
5. Run the full standard validation suite to confirm the update is safe:

   ```powershell
   flutter pub get --enforce-lockfile
   dart format --output=none --set-exit-if-changed lib test
   flutter analyze --no-pub
   flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
   ```

6. Open a change and obtain independent review. Never merge
   an unreviewed dependency update.

Do not use `flutter pub upgrade --major-versions` in a production branch without
a full review of breaking changes.

## Shorebird, Bundletool, gcloud, and Actions integrity

[`config/toolchain.json`](../../config/toolchain.json) pins the Shorebird CLI
repository commit, reported CLI version, Flutter revision, engine revision,
Bundletool URL/version/SHA-256, and gcloud version.
[`tool/install_shorebird.ps1`](../../tool/install_shorebird.ps1) uses a detached
exact-commit checkout and validates the revisions; the release evidence
manifest uses `--require-shorebird`. No mutable `latest` setup action is used.
[`tool/download_bundletool.ps1`](../../tool/download_bundletool.ps1) rejects a
download whose SHA-256 differs before it can derive APKs.

Google Cloud authentication uses short-lived GitHub OIDC through exact-commit
`google-github-actions/auth` and `setup-gcloud` references. The repository
action policy allowlists every external action commit and its reviewed release
comment. KMS private keys are non-exportable and no service-account JSON is
stored in GitHub.

A Shorebird, Flutter-engine, Bundletool, gcloud, or action update must refresh
the canonical config, official-source review, tests, workflows, release dry-run,
dependency/notices evidence, and documentation together. It requires a new
base release and is not patch-eligible.

## Sentry CLI integrity

`tool/publish_sentry_release.ps1` invokes the Sentry CLI through `npx` at a
pinned version:

```powershell
$sentryCli = @('--yes', '@sentry/cli@2.58.6')
```

This version is pinned to match the `sentry_dart_plugin` 3.4.0 embedded CLI
version. The `--yes` flag accepts the npx install prompt without interactive
input.

The `npm ci` command that precedes the Sentry publication step installs the
`package-lock.json`-frozen Node dependency tree. This lockfile provides
content-hash integrity for the `@sentry/cli` package and its transitive
dependencies when installed through npm. `npm ci` fails if `package.json`
and `package-lock.json` are inconsistent.

> [!NOTE]
> The Sentry CLI download path (`npx @sentry/cli@2.58.6`) is version-pinned
> but not independently checksum-verified at the binary level beyond what npm's
> content-hash system provides.

## Updating Gradle

To update the Gradle distribution:

1. Change the version in `gradle-wrapper.properties`:
   ```properties
   distributionUrl=https\://services.gradle.org/distributions/gradle-X.Y.Z-bin.zip
   ```
2. Retrieve the official SHA-256 from
   `https://services.gradle.org/distributions/gradle-X.Y.Z-bin.zip.sha256`.
3. Update `distributionSha256Sum` with the retrieved checksum.
4. Update this document with the new version, checksum, and review date.
5. Review the Gradle release notes for breaking changes affecting the Flutter
   Gradle plugin or Owntend build scripts.
6. Run `./gradlew --version` inside the `android/` directory to confirm the
   wrapper accepts the new distribution.
7. Commit the updated properties and documentation together.

## Updating the Sentry CLI pin

To update the Sentry CLI version in `publish_sentry_release.ps1`:

1. Update the `@sentry/cli@X.Y.Z` specifier.
2. Confirm it matches the version embedded by the `sentry_dart_plugin` version
   in `pubspec.yaml`, or document the deliberate divergence.
3. Update this document and `CHANGELOG.md`.

## Validation

Toolchain and dependency integrity tests run with:

```powershell
npm ci
npm run test:all
```
