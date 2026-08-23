# VersionDeck Release Runbook

> **Automated publication pipeline:** When a production `Shorebird Android Release`
> is published on `main`, `Verify Production APK Artifact Set` automatically validates the
> derived ABI APKs and provenance, creates/updates the official GitHub Release with the
> verified ABI APKs and `.sha256` checksum assets, and triggers `Deploy VersionDeck` via
> `workflow_run` in verified mode to generate the signed manifest and publish to GitHub Pages.
> The account-deletion surface is independent of release publication. See the
> [Production containment record](operations/production-containment.md).

## Purpose

VersionDeck is the public static site for verified Owntend APK releases and Owntend's external account-deletion page. The release area is not the build system and does not trust release notes alone; it independently verifies release artifacts before enabling downloads. The account-deletion area is a separate authenticated client of the protected Supabase deletion backend and must not affect release trust.

The authoritative implementation is:

- `download-site/`
- `tool/generate_versiondeck_manifest.mjs`
- `tool/versiondeck-control.json`
- `tool/versiondeck_apk_verifier.mjs`
- `tool/build_account_deletion_site.mjs`
- `tool/build_versiondeck_site.mjs`
- `tool/validate_versiondeck.mjs`
- current `tool/*.test.mjs` VersionDeck tests

The deletion backend authority is [`supabase/functions/delete-account/index.ts`](../supabase/functions/delete-account/index.ts). The static site contains only public configuration and browser code; it never contains service-role credentials.

## Trust model

A release is downloadable only when the pipeline can verify the expected properties from trusted source and artifact evidence, including:

- Release identity and state.
- APK digest.
- Android package/application ID.
- Version name and build number.
- Release/non-debuggable status.
- Signing certificate identity.
- Source/release ancestry where required.
- The unified `Shorebird Android Release` workflow identity and exact current-main source.
- An APK derived from the canonical Shorebird AAB with pinned Bundletool, never an independent Flutter compile.

The published production Shorebird job creates a universal APK and exactly `arm64-v8a`, `armeabi-v7a`, and `x86_64` variants from one AAB. `Verify Production APK Artifact Set` independently rechecks the protected set and provenance, creates the official GitHub Release with the verified ABI APKs and checksums, and triggers `Deploy VersionDeck`. VersionDeck's verifier and manifest schema bind APK and AAB evidence to `.github/workflows/shorebird-release-android.yml`. A validation/dry-run, non-production artifact, patch artifact, missing ABI, changed signer, or different source run is ineligible.

Live build status is informational. It must not grant download trust to an in-progress artifact.

## Account-deletion surface

The account-deletion page uses an explicitly allowlisted configured deployment URL. The current temporary public URL is `https://zuhak5.github.io/Owntend/account-deletion.html`; `https://owntend.app/account-deletion.html` remains an allowlisted future custom-domain URL. Its browser flow uses Google OAuth with PKCE, consumes the callback verifier from `sessionStorage`, and keeps the resulting access token only in the current page's JavaScript memory. A page reload requires a new sign-in, but an unresolved deletion can resume status recovery from the 32-byte recovery key and expected user ID stored for that operation in `sessionStorage`. Destructive controls remain hidden until identity lookup; the page then shows a masked account identity and keeps the delete button disabled until the user selects an explicit permanent-deletion confirmation.

The page creates one 43-character unpadded base64url recovery key with Web Crypto and sends it with the confirmation to `POST /functions/v1/delete-account`. It reports success only after that response or `POST /functions/v1/account-deletion-status` returns `deleted: true`, `status: "deleted"`, and the authenticated/expected user's exact `user_id`. Ambiguous, pending, temporary, malformed, or mismatched results do not become success, and recovery reuses the same key. Redirect completion, Google sign-in, or a generic successful HTTP status is not deletion evidence. The browser page performs remote deletion only; it cannot erase installed-device databases, media, notifications, caches, secure storage, or user-exported backups.

Public configuration is generated during the static build. See [`reference/configuration.md`](reference/configuration.md#public-browser-account-deletion) for the three required configuration variables and their validation rules.

## Publication control

`tool/versiondeck-control.json` is the reviewed authority for:

- The manifest trust-lease duration.
- Whether publication is `active` or explicitly `disabled`.
- The reviewed historical disposition for any release outside current `main`
  ancestry.

The generated manifest must never exceed a 24-hour absolute trust lease. The
runtime and cache policy treat any network-fetched or cached manifest past that
lease as expired and disable downloads until a fresh manifest is revalidated.

In the clean pre-release state, the checked-in control keeps publication disabled
until the first official `1.0.0 (Build 1)` release is signed, verified, and published.

## Pull-request validation

For changes affecting VersionDeck:

1. Check JavaScript syntax for all site modules, tools, and test files.
2. Run all current canonical VersionDeck Node tests:
   ```powershell
   npm run test:all
   ```
3. Build a revisioned static artifact into a temporary directory:
   ```powershell
   $SourceSha = (git rev-parse HEAD).Trim()
   node tool/build_versiondeck_site.mjs `
     --source download-site `
     --output .versiondeck-site `
     --revision $SourceSha `
     --allow-inert-account-deletion-config true
   ```
4. Run `tool/validate_versiondeck.mjs` on the generated artifact:
   ```powershell
   node tool/validate_versiondeck.mjs .versiondeck-site
   ```
5. Review accessibility, reduced motion, responsive behavior, stale/error/offline states, and service-worker changes.

## Manifest rules

- The manifest schema is versioned.
- The manifest publication state is explicit.
- Every manifest carries an absolute `leaseExpiresAt` trust deadline.
- Verified release entries must be deterministic.
- Stable and prerelease selection must be explicit.
- Unknown or invalid fields must not silently enable downloads.
- Failed verification should produce diagnostics without publishing a trusted entry.
- The newest unverified release must not silently cause an older artifact to be represented as that release.
- Historical release decisions must match the release ID, tag, and verified commit SHA exactly.
- Disabled manifests must not advertise an active latest stable or prerelease download.

## Service-worker and cache rules

- Revision all application-shell assets when behavior changes.
- Update the precache list when adding or removing modules or styles.
- Separate shell caching from release-manifest freshness.
- Enforce the manifest's absolute trust lease for both live and cached data.
- Expired, missing, malformed, or unverifiable release metadata must disable or clearly constrain downloads.
- Offline UI must distinguish cached verified release data from live build status.
- Do not cache secrets or API tokens in static assets.
- Treat `account-deletion.html` as a network-only navigation with `cache: "no-store"`. It must not overwrite the cached VersionDeck root and must never fall back to cached `index.html`.
- Keep account-deletion HTML, CSS, JavaScript, and generated public configuration out of the application-shell precache. The build adds a source-revision query to deletion CSS, JavaScript, and configuration URLs.
- When deletion navigation is offline under service-worker control, return the explicit network-required `503` response. Never render the cached release page as if it were the deletion flow.

## Accessibility

Validate:

- Keyboard navigation and visible focus.
- Semantic headings and status announcements.
- Color contrast and non-color state indicators.
- Responsive layout across narrow screens.
- Reduced-motion preferences.
- Clear disabled-download explanations.
- Stable download identity while a new build is active.

## Failure handling

- Fail closed when APK verification is incomplete.
- If artifact verification is failing but operator action must immediately
  disable downloads, keep or switch `tool/versiondeck-control.json` to
  `publication.status = "disabled"` and run the manual disabled publication
  mode. Do not edit `releases.json` by hand.
- Preserve diagnostics for operator review.
- Do not manually edit `releases.json` to force acceptance.
- Do not bypass package, signer, checksum, or ancestry checks.
- Do not expose a token in the public site to obtain richer live status.
- If any required public deletion-site variable is absent or rejected, leave the current live site untouched and correct configuration. Never enable the inert test flag in production.
- If the hosted function, Google callback, CORS contract, or strict receipt check fails, do not describe browser deletion as operational. Retain the in-app method, correct the backend/configuration, and rerun hosted smoke validation.

## Post-deployment checks

- Load the public site in a fresh browser session.
- Confirm the manifest schema and latest stable/prerelease selection.
- Confirm the public manifest publication status and `leaseExpiresAt` value.
- Confirm the download link points to the expected verified artifact.
- Compare displayed version/build/checksum with release evidence.
- Verify stale/offline/error states.
- Verify service-worker update behavior.
- Verify live build status does not replace stable download identity.

### Account-deletion hosted smoke

Use a disposable Google/Supabase account with non-sensitive test rows and private test media. Do not use a personal account, and do not put an access token, OAuth code, email address, user ID, or raw deletion response in logs, screenshots, or retained artifacts.

1. Confirm the deletion-recovery migration and reviewed `delete-account` and `account-deletion-status` function versions are deployed to the intended Supabase project, and that the canonical deletion URL is allowlisted in Supabase Auth redirect configuration.
2. Confirm the required variables documented in [`reference/configuration.md`](reference/configuration.md#public-browser-account-deletion) are set, then record the successful VersionDeck build and deployment revisions.
3. In a fresh browser profile, load the canonical deletion page. It must not show the unavailable-configuration state, and browser developer tools must show revisioned same-origin deletion assets with no service-role value.
4. Verify the production preflight independently:

   ```powershell
   curl.exe --silent --show-error --dump-header - --output NUL --request OPTIONS `
     --header "Origin: https://owntend.app" `
     --header "Access-Control-Request-Method: POST" `
     --header "Access-Control-Request-Headers: authorization,apikey,content-type" `
     "https://qvdccazlbpvsrzkxunxo.supabase.co/functions/v1/delete-account"
   ```

   Expect HTTP `204`, `Access-Control-Allow-Origin: https://owntend.app`, `Vary: Origin`, and the documented methods and headers. Repeat for `/functions/v1/account-deletion-status` with `Access-Control-Request-Headers: apikey,content-type`, then repeat both with an unapproved origin and expect rejection with no allow-origin header. Do not use wildcard expectations.
5. Start Google sign-in and verify the browser returns to the exact canonical callback, removes OAuth parameters from the address bar, shows a generic verified-identity state without displaying an email address, and leaves deletion disabled until the confirmation checkbox is selected.
6. Submit deletion once. Exercise an ambiguous-response/reload recovery where controlled tooling permits, confirm status lookup reuses the original logical-operation key, and confirm the browser reports success only after the strict receipt check. In protected backend tooling, verify the disposable Auth user, owned Postgres rows, and private `user-media` objects are removed. Redact the matching `user_id` and never retain the recovery key.
7. Confirm an installed test client for that deleted account observes a revoked/deleted session and follows local cleanup or recovery. Record this separately: the browser receipt alone cannot prove device-local cleanup.
8. With a VersionDeck service worker already controlling the site, switch the browser offline and reload the deletion URL. Expect the explicit network-required response, never cached release content or a deletion-success state.
