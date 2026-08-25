# Contributing to Owntend

## Before making changes

1. Read [`AGENTS.md`](AGENTS.md), the relevant documentation under [`docs/`](docs/README.md), and the mandatory [`documentation maintenance policy`](docs/governance/documentation-maintenance.md).
2. Inspect the affected implementation, tests, generated files, migrations, configuration, and documentation.
3. Keep changes narrowly scoped and preserve unrelated work.
4. Never commit credentials, production configuration, signing material, service-role keys, or private user data.
5. Perform a documentation-impact assessment before editing. This requirement applies to humans, AI agents, bots, and automated contributors.

## Local setup

Use Flutter 3.47.0 or the canonical toolchain pinned in [`config/toolchain.json`](config/toolchain.json). Copy an example configuration file:

```powershell
Copy-Item config/dev.example.json config/dev.json
flutter pub get
flutter gen-l10n
dart run build_runner build
```

For local Supabase and repository tooling work:

```powershell
npm ci
npm run validate:test-inventory
npm run test:all
npx supabase start
npm run supabase:lint
npm run supabase:test
```

Use the local ports in `supabase/config.toml`. Real configuration files and Supabase environment files are intentionally ignored.

## Dependency integrity

`pubspec.lock`, `package-lock.json`, and
`android/gradle/wrapper/gradle-wrapper.properties` are integrity-authoritative.

- All production `flutter pub get` invocations must use
  `--enforce-lockfile`. A lockfile mismatch or content-hash change fails before
  any code is compiled.
- The Gradle distribution checksum (`distributionSha256Sum`) in
  `gradle-wrapper.properties` must remain current and must match the official
  SHA-256 published at
  `https://services.gradle.org/distributions/gradle-X.Y.Z-bin.zip.sha256`.
- `npm ci` enforces `package-lock.json` integrity for Node tooling including
  the Sentry CLI used in production release scripts.

To update dependencies, see the procedures in
[`docs/development/dependency-integrity.md`](docs/development/dependency-integrity.md).
Static-source contract tests for these policies run with:

```powershell
npm run test:all
```

## Change requirements

### Flutter and Dart

- Preserve Riverpod and repository boundaries.
- Use GoRouter instead of introducing a second navigation system.
- Add English and Arabic localization for user-visible text.
- Check both left-to-right and right-to-left layouts.
- Do not edit generated Drift or localization output manually.
- Add focused tests for behavior changes.

### Import boundaries

Features must not import other features' internals directly. Shared presentation code lives in `lib/src/ui/components`. Cross-feature import violations fail the boundary contract test `test/feature_boundary_contract_test.dart`.

### Database and synchronization

- Treat local and cloud schema changes as coordinated work.
- Add forward migrations and migration tests.
- Preserve outbox durability, account binding, idempotency, revision handling, conflict recovery, and restart safety.
- Review backup compatibility and account deletion whenever persistent data changes.
- Keep Row Level Security enabled and test cross-user denial.

### Privacy and observability

- Do not log user content, identity data, location, media paths, tokens, or raw request payloads.
- Preserve the Sentry scrubber and disabled screenshot, replay, view-hierarchy, and raw-HTTP capture settings.
- Update `PRIVACY.md` when data collection, storage, transmission, retention, deletion, permissions, advertising, or third-party processing changes.

### Monetization

- Wallet and reward state remain server-authoritative.
- Reward callbacks from the device are not sufficient to credit points.
- Preserve idempotency, server-side verification, consent behavior, and offline failure handling.

### Release and VersionDeck

- Do not run production signing, release publication, hosted database mutation, or public deployment commands without explicit authorization.
- Preserve independent APK verification, package and signer checks, checksums, and fail-closed download behavior.

## Documentation impact

Documentation is part of the change, not a later cleanup task.

- Update affected documents in the same branch and change as the implementation.
- Use the change-to-document matrix in [`docs/governance/documentation-maintenance.md`](docs/governance/documentation-maintenance.md).
- Verify prose against implementation, tests, migrations, and configuration.
- Update `CHANGELOG.md` for user-visible, compatibility, privacy, security, migration, release, or material operational changes.
- Remove, archive, or clearly label superseded instructions.
- Do not duplicate mutable versions, ports, fingerprints, routes, or command inventories without a maintenance reason.

Every contributor must report one documentation outcome:

- **Updated:** list the documents changed and why.
- **Reviewed, no change:** list the documents reviewed and explain why they remain accurate.
- **Temporary exception:** link a tracked follow-up and explain the temporary inconsistency.

AI agents must also list documentation reviewed and changed in their final report and identify any claim that still depends on a device, a hosted service, or a protected environment.

## Validation

Run the narrowest relevant checks, then the standard Flutter suite when Flutter code changed:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
```

Validate production configuration shape with the example file:

```powershell
flutter test --no-pub test/prod_build_config_test.dart `
  --dart-define-from-file=config/prod.example.json `
  --dart-define=VERIFY_PRODUCTION_CONFIG=true
```

Supabase changes require:

```powershell
npm run supabase:lint
npm run supabase:test
```

VersionDeck changes require the JavaScript syntax checks, focused Node tests, static site build, and `tool/validate_versiondeck.mjs`.

Documentation-only changes require link, path, command, and source-of-truth review. Do not claim an automated documentation check ran unless it actually exists and was executed.
