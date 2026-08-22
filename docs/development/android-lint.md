# Android Release Lint Gate

## Overview

Android Lint provides static analysis for Android-specific bugs, correctness issues, accessibility problems, performance bottlenecks, security vulnerabilities, and internationalization defects.

Prior to remediation, `checkReleaseBuilds = false` was set in [`android/app/build.gradle.kts`](../../android/app/build.gradle.kts), which disabled the Android Gradle Plugin's built-in release lint verification. This created a blind spot where Flutter static analysis (`flutter analyze`) and custom regex contracts could not detect native Android manifest, permission, lifecycle, or bytecode issues.

Release lint is fully enabled, configured as a blocking gate with `abortOnError = true`, and emits comprehensive machine-readable and human-readable reports.

## Configuration Contract

In [`android/app/build.gradle.kts`](../../android/app/build.gradle.kts):

```kotlin
android {
    ...
    lint {
        checkReleaseBuilds = true
        abortOnError = true
        checkAllWarnings = true
        warningsAsErrors = false
        ignoreTestSources = true
        htmlReport = true
        xmlReport = true
        sarifReport = true
        textReport = true
        htmlOutput = file("build/reports/lint-results-prodRelease.html")
        xmlOutput = file("build/reports/lint-results-prodRelease.xml")
        sarifOutput = file("build/reports/lint-results-prodRelease.sarif")
        textOutput = file("build/reports/lint-results-prodRelease.txt")
    }
}
```

### Key Properties

1. **`checkReleaseBuilds = true`**: Re-enables the automatic `lintVital<Variant>` task during release APK (`assembleProdRelease`) and release AAB (`bundleProdRelease`) builds.
2. **`abortOnError = true`**: Fails the Gradle build immediately if any fatal/error-level lint issue is detected.
3. **`checkAllWarnings = true`**: Enables comprehensive inspection across all available warning categories.
4. **`ignoreTestSources = true`**: Focuses release lint analysis strictly on production application code and resources.
5. **Report Generation**: Emits HTML (`lint-results-prodRelease.html`), XML (`lint-results-prodRelease.xml`), SARIF (`lint-results-prodRelease.sarif`), and TXT (`lint-results-prodRelease.txt`) formats into `build/reports/`.

## Evidence Collection and Binding

During release packaging via [`tool/collect_android_release_evidence.ps1`](../../tool/collect_android_release_evidence.ps1):
1. Discovers the generated `lint-results-prodRelease.html` and `lint-results-prodRelease.xml` reports.
2. Copies reports into the release evidence directory (`release/apk-evidence/` / `release/aab-evidence/`).
3. Computes the SHA-256 hash of each report.
4. Records `lint_html_report_file`, `lint_html_report_sha256`, `lint_xml_report_file`, `lint_xml_report_sha256`, and `android_lint_verified: true` in `release-evidence-summary.json`.
5. Uploads the reports as part of the immutable release evidence and provenance archives.

## Automated Verification

The test suite in [`tool/android-lint-gate.test.mjs`](../../tool/android-lint-gate.test.mjs) guarantees that:
- `android/app/build.gradle.kts` specifies `checkReleaseBuilds = true` and `abortOnError = true`.
- Permissive or disabled lint blocks are detected and rejected.
- Evidence collection scripts bind lint report hashes to the release summary.
- Production build scripts execute release builds without suppressing lint failures.

Run the test suite locally:
```powershell
npm run test:android-lint
```
