# Documentation Maintenance Policy

## Purpose

Owntend documentation is part of the implementation contract. This policy applies to every contributor, including maintainers, external contributors, AI coding agents, automated agents, bots, and reusable Agent Skills.

A change is not complete when the repository behavior and its documentation disagree.

## Mandatory rule for AI agents

Any AI agent that reads, modifies, reviews, tests, or publishes changes in this repository must perform a documentation-impact review as part of the same task.

The agent must:

1. Read `AGENTS.md` and the relevant documents listed in `docs/README.md` before editing.
2. Identify which documented contracts, commands, diagrams, runbooks, policies, examples, or release notes are affected.
3. Update the affected documentation in the same branch and pull request as the implementation change.
4. Verify documentation claims against current code, tests, migrations, workflows, configuration, and generated behavior.
5. List the documents reviewed and changed in the pull-request description or final work report.
6. When no documentation change is required, state that explicitly and give a concrete reason.

An agent must not defer required documentation to an unspecified follow-up, silently leave stale prose, or claim completion without reporting documentation impact.

## Documentation-impact assessment

Review the following map for every change.

| Change area | Documents to review |
| --- | --- |
| Product behavior, screens, settings, routes, or user flows | `README.md`, `docs/product/feature-catalog.md`, `docs/reference/routes-and-permissions.md`, localization documentation |
| Architecture, service boundaries, providers, repositories, or major data flow | `docs/architecture/system-overview.md` and an ADR when the decision is durable or costly to reverse |
| Drift schema, persistent fields, migrations, indexes, or local settings | `docs/architecture/data-model.md`, migration/testing documentation, backup compatibility documentation |
| Outbox, hydration, realtime, cursors, conflicts, retries, or synchronization authority | `docs/architecture/sync-protocol.md`, data model, relevant ADRs and tests |
| Supabase tables, RLS, Storage, RPCs, Realtime, or Edge Functions | `docs/backend/supabase.md`, `docs/backend/migrations-and-functions.md`, security and privacy documents |
| Authentication, sessions, sign-out, reauthentication, or account deletion | `docs/architecture/auth-and-account-deletion.md`, `PRIVACY.md`, `SECURITY.md` |
| Ads, consent, points, rewards, SSV, or paid/gated behavior | `docs/architecture/monetization.md`, `PRIVACY.md`, backend documentation |
| Backup format, archive contents, restore behavior, or retention | `docs/architecture/backup-and-restore.md`, privacy and compatibility notes |
| Permissions, foreground/background execution, notifications, alarms, location, or new SDKs | `docs/reference/routes-and-permissions.md`, `PRIVACY.md`, development and operations documentation |
| Configuration keys, ports, environment variables, flavors, or secret handling | `docs/reference/configuration.md`, setup documentation, safe example files |
| Sentry collection, scrubbing, sampling, releases, or incident procedure | `docs/SENTRY_OPERATIONS.md`, Sentry ADR, `PRIVACY.md` |
| Android build, signing, checksums, or protected workflows | `docs/operations/release-runbook.md`, `CHANGELOG.md`, security documentation |
| VersionDeck manifests, verification, cache policy, or site build | `docs/versiondeck-release-runbook.md`, VersionDeck ADR |
| Localization, text, date/number formatting, accessibility, or RTL layout | `docs/development/localization-and-rtl.md`, feature and testing documentation |
| Test commands, validation checks, generated files, or contributor workflow | `CONTRIBUTING.md`, `docs/development/testing.md`, `AGENTS.md` |
| Agent Skills, agent scripts, trigger rules, or agent governance | `AGENTS.md`, `docs/agent-skills/`, this policy |
| User-visible or material operational change prepared for release | `CHANGELOG.md` |

The table is a minimum review set, not an exclusion list.

## Same-change requirement

Documentation updates belong in the same branch, commit series, and pull request as the behavior they describe. This allows reviewers and CI to evaluate implementation and documentation together.

A separate follow-up is acceptable only when:

- The user explicitly limits the task to an emergency repair.
- The missing documentation is recorded as a concrete tracked issue.
- The pull request clearly identifies the temporary inconsistency and owner.

AI agents must not create this exception on their own merely to reduce scope.

## Source-of-truth rules

- Executable behavior, tests, migrations, policies, workflows, and configuration take precedence over stale prose.
- Documentation must link to mutable sources instead of duplicating versions, fingerprints, ports, route lists, or command inventories without a maintenance reason.
- Planned behavior must be labeled as planned.
- Security, privacy, compatibility, and operational limitations must not be softened or omitted.
- Historical documents must not be used as current runbooks unless clearly marked.

## Pull-request requirements

Every pull request must contain a documentation-impact statement with one of these outcomes:

- **Updated:** list every document changed and why.
- **Reviewed, no change:** list the documents reviewed and explain why they remain accurate.
- **Temporary exception:** link the tracked follow-up and explain the operational risk.

For AI-authored changes, the final report must also distinguish:

- Documentation verified from repository evidence.
- Documentation that depends on CI, a device, a hosted service, or a protected environment.
- Any claims that remain unverified.

## Review checklist

Before merging:

- Confirm links and referenced paths exist.
- Confirm commands match current scripts and workflows.
- Confirm configuration examples match authoritative configuration.
- Confirm English and Arabic behavior is represented where relevant.
- Confirm privacy and security statements match actual data handling.
- Confirm release and VersionDeck claims preserve fail-closed verification.
- Confirm `CHANGELOG.md` reflects material unreleased changes.
- Confirm superseded instructions are removed, archived, or marked historical.

## Ownership and maintenance

The subsystem owner reviewing a code change also owns the accuracy of the affected documentation. Documentation should be reviewed after material architecture, dependency, permission, privacy, security, release, or workflow changes and before major releases.

When an agent discovers stale documentation outside the immediate task, it must report the discrepancy. It may correct it in the same pull request when the fix is low-risk and directly supported by repository evidence; otherwise it should create or recommend a tracked follow-up without presenting the stale statement as current truth.
