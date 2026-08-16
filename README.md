# Owntend

Owntend is an Android-first Flutter application for organizing household assets and keeping maintenance work on schedule. It combines an offline-first Drift database with authenticated Supabase synchronization, reminders, backup and restore, statistics, Google sign-in, privacy-preserving Sentry observability, and an independently verified APK download site named VersionDeck.

## Current stack

- Flutter 3.47.0 and Dart 3.13 ([canonical toolchain](config/toolchain.json))
- Riverpod and GoRouter
- Drift and SQLite
- Supabase Auth, Postgres, Storage, Realtime, RPCs, and Edge Functions
- Google sign-in and Google Mobile Ads
- Sentry Flutter
- Flutter local notifications, foreground tasks, Workmanager, and coarse location
- PowerShell release tooling, Node.js, and static site hosting

The authoritative dependency and SDK versions are in [`pubspec.yaml`](pubspec.yaml), [`package.json`](package.json), and [`config/toolchain.json`](config/toolchain.json).

## Product capabilities

Owntend manages areas, rooms, categories, assets, tags, photos, maintenance plans and history, calendar views, health and readiness summaries, warranty alerts, notifications, search, statistics, settings, cloud accounts, and encrypted-platform storage for sensitive session material. The app supports English and Arabic, including right-to-left layout.

See [`docs/product/feature-catalog.md`](docs/product/feature-catalog.md) for the complete product map.

## Repository map

```text
android/                 Android host, manifests, flavors, signing guards
assets/                  App images, illustrations, audio, and fonts
config/                  Safe configuration examples; real configs are ignored
download-site/           VersionDeck static download site
integration_test/        Flutter integration tests
lib/                     Flutter application and generated localization
supabase/                Local Supabase config, migrations, tests, functions
test/                    Flutter unit and widget tests
tool/                    Build, release, validation, and VersionDeck scripts
docs/                    Product, architecture, development, and operations docs
```

## Getting started

Read [`docs/development/getting-started.md`](docs/development/getting-started.md). The standard local sequence is:

```powershell
flutter pub get
flutter gen-l10n
dart run build_runner build
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
```

Local Supabase development requires the Supabase CLI and the ports declared in [`supabase/config.toml`](supabase/config.toml). Copy an example configuration file instead of committing secrets.

## Documentation

Start at [`docs/README.md`](docs/README.md). Particularly important documents are:

- [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md)
- [`docs/architecture/sync-protocol.md`](docs/architecture/sync-protocol.md)
- [`docs/development/testing.md`](docs/development/testing.md)
- [`docs/SENTRY_OPERATIONS.md`](docs/SENTRY_OPERATIONS.md)
- [`docs/versiondeck-release-runbook.md`](docs/versiondeck-release-runbook.md)
- [`docs/governance/documentation-maintenance.md`](docs/governance/documentation-maintenance.md)
- [`PRIVACY.md`](PRIVACY.md)
- [`AGENTS.md`](AGENTS.md)

Documentation is part of the implementation contract. Humans, AI agents, bots, and Agent Skills must review and update affected documents in the same change as the behavior they describe.

## Production releases

Production publication remains under scoped containment. Exact-main signed APK
and AAB evidence builds may run, but they do not authorize Sentry release
mutation, GitHub Release/tag publication, Google Play upload or rollout, hosted
backend mutation, or verified VersionDeck downloads. Historical releases remain
preserved. See the
[`TASK-001 containment record`](docs/operations/production-containment.md).

Production Android evidence builds validate production configuration, signing
identity, package metadata, APK debuggability, checksums, tests, and provenance.
Sentry runtime ingestion may use the public DSN, but Sentry release mutation
remains a separate contained operation.

See [`docs/operations/release-runbook.md`](docs/operations/release-runbook.md).

## Contributing and security

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and the [`documentation maintenance policy`](docs/governance/documentation-maintenance.md) before changing the project. Report vulnerabilities according to [`SECURITY.md`](SECURITY.md).

## License and Asset Provenance

Owntend source code is licensed under the [MIT License](LICENSE). Third-party notices and trademark disclosures are detailed in [NOTICE](NOTICE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Asset provenance, rights, and font/audio redistribution terms are cataloged in [`config/asset_provenance.json`](config/asset_provenance.json). See [`docs/governance/license-decision.md`](docs/governance/license-decision.md) for governance details.
