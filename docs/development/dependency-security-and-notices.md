# Dependency Security, License Policy, SBOM, and Notices

## Purpose and Scope

Owntend enforces an automated, auditable supply-chain security and licensing
governance contract for all dependencies across its active ecosystems:

1. **Flutter / Dart packages** (`pubspec.yaml`, `pubspec.lock`)
2. **Node.js tooling and build dependencies** (`package.json`, `package-lock.json`)
3. **Deno / Supabase Edge Function runtimes** (`deno.json`, `deno.lock`)
4. **Android Gradle plugins and wrapper** (`android/build.gradle.kts`, `gradle-wrapper.properties`)

This policy ensures that unreviewed vulnerabilities, copyleft/viral license
obligations, and unverified third-party code cannot enter production releases.

First-party asset and repository licensing decisions are governed separately
in [`docs/governance/license-decision.md`](../governance/license-decision.md).

---

## License Classification Matrix

Every resolved package is categorized into one of three license tiers:

### 1. Allowed Permissive (Standard Approval)

These licenses permit commercial redistribution, modification, and sublicensing
without imposing copyleft obligations on Owntend source code:

- `MIT`
- `Apache-2.0` / `Apache-2.0 WITH LLVM-exception`
- `BSD-2-Clause`
- `BSD-3-Clause`
- `ISC`
- `0BSD`
- `CC0-1.0`
- `Unlicense`
- `Zlib`
- `Python-2.0`
- `Unicode-DFS-2016`

### 2. Conditionally Allowed (File-Scoped Weak Copyleft)

- `MPL-2.0`: Permitted only for independent, unmodified upstream libraries where
  Owntend does not alter the upstream source files.

### 3. Prohibited (Fail-Closed)

These licenses impose viral copyleft, network copyleft, or commercial restrictions
that conflict with Owntend redistribution terms. They are blocked automatically
unless an active, owner-signed exception exists in the exception registry:

- `AGPL-1.0` / `AGPL-3.0` (all variants)
- `GPL-1.0` / `GPL-2.0` / `GPL-3.0` (all variants)
- `LGPL-2.0` / `LGPL-2.1` / `LGPL-3.0` (all variants)
- `SSPL-1.0`
- `Commons-Clause`
- `BUSL-1.1`
- Proprietary, non-commercial, or unstated/unknown licenses

---

## Exception and Waiver Registry

When a technical or platform constraint requires a dependency with an unapproved
or copyleft license (e.g. desktop-only platform plugins), the dependency must be
formally registered in [`tool/dependency-exceptions.json`](../../tool/dependency-exceptions.json).

### Mandatory Exception Fields

```json
{
  "packageName": "dbus",
  "ecosystem": "pub",
  "reason": "Detailed technical rationale explaining why the dependency is needed, how it is isolated, and why it is safe.",
  "approvedBy": "zuhak5",
  "expiresAtUtc": "2027-08-14T00:00:00Z",
  "maxAllowedSeverity": "low"
}
```

### Exception Rules

1. **Named owner sign-off**: `approvedBy` must name a repository administrator.
2. **Hard expiration date**: `expiresAtUtc` must be a valid future ISO-8601 timestamp.
   Expired exceptions immediately fail validation and release builds.
3. **Detailed rationale**: `reason` must exceed 10 characters and explain technical isolation.
4. **No indefinite waivers**: Waivers cannot exceed 12 months without formal re-review.
5. **Stale exception pruning**: Exceptions for removed packages trigger validation warnings.

---

## Vulnerability Triage and Response SLAs

When a security vulnerability is identified in a dependency (via security advisories or automated scanning), the maintainers adhere to the following
response SLAs:

| Severity | Triage SLA | Remediation / Patch SLA | Mitigation Strategy |
| :--- | :--- | :--- | :--- |
| **Critical** (CVSS 9.0–10.0) | 24 hours | 72 hours | Immediate patch or dependency replacement |
| **High** (CVSS 7.0–8.9) | 48 hours | 7 days | Update to patched release or isolate code path |
| **Medium** (CVSS 4.0–6.9) | 7 days | 30 days | Scheduled release update |
| **Low** (CVSS 0.1–3.9) | 14 days | 90 days | Routine dependency maintenance |

---

## Software Bill of Materials (SBOM)

Owntend generates a machine-readable **SPDX 2.3 JSON Software Bill of Materials**
(`sbom.spdx.json`) for every production release attempt via:

```powershell
node tool/generate_sbom_and_notices.mjs --output-directory release/apk-evidence --version-name 1.0.0 --build-number 1
```

### SBOM Specification

- **Standard**: SPDX Version 2.3 JSON (`spdxVersion: "SPDX-2.3"`)
- **Data License**: `CC0-1.0`
- **Scope**: Every resolved package from `pubspec.lock`, `package-lock.json`, and `deno.lock`.
- **Package Identifiers**: Package URL (`purl`) locator standard (e.g. `pkg:pub/drift@2.34.3`).
- **Integrity**: Cryptographic package checksums (`SHA256` for pub, `SHA512` for npm/deno).
- **Binding**: SHA-256 digest of `sbom.spdx.json` is recorded in `release-evidence-summary.json`.

---

## Third-Party Dependency Notices

The generator also produces `THIRD_PARTY_NOTICES.md`, a human-readable attribution document:

- Lists all direct and transitive dependencies by ecosystem with version, license type,
  and upstream registry URL.
- Includes verbatim copies of standard open-source license texts (MIT, Apache-2.0,
  BSD-3-Clause, BSD-2-Clause, ISC, 0BSD).

---

## Local and Verification Commands

```powershell
# Validate all lockfiles against the license and exception policy
npm run validate:dependency-policy

# Run unit tests for policy, SBOM, and notices coverage
npm run test:dependency-security

# Generate release SBOM and Third-Party Notices locally
npm run generate:sbom-and-notices
```
