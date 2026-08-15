# Sentry Operations

> **Production release publication is contained.** The Sentry-bearing Android
> release process has been disabled since 2026-08-11. Historical Build 44
> evidence is retained, but no new Sentry release mutation is
> authorized. Re-enable only under the owner and prerequisite matrix in the
> [TASK-001 containment record](operations/production-containment.md).

## Purpose

Sentry provides technical crash and performance diagnostics for Owntend when enabled. It must not become a store of user content, direct identifiers, location, credentials, media, or raw application payloads.

The authoritative sources are application configuration, Sentry initialization and scrubber code, tests, `pubspec.yaml`, and `tool/publish_sentry_release.ps1`.

## Privacy baseline

Owntend's intended Sentry configuration must preserve all of the following unless a separately approved privacy decision changes policy:

- No screenshots.
- No session replay.
- No view hierarchy.
- No raw HTTP request or response bodies.
- No authentication tokens, cookies, API keys, or signed URLs.
- No names, email addresses, Google identity payloads, or stable advertising identifiers.
- No room, asset, maintenance, note, warranty, pet, plant, safety, or notification content.
- No precise or approximate location values.
- No local file names or media object paths that contain user data.
- No backup contents or archive paths.

Use allowlisted technical context rather than trying to block an unbounded list after collection.

## Allowed diagnostic context

Examples of acceptable fields when non-identifying:

- Application release and build.
- Environment/flavor.
- Operating-system and device class data supplied safely by the SDK.
- Screen or route identifiers that do not contain entity IDs or names.
- Technical subsystem names.
- Stable error classes and sanitized error codes.
- Synchronization state categories without payloads.
- Boolean feature/configuration state that does not expose consent choices beyond what is operationally necessary.

Review every new tag, context object, breadcrumb, attachment, and exception message.

## Initialization

Sentry is controlled by application configuration. Development and example configurations may disable it or use non-production projects. Initialization should fail safely when disabled or incompletely configured.

Do not log the DSN, auth token, organization/project credentials, or complete configuration object.

## Scrubbing

The event processor/scrubber should:

1. Remove prohibited keys recursively.
2. Sanitize exception text and breadcrumbs while preserving non-identifying technical failure descriptions.
3. Preserve standard `package:*` and `dart:*` stack frame URIs while stripping local developer machine paths.
4. Clear unmapped protocol extension fields rather than dropping valid crash events.
5. Remove URL query strings and signed object paths where present.
6. Drop request bodies and unsafe headers.
7. Remove user objects and direct identifiers.
8. Bound collection sizes.
9. Fail closed when an unknown rich payload cannot be proven safe.

Scrubber tests must include nested maps/lists and representative authentication, synchronization, media, ads, backup, and backend errors.

## Capturing errors

- Prefer typed technical errors with safe codes.
- Add context close to the subsystem boundary, not user-entered values.
- Avoid capturing the same exception repeatedly at multiple layers.
- Distinguish expected offline, cancellation, permission denial, and user-validation states from actionable failures.
- Never attach database files, backups, screenshots, or request dumps.
- Background tasks (WorkManager and foreground services) must initialize Sentry safely via `initializeBackgroundSentry()` so unexpected failures are captured without destabilizing process lifecycles.

## Releases

Production release publication is handled through `tool/publish_sentry_release.ps1`.
The Sentry token must not be available to signing, Supabase, or public client jobs.

The release identifier must correspond to the built application release and source commit. The current protected release format is `app.owntend.mobile@x.y.z+N`, where `N` is also the Sentry `dist`. Release publication should associate commits and upload only the symbol artifacts needed for symbolication without uploading user data or repository secrets.

Current source-backed symbolication expectations:

- Production Flutter builds generate obfuscated Dart symbols with `--split-debug-info=build/sentry-debug/dart`.
- Production Flutter builds also generate `build/sentry-debug/dart/mapping.json` via `--extra-gen-snapshot-options=--save-obfuscation-map=...`, and `pubspec.yaml` points `sentry.dart_symbol_map_path` to that exact file.
- `tool/publish_sentry_release.ps1` uploads Dart debug symbols with `dart run sentry_dart_plugin` and uploads the Android R8 mapping file explicitly with `sentry-cli upload-proguard`.

Do not run production Sentry release mutation as an ordinary local command.
During active containment, do not run release mutation scripts either.

## Edge Functions

Supabase Edge Functions may optionally send technical server-side failures to Sentry when their function environment provides `SENTRY_DSN`. That capture must remain request-scoped and strictly limited:

- Use per-request scopes instead of global scope mutation because Supabase Edge runtimes can be reused across requests.
- Configure `beforeSend` in Edge `Sentry.init` to guarantee request headers, user identities, query parameters, and raw webhook bodies are stripped.
- Capture only server configuration faults, dependency failures, and unexpected backend exceptions.
- Do not capture routine request validation failures such as malformed payloads, missing authorization, duplicate reward callbacks, or expected not-found states.
- Do not attach JWTs, authorization headers, recovery keys, claim IDs, user IDs, raw query strings, or webhook payload bodies.

## Operational triage

When investigating an issue:

1. Confirm environment and release.
2. Inspect sanitized stack trace and technical breadcrumbs.
3. Determine whether the event contains unexpected sensitive data; if so, stop ordinary triage and initiate privacy containment.
4. Reproduce with local or synthetic data.
5. Classify application, backend, configuration, device, or external-service cause.
6. Add regression tests before changing capture volume.
7. Resolve or monitor the issue according to impact.

## Sensitive-data incident

If prohibited data reaches Sentry:

1. Disable or patch the capture path.
2. Assess affected environments, events, and retention.
3. Restrict access and delete affected events or attachments using approved Sentry controls.
4. Rotate any exposed credential.
5. Document the incident and update scrubber tests.
6. Review legal and user-notification obligations.

Do not copy sensitive event content into public issues or messages.

## Alerting

Alerts should use technical conditions such as release regression, crash-free rate, error class, or backend failure category. Avoid alert content that reproduces full event payloads in email, chat, or public systems.

## Change checklist

Any Sentry SDK upgrade or observability change must review configuration defaults, data collection, breadcrumbs, integrations, network capture, screenshots/replay/view hierarchy, sampling, release naming, source/debug artifact handling, tests, `PRIVACY.md`, and this runbook.
