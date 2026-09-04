# Owntend Documentation

This directory is the canonical entry point for product, architecture, development, operations, governance, and agent-workflow documentation.

## Product

- [`product/feature-catalog.md`](product/feature-catalog.md): user-visible capabilities and product boundaries.
- [`../PRIVACY.md`](../PRIVACY.md): data collection, storage, third parties, retention, and deletion.

## Architecture

- [`architecture/system-overview.md`](architecture/system-overview.md): major components and data flows.
- [`architecture/data-model.md`](architecture/data-model.md): local and cloud data domains.
- [`architecture/sync-protocol.md`](architecture/sync-protocol.md): offline-first synchronization model.
- [`architecture/current-contracts.md`](architecture/current-contracts.md): canonical current data, sync, completion, reminder, security, media, retention, version, and composition contracts.
- [`architecture/auth-and-account-deletion.md`](architecture/auth-and-account-deletion.md): identity and deletion lifecycle.
- [`architecture/monetization.md`](architecture/monetization.md): ads, points, charged creation, and SSV.
- [`architecture/backup-and-restore.md`](architecture/backup-and-restore.md): archive format and restore safety.

## Backend

- [`backend/supabase.md`](backend/supabase.md): local Supabase stack, authentication, RLS, RPCs, Storage, Realtime, Edge Functions, and Advisor audits.
- [`backend/migrations-and-functions.md`](backend/migrations-and-functions.md): migration baseline policy and Edge Function contracts.

## Development

- [`development/getting-started.md`](development/getting-started.md): workstation setup and local execution.
- [`development/toolchain.md`](development/toolchain.md): authoritative canonical toolchain matrix, environment resolution, policy evaluation, and evidence manifest.
- [`development/android-lint.md`](development/android-lint.md): blocking release lint gate, report generation, and evidence binding.
- [`development/test-and-asset-inventory.md`](development/test-and-asset-inventory.md): canonical runtime asset and test inventory discovery.
- [`development/testing.md`](development/testing.md): test strategy and commands.
- [`development/dependency-integrity.md`](development/dependency-integrity.md): Gradle distribution checksum, pub lockfile enforcement, exact Shorebird/Bundletool pins, and Sentry CLI pin.
- [`development/dependency-security-and-notices.md`](development/dependency-security-and-notices.md): dependency review, license matrix, exception registry, SBOM (SPDX 2.3), and third-party notices.
- [`development/localization-and-rtl.md`](development/localization-and-rtl.md): English/Arabic localization and RTL requirements.
- [`development/transient-feedback.md`](development/transient-feedback.md): protected Undo, batching, ordering, accessibility, and layout contracts for transient feedback.

## Operations

- [`operations/release-runbook.md`](operations/release-runbook.md): unified Shorebird AAB release and exact-AAB APK evidence process.
- [`operations/shorebird-code-push.md`](operations/shorebird-code-push.md): account setup, app IDs, GitHub/KMS configuration, safe validation, patching, promotion, and rollback.
- [`operations/google-play-release-runbook.md`](operations/google-play-release-runbook.md): canonical Shorebird AAB evidence and the separately authorized Google Play handoff.
- [`operations/google-play-data-safety-evidence.md`](operations/google-play-data-safety-evidence.md): release-scoped Data safety evidence worksheet and operator-owned gaps.
- [`SENTRY_OPERATIONS.md`](SENTRY_OPERATIONS.md): Sentry configuration and incident workflow.
- [`versiondeck-release-runbook.md`](versiondeck-release-runbook.md): VersionDeck validation and deployment.

## Reference

- [`reference/configuration.md`](reference/configuration.md): configuration sources and secret handling.
- [`reference/routes-and-permissions.md`](reference/routes-and-permissions.md): application routes and Android permissions.

## Governance

- [`governance/documentation-maintenance.md`](governance/documentation-maintenance.md): mandatory same-change documentation policy for humans, AI agents, bots, and Agent Skills.
- [`governance/license-decision.md`](governance/license-decision.md): current licensing decision status.

## Decisions

- [`adr/0001-offline-first-sync.md`](adr/0001-offline-first-sync.md)
- [`adr/ADR-SENTRY-OBSERVABILITY.md`](adr/ADR-SENTRY-OBSERVABILITY.md)
- [`adr/0002-versiondeck-release-verification.md`](adr/0002-versiondeck-release-verification.md)
- [`adr/ADR-SHOREBIRD-CODE-PUSH.md`](adr/ADR-SHOREBIRD-CODE-PUSH.md)

## Agent workflows

- [`agent-skills/README.md`](agent-skills/README.md): proposed skill catalog and installation model.
- [`agent-skills/source-policy.md`](agent-skills/source-policy.md): provenance and pinning rules.
- [`agent-skills/audit-checklist.md`](agent-skills/audit-checklist.md): security and compatibility review.
- [`agent-skills/update-runbook.md`](agent-skills/update-runbook.md): controlled update process.

## Documentation rules

- Implementation, tests, migrations, and configuration remain executable sources of truth.
- Link to mutable values instead of duplicating them where practical.
- Update documents in the same change as the behavior they describe.
- Every AI agent, bot, and automated contributor must perform and report a documentation-impact review under [`governance/documentation-maintenance.md`](governance/documentation-maintenance.md).
- When no documentation change is required, state which documents were reviewed and why they remain accurate.
- Mark planned behavior clearly; do not present a roadmap item as implemented.
- Validate paths and commands before merging documentation changes.
