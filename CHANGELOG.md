# Changelog

Owntend uses Git history as the authoritative record of shipped changes. This file records notable project-level changes that affect users, operators, contributors, architecture, security, or compatibility.

The current application version is defined only in `pubspec.yaml`. Released versions are recorded below after their version and build numbers have been finalized.

## Unreleased

### Fixed

- Aligned the Supabase device `consumable` field with Flutter's optional descriptive-text contract so normal filter, battery, and cartridge descriptions no longer fail asset creation.
- Preserved item `placement` during the server-authoritative asset-creation RPC.
- Localized built-in categories and pet species at presentation boundaries, corrected Arabic recurrence/reminder/duration grammar across detail and task-card surfaces, and removed English-only relationship fragments from Arabic UI surfaces.
- Added Arabic search aliases for controlled categories, room/item types, power sources, sunlight, and built-in pet/fish values while keeping canonical stored values locale-neutral.

## 1.0.0 (Build 1) — 2026-08-15

### Added

- **Initial Production Baseline**:
  - Full-featured household asset organization, inventory tracking, and maintenance management for Android.
  - Offline-first local persistence via Drift SQLite with schema version 1, foreign keys, write-ahead logging (WAL), and FTS5 full-text search indexing with Unicode support.
  - Authenticated cloud synchronization with Supabase PostgreSQL, Row Level Security (RLS) policies, and table-aware real-time change feed.
  - Multi-factor resilient Google Sign-In authentication with secure session persistence.
  - Fully automated, privacy-compliant account deletion lifecycle with cryptographic recovery tokens and complete media cleanup.
  - Server-authoritative points and monetization engine supporting Google AdMob rewarded ads with server-side verification (SSV), 0-point free asset creation, and task-based point debiting.
  - Contextual notification scheduling, background WorkManager synchronization, exact alarm support, and periodic maintenance reminders.
  - Local backup and restore subsystem with ZIP archive integrity validation, SHA-256 manifest checks, and rollback safety.
  - Complete dual-language internationalization and RTL layout support for English and Arabic.
  - Privacy-preserving Sentry observability with strict PII scrubbing and symbolicated crash reporting.
  - Google Play production release tooling, signed APK pipeline, immutable artifact manifests, and browser-hosted VersionDeck update distribution.
  - Supabase-hosted Edge Functions for account deletion, AdMob SSV callback validation, and secure administrative operations.
  - CI/CD validation for Flutter formatting, static analysis, unit/widget/integration tests, Supabase schema/database tests, Edge Function Deno tests, Android lint, dependency security, asset provenance, and release workflow contracts.

### Security

- Row Level Security is enabled across user-owned cloud tables with explicit least-privilege policies and service-role isolation for internal monetization and synchronization tables.
- Public security-definer entry points are minimized in favor of invoker wrappers around private-schema privileged implementations.
- Production secrets and platform identifiers are validated through explicit build configuration contracts rather than committed runtime credentials.
- Dependency licensing, SBOM generation, third-party notices, asset provenance, and immutable GitHub Actions are enforced by repository validation tooling.
