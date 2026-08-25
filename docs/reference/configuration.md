# Configuration Reference

### AdMob application IDs (WP-012 decision D2)

Per-flavor AdMob application IDs are declared as Gradle
`manifestPlaceholders["admobAppId"]` in `android/app/build.gradle.kts`
(Google sample ID for dev/staging; the production ID for prod). These values are
public — they ship inside every APK and `download-site/app-ads.txt` — and the
protected release-evidence tooling independently pins the exact expected
production ID, so a single source of truth is deliberately split into
"build input" and "fail-closed verification expectation".

## Principles

- Commit examples and schemas, not real environment values.
- Keep secrets out of Flutter-distributed configuration whenever possible.
- Treat configuration validation as code and test it.
- Fail closed for production-only requirements.
- Link mutable values to their source instead of duplicating them across documents.

## Flutter configuration

The application reads compile-time values supplied with `--dart-define-from-file`. Committed examples live under `config/`; real `config/*.json` files are ignored.

Current example keys include:

- `APP_ENV`
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `GOOGLE_WEB_CLIENT_ID`
- `ADMOB_TEST_DEVICE_IDS`
- `ADMOB_CONSENT_DEBUG_GEOGRAPHY`
- `SENTRY_ENABLED`
- `SENTRY_DSN`
- `SENTRY_TRACES_SAMPLE_RATE`

Additional production-only keys may be validated by `test/prod_build_config_test.dart` and build scripts. Those sources are authoritative.

A Supabase publishable/anonymous key can be distributed to the client only when RLS and backend authorization are correct. A service-role key must never be included.

## Local Supabase

`supabase/config.toml` defines the local service ports, enabled providers, Storage bucket, Deno function entrypoints, and database major version.

The local API port is `55321` in the committed configuration. Development examples must stay aligned. Android emulators may need a host alias rather than `127.0.0.1`, but the port remains the configured local API port.

Google provider values are read from environment variables by the local Supabase runtime. Keep those values in ignored environment files or the shell environment.

## Android and Gradle

Android application IDs, flavors, build types, signing configuration, and production guards are defined under `android/`. The production application ID is `app.owntend.mobile`; non-production flavors may add suffixes.

Signing material includes keystores, aliases, passwords, expected fingerprints, and `android/key.properties`. It belongs only in protected secret storage and is ignored by Git.

## Shorebird

[`shorebird.yaml.template`](../../shorebird.yaml.template) contains only non-secret placeholders. The three app IDs are repository-level GitHub Variables named `SHOREBIRD_DEV_APP_ID`, `SHOREBIRD_STAGING_APP_ID`, and `SHOREBIRD_PROD_APP_ID`. [`tool/configure_shorebird.ps1`](../../tool/configure_shorebird.ps1) validates and writes ignored `shorebird.yaml`; the generated file must not be committed.

`SHOREBIRD_TOKEN` is an environment Secret, not Flutter configuration. Google Workload Identity and KMS resource names are environment Variables. The non-exportable KMS private key remains in Google Cloud. Android signing values remain environment Secrets. The exact classification, names, kill switches, and setup procedure are in [`../operations/shorebird-code-push.md`](../operations/shorebird-code-push.md).

## Sentry

Client runtime uses enabled state, DSN, environment, release/build, patch number, and sampling configuration. Shorebird release builds retain Dart obfuscation symbols under `build/shorebird-symbols`, the Android R8 mapping, and exact-engine symbol archives. Production Sentry publication additionally requires protected Sentry credentials and remains separately authorized. Do not put Sentry or Shorebird auth tokens in Flutter config.

Supabase Edge Functions may optionally read `SENTRY_DSN` from their hosted function environment for request-scoped server-failure reporting. Keep that value in Supabase secret storage rather than Flutter config, static assets, or committed examples.

## Google services and ads

Google sign-in uses OAuth client identifiers appropriate to Android and backend token exchange. Google Mobile Ads uses the Android application ID in the manifest and ad-unit/configuration values through the monetization implementation.

AdMob-specific compile-time keys are:

- `ADMOB_TEST_DEVICE_IDS`: optional comma-separated test-device identifiers for development or staging only. Production validation fails closed if this key is non-empty.
- `ADMOB_CONSENT_DEBUG_GEOGRAPHY`: optional UMP debug geography (`eea`, `regulated_us_state`, or `other`) for development or staging only. Production validation fails closed if this key is set.

These keys are intended only for operator-controlled debug builds. Keep them empty in production examples and protected production configuration.

## VersionDeck

VersionDeck static assets contain no private token.

### Public browser account deletion

The VersionDeck build generates `account-deletion-config.js` from three public configuration variables:

| Variable | Required production value | Exposure and validation |
| --- | --- | --- |
| `PUBLIC_SUPABASE_URL` | `https://qvdccazlbpvsrzkxunxo.supabase.co` | Public project URL. Any other URL is rejected. |
| `PUBLIC_SUPABASE_PUBLISHABLE_KEY` | The hosted project's public publishable key or anonymous-role JWT | Intentionally browser-distributed. It must validate as a public `sb_publishable_...` key or an anonymous-role JWT; a privileged key is rejected because it does not satisfy that shape. Never substitute a service-role credential. |
| `ACCOUNT_DELETION_SITE_URL` | `https://owntend.app/account-deletion.html` | Exact Google OAuth callback and canonical public page. Any other URL is rejected. |

[`tool/build_account_deletion_site.mjs`](../../tool/build_account_deletion_site.mjs) is authoritative for this schema and its fixed endpoints. [`tool/build_versiondeck_site.mjs`](../../tool/build_versiondeck_site.mjs) validates the configuration before replacing or emitting the site output, writes only the known public fields, and includes the generated file in the hashed asset inventory. There is no production fallback: missing, empty, malformed, disabled, or mismatched values fail the build.

Validation passes `--allow-inert-account-deletion-config true` explicitly for test environments. That mode generates a fixed disabled `example.invalid` configuration so static markup and browser logic can be tested without production values. It must not be used by the production deployment step. The page itself also validates the generated object and remains disabled if configuration is absent or invalid.

The publishable key is not a secret and is protected by RLS, authenticated Edge Function checks, and server-held service-role credentials rather than concealment. Nevertheless, do not print the real value unnecessarily in test evidence, and never place a service-role key in static assets, Flutter configuration, or committed examples.

## Validation

Safe production-shape validation:

```powershell
flutter test --no-pub test/prod_build_config_test.dart `
  --dart-define-from-file=config/prod.example.json `
  --dart-define=VERIFY_PRODUCTION_CONFIG=true
```

This does not validate real credentials or signing identity.

## Change checklist

When adding a key:

1. Define its owner and environment scope.
2. Decide whether it is safe to distribute.
3. Add a committed placeholder example.
4. Add validation and a useful failure message.
5. Update privacy and operations docs if data or third-party behavior changes.
6. Remove obsolete keys after backward-compatible rollout.
7. Verify `.gitignore` still protects real values.
