# Owntend Agent Skills

## Purpose

Agent Skills provide task-specific reusable workflows. They complement, but do not replace, the always-active repository rules in `AGENTS.md` or detailed architecture in `docs/`.

The intended active project location is `.agents/skills/`. That directory is currently ignored and should not be activated until the source, audit, lock, and validation tooling described here is implemented.

Every active or proposed skill must comply with [`../governance/documentation-maintenance.md`](../governance/documentation-maintenance.md). A skill that changes repository behavior must require a documentation-impact assessment, same-change documentation updates, and an evidence-based documentation closeout.

## Skill layers

1. **Official exact-match skills**: maintained by the relevant technology project and directly compatible with Owntend.
2. **Official source-only skills**: trustworthy upstream guidance that targets another platform or SDK generation and must be adapted.
3. **Audited community skills**: used only when no official source exists and after full review.
4. **Owntend-specific skills**: encode repository architecture, invariants, validation, documentation impact, and protected operations.

## External sources to evaluate

- Flutter official Agent Skills.
- Dart official skills.
- Supabase general and Postgres best-practice skills.
- Android R8 analysis skill.
- Selected Sentry issue-triage skills.
- Google Mobile Ads Android skills as source-only material for a Flutter adaptation.

Do not install every skill from a repository. Select only workflows that match Owntend.

## Owntend-specific catalog

Priority skills:

- `owntend-sync-change`
- `owntend-persistence-migration`
- `owntend-supabase-change`
- `owntend-auth-lifecycle`
- `owntend-monetization-change`
- `owntend-backup-restore`
- `owntend-versiondeck-change`
- `owntend-release-pipeline`
- `owntend-privacy-review`
- `owntend-flutter-feature`
- `owntend-ci-triage`
- `owntend-documentation`

Additional technology-focused adaptations may cover Riverpod, routing, localization/RTL, Google authentication, Sentry Flutter, Android notifications/background work, and location/weather.

## Required skill structure

```text
.agents/skills/<skill-name>/
  SKILL.md
  references/      optional
  scripts/         optional
  assets/          optional
  SOURCE.json      required for vendored or adapted external skills
```

`SKILL.md` frontmatter should contain a unique lowercase hyphenated `name` and a description that states both the workflow and concrete triggering conditions.

## Design rules

- Prefer narrow, composable workflows.
- Keep global safety rules in `AGENTS.md`.
- Keep detailed architecture in `docs/`.
- Use references for large tables and checklists.
- Add scripts only when they provide deterministic value.
- Require an evidence-based closeout report.
- Default production, hosted, signing, release, and destructive operations to planning or local validation only.
- Require the skill to read the documentation maintenance policy before implementation.
- Require a documentation-impact decision before editing.
- Require affected documentation to be updated in the same branch and pull request.
- Require the closeout to list documents reviewed, documents changed, reviewed-no-change rationale, and unverified claims.
- Reject skill instructions that defer required documentation to an unspecified follow-up.

## Required documentation workflow in every skill

Each implementation skill must contain an explicit sequence equivalent to:

1. Identify the affected subsystem and current documentation.
2. Use the matrix in `docs/governance/documentation-maintenance.md`.
3. Update implementation, tests, and documentation together.
4. Update `CHANGELOG.md` when the change is material or user-visible.
5. Validate links, paths, commands, privacy claims, and operational claims.
6. Report documentation impact in the final output.

The skill may delegate detailed documentation authoring to `owntend-documentation`, but the primary skill remains responsible for ensuring that documentation work is completed.

## Installation sequence

1. Implement source policy and lock-file format.
2. Add download-to-staging and audit tooling.
3. Evaluate official Flutter, Dart, Supabase, Postgres, Android, Sentry, and Google Ads sources.
4. Vendor only approved skills at immutable commits.
5. Create Owntend adaptations under new names.
6. Add trigger test cases and structural/security validation.
7. Verify every skill enforces the documentation maintenance policy.
8. Enable `.agents/skills/` in Git only after validation is enforced.
9. Exercise every skill on a real repository task.

## Ownership

Each skill requires a reviewer responsible for its subsystem. Review skills after architecture, dependency, command, workflow, permission, privacy, release, data-contract, or documentation-governance changes and at least before major releases.

See `source-policy.md`, `audit-checklist.md`, and `update-runbook.md`.
