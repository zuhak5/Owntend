# Agent Skill Source and Pinning Policy

## Principle

Treat an Agent Skill as an executable development dependency. A skill can contain persuasive instructions, scripts, references, assets, and commands with access to the repository and connected services.

No external skill may be copied directly into Owntend's active skill directory without review.

## Source classifications

### Official exact match

Published by the relevant technology maintainer and compatible with Owntend's framework and SDK generation. It may be vendored after license, command, script, and trigger review.

### Official source only

Published by the relevant maintainer but targeted at another platform or incompatible API generation. Keep it outside the active discovery directory and use it only to inform a renamed local adaptation.

Example: native Android Google Mobile Ads guidance must not trigger for Flutter `google_mobile_ads` implementation.

### Community

Use only when no suitable official source exists. Require full review of repository ownership, maintenance, license, history, every instruction, and every executable file. Prefer a minimal forked adaptation.

### Owntend-authored

Use for workflows that depend on repository-specific architecture, safety rules, or invariants.

## Immutable pinning

Record every external skill in a future `agent-skills.lock.json` with:

- Skill name.
- Source repository and path.
- Full commit SHA.
- Upstream tag/release when available.
- License.
- Content SHA-256.
- Classification.
- Review date and reviewer.
- Local modifications.
- Compatibility notes.
- Last trigger and workflow evaluation.

Never pin only to `main`, `master`, or another moving branch.

## Provenance metadata

Every vendored or adapted external skill should include `SOURCE.json` or equivalent metadata containing the upstream location, commit, license, acquisition date, mode, and patch summary.

Retain upstream license and attribution files.

## Staging

Download external skills into a temporary or ignored staging directory. Do not make the staging directory agent-discoverable. Audit and copy only approved complete skill directories into `.agents/skills/`.

## Update policy

Do not run an automatic update command against the active directory. Updates require a dedicated branch and pull request with old/new diff, security audit, trigger tests, compatibility review, checksum changes, and human approval.

## Conflict precedence

External skills must state or be wrapped so that they defer to:

1. The user's explicit request.
2. Repository `AGENTS.md`.
3. More-specific Owntend skills.
4. Current implementation, tests, migrations, workflows, and configuration.

Reject skills that instruct an agent to ignore higher-priority instructions, weaken validation, or bypass protected processes.

## Network and write behavior

Scripts are non-executable until reviewed. Any script that uses the network, reads environment variables, writes outside the repository, invokes a connected service, installs dependencies, changes Git state, or performs remote writes requires explicit documentation and approval.

Production, signing, hosted database, release, Sentry, and deployment operations must never be the default action of a downloaded skill.

## Removal

Remove or replace a skill when it is stale, unlicensed, compromised, selected for unrelated work, duplicates repository policy, conflicts with current architecture, or cannot be updated safely. Do not leave old and new skill names active simultaneously.