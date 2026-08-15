# Agent Skill Update Runbook

## Goal

Update external Agent Skills without allowing a moving upstream branch or automated installer to change active repository instructions silently.

## Preconditions

- The current active skill and lock entry are known.
- The upstream source, license, and intended target revision are identified.
- The update is performed on a dedicated branch.
- No automatic updater writes directly into `.agents/skills/`.
- The candidate is reviewed against `AGENTS.md` and `docs/governance/documentation-maintenance.md`.

## Procedure

1. Resolve the new upstream full commit SHA and release/tag.
2. Download the candidate into a temporary or ignored staging directory.
3. Compare every changed `SKILL.md`, reference, script, asset, package file, and license.
4. Review upstream release notes and security advisories.
5. Re-run the complete audit checklist.
6. Verify platform and SDK compatibility with current Owntend dependencies.
7. Apply local patches deliberately; do not overwrite Owntend adaptations wholesale.
8. Recompute content checksums and update provenance metadata.
9. Run structural validation and script tests.
10. Run positive, near-miss, prohibited-action, and composition trigger cases.
11. Exercise the skill on a representative repository task without production access.
12. Verify the skill requires a documentation-impact assessment before editing.
13. Verify the skill requires same-branch documentation updates for changed behavior, commands, triggers, contracts, or invariants.
14. Verify the skill closeout lists documents reviewed, documents changed, reviewed-no-change rationale, and unverified claims.
15. Update Agent Skill governance documentation when commands, triggers, sources, scripts, or invariants change.
16. Open a dedicated pull request showing source revision, diff summary, audit result, documentation impact, tests, and residual risk.
17. Require subsystem-owner approval before merge.

## Documentation compliance gate

Reject or patch an upstream skill when it:

- Treats documentation as optional cleanup.
- Defers required documentation to an unspecified future task.
- Changes code, migrations, configuration, permissions, privacy behavior, workflows, or operations without reviewing the matching Owntend documents.
- Claims completion without listing documentation reviewed or updated.
- Copies mutable versions, ports, fingerprints, routes, or commands into prose without a maintenance strategy.
- Replaces current Owntend documentation with generic framework guidance.

A Owntend adaptation may delegate detailed writing to `owntend-documentation`, but the initiating skill must still ensure the documentation work is completed in the same branch and pull request.

## Review focus by source

### Flutter and Dart

Check minimum SDK versions, generated-code guidance, architecture assumptions, test commands, and whether a setup skill would overwrite existing configuration.

### Supabase and Postgres

Check CLI commands, migration policy, RLS guidance, service-role handling, destructive/linked operations, Edge Function runtime assumptions, and compatibility with Owntend synchronization.

### Google Mobile Ads

Confirm whether guidance targets native Android or Flutter. Preserve current Flutter plugin APIs, consent, test units, SSV, opaque claims, replay protection, and server authority.

### Sentry

Confirm `sentry_flutter` compatibility and preserve Owntend's disabled screenshots, replay, view hierarchy, raw HTTP capture, and strict scrubbing. Treat remote alert/project mutation as an explicit write.

### Android

Install only task-relevant skills. Check AGP/Gradle and Android-version assumptions and prevent Compose/native architecture guidance from replacing Flutter behavior.

## Rollback

If an update causes incorrect selection or unsafe behavior:

1. Disable or remove the new active skill.
2. Restore the previous pinned content and lock entry.
3. Record the failed trigger or workflow case.
4. Add a regression case before attempting another update.
5. Review whether the skill should be forked, split, or replaced with a Owntend-authored skill.
6. Correct any documentation that the faulty skill changed or left stale.

## Cadence

Check for updates monthly, before major framework/backend/SDK upgrades, after relevant security advisories, before major Owntend releases, and after an agent-related near miss.

Do not update solely because upstream `main` changed.
