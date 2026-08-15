# Security Policy

## Active production containment

Production release, signing, Sentry, Supabase mutation/advisor, Play AAB, and
VersionDeck publication rails were paused on 2026-08-11. The redacted
evidence, action ledger, limits, and re-enable owners are recorded in
[`docs/operations/production-containment.md`](docs/operations/production-containment.md).
Do not treat source or historical release evidence as authorization to
lift containment.

## Reporting a vulnerability

Do not report security vulnerabilities in public issues, discussions, screenshots, or release notes.

Contact the repository maintainer privately through verified security channels. Include the affected component, reproduction steps, expected impact, and any evidence that can be shared safely.

Do not include production secrets, private user data, access tokens, signing files, or complete exploit payloads in an initial report.

## Response expectations and vulnerability SLAs

The maintainer attempts to respond to and remediate reported vulnerabilities according to the following service-level targets:

| Severity | Triage Target | Remediation Target | Action |
| :--- | :--- | :--- | :--- |
| **Critical** (CVSS 9.0–10.0) | 24 hours | 72 hours | Immediate emergency patch or rollback |
| **High** (CVSS 7.0–8.9) | 48 hours | 7 days | Expedited fix and release |
| **Medium** (CVSS 4.0–6.9) | 7 days | 30 days | Scheduled release cycle fix |
| **Low** (CVSS 0.1–3.9) | 14 days | 90 days | Routine maintenance |

## Dependency security and license governance

Dependencies across all ecosystems (Dart/Flutter, Node.js, Deno/Edge Functions, Gradle) are governed by the [Dependency Security and License Policy](docs/development/dependency-security-and-notices.md):

- Automated gates (`npm run validate:dependency-policy` and `npm run test:dependency-security`) block unreviewed vulnerabilities and prohibited copyleft licenses.
- Time-bounded, owner-approved waivers are recorded in `tool/dependency-exceptions.json`; unowned or expired exceptions fail closed.
- Production releases generate and archive an SPDX 2.3 JSON Software Bill of Materials (`sbom.spdx.json`) and Third-Party Notices (`THIRD_PARTY_NOTICES.md`).

## Security-sensitive areas

Changes in these areas require elevated review:

- Supabase migrations, Row Level Security, RPCs, Storage policies, and Edge Functions.
- Google authentication, session storage, account binding, sign-out, and account deletion.
- Offline synchronization, conflict recovery, maintenance-completion idempotency, and media cleanup.
- AdMob server-side verification, reward claims, point balances, and charged creation.
- Backup archive parsing, restore staging, schema compatibility, and rollback. All backup imports enforce strict preallocation resource budgets before live mutation: 256 MiB compressed limit (`_maxBackupBytes`), 512 MiB total expanded limit (`_maxExtractedBytes`), 256 MiB single entry limit (`_maxSingleEntryBytes`), 10,000 maximum entry count (`_maxEntryCount`), 20x maximum compression ratio (`_maxCompressionRatio`), and streaming declared-vs-actual byte size validation.
- Sentry initialization, scrubbing, event processors, release publication, and telemetry fields.
- Android permissions, exact alarms, foreground services, boot receivers, and location.
- Production configuration, Android signing, APK verification, and VersionDeck.

## Secret handling

Never commit:

- Real files under `config/*.json` other than committed examples.
- `.env` files or `supabase/.env`.
- Supabase service-role credentials.
- Google OAuth secrets.
- Sentry authentication tokens.
- Android keystores, signing passwords, or `android/key.properties`.
- Private user content or production database exports.

If a secret is committed, remove it from active use immediately, rotate it, assess exposure, and then clean repository history when appropriate. Deleting the file in a later commit is not sufficient.

## Supported version

Security fixes target the current `main` branch and the most recent published Android release unless the maintainer states otherwise. Version information is authoritative in `pubspec.yaml`.

## Safe testing

Use local or dedicated non-production environments. Do not test destructive behavior against production accounts, hosted databases, public Storage objects, signing infrastructure, Sentry projects, or release processes without explicit authorization.
