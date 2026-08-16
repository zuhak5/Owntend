# Changelog

Owntend uses Git history as the authoritative record of shipped changes. This file records notable project-level changes that affect users, operators, contributors, architecture, security, or compatibility.

The current application version is defined only in `pubspec.yaml`. Released versions are recorded below after their version and build numbers have been finalized.

## Unreleased

### Fixed

- Aligned the Supabase device `consumable` field with Flutter's optional descriptive-text contract so normal filter, battery, and cartridge descriptions no longer fail asset creation.
- Preserved item `placement` during the server-authoritative asset-creation RPC.
- Centralized built-in category and recurrence presentation, localized built-in pet species, corrected Arabic recurrence/reminder/duration grammar across detail and task-card surfaces, and removed English-only relationship fragments from Arabic UI surfaces.
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
  - First-class Empty Trash bulk purge capability with transactional cascading deletion, photo file unlinking, and UI confirmation.
  - Hardened task recurrence calculation preventing backward next_due_date regression on early completions.
  - Dual-state completion undo handling for both un-synced outbox mutations and synchronized cloud records.
  - Enhanced account deletion data cleaner purging all reconciliation requests and FTS virtual tables.
