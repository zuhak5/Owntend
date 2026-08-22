# Development Setup

## Prerequisites

- Flutter 3.47.0 stable or the version currently pinned in [`config/toolchain.json`](../../config/toolchain.json).
- Dart included with Flutter.
- Android SDK and a supported emulator or device.
- PowerShell for repository build scripts.
- Node.js and npm for Supabase tooling.
- Supabase CLI through the pinned npm dependency.
- Git.

Production signing credentials and production configuration are not required for normal development.

## Configuration

Copy a committed example; never commit the resulting real file:

```powershell
Copy-Item config/dev.example.json config/dev.json
```

Fill in only development or local values. Configuration keys and ownership are described in `docs/reference/configuration.md`.

The local Supabase API endpoint must match `supabase/config.toml`. Android emulators cannot use the host loopback address directly; use an emulator-accessible host address when necessary without changing the committed local-port contract.

## Flutter bootstrap

```powershell
flutter doctor
flutter pub get
flutter gen-l10n
dart run build_runner build
```

Run the development flavor with the selected configuration:

```powershell
flutter run --flavor dev --dart-define-from-file=config/dev.json
```

Use the actual flavor and entrypoint conventions already encoded in Gradle and application configuration.

Normal development deliberately does not require `shorebird.yaml`, a Shorebird account, token, or KMS access. The generated file is ignored and the committed `pubspec.yaml` omits it, so ordinary `flutter run` remains usable. Use the disposable-clone setup and validation procedure in [`../operations/shorebird-code-push.md`](../operations/shorebird-code-push.md) only when working on release/code-push operations.

## Local Supabase

Install Node dependencies and start the local stack:

```powershell
npm ci
npx supabase start
```

The committed local configuration uses ports under the `5532x` range. Retrieve the local publishable/anonymous key from the Supabase CLI output and place it only in the ignored development configuration.

Validate the backend:

```powershell
npm run supabase:lint
npm run supabase:test
```

Stop services when finished:

```powershell
npx supabase stop
```

Do not link to or mutate a hosted project as part of ordinary setup.

## Generated source

Regenerate Drift code after schema or DAO changes:

```powershell
dart run build_runner build
```

Regenerate localization after ARB changes:

```powershell
flutter gen-l10n
```

Generated files must remain deterministic and should not be manually edited.

## Standard validation

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
```

Production configuration shape can be tested using the safe example:

```powershell
flutter test --no-pub test/prod_build_config_test.dart `
  --dart-define-from-file=config/prod.example.json `
  --dart-define=VERIFY_PRODUCTION_CONFIG=true
```

## Common boundaries

- Signed-out local behavior and signed-in sync behavior are distinct states.
- Google sign-in requires correctly configured OAuth clients and redirect/package identity.
- Notifications, exact alarms, and background work require device-level testing.
- Sentry and ads should use safe non-production configuration during development.
- Production AABs and derived APKs must come from the protected `Shorebird Android Release` workflow, not ordinary local commands.

## Troubleshooting

When generated code is stale, regenerate before modifying source to compensate. When local Supabase connectivity fails, compare the app URL with `supabase/config.toml`, emulator networking, and CLI status. When tests fail only with real services, isolate whether the failure is configuration, local-service availability, or product behavior before changing tests.
