# ADR 0002: Independently Verify APK Releases Before Public Download

- Status: Accepted
- Date: August 4, 2026

## Context

Release distributions can contain an incorrectly named, unsigned, wrongly signed, debuggable, mismatched, or otherwise invalid APK. Release notes and filenames are assertions, not proof. Owntend needs a public download surface that fails closed when artifact identity cannot be established.

The site also displays live build status, which is useful operational context but is not evidence that an artifact is safe to download.

## Decision

Use VersionDeck as a separately generated static site. Its deployment process independently inspects candidate APKs, verifies release identity and trusted artifact properties, generates a versioned manifest with an explicit publication state and absolute trust lease, builds revisioned static assets, and validates the result.

Download enablement is based on verified artifact data, not live build status or release prose.

Verification includes the applicable package name, version/build, digest, signer identity, release state, source ancestry, and non-debuggable status. The release process must also be able to publish an explicit disabled manifest without successful artifact generation when operator action needs to revoke or contain downloads.

## Consequences

### Positive

- Public downloads fail closed when artifact identity is uncertain.
- Release metadata is derived from inspected artifacts.
- The site can remain static and token-free.
- Live build state can be shown without changing stable-download trust.
- Operators can publish a reviewed disabled state without manufacturing or
  mutating APK artifacts first.

### Negative

- Verification requires Android tools.
- Manifest, service-worker, cache, and verifier changes require coordinated tests.
- A valid release may not appear until independent verification and build finish.

## Required invariants

- Never publish an unverified APK entry.
- Never use a public API token in the site.
- Never let stale or malformed metadata enable downloads.
- Never let network-fetched or cached metadata stay trusted past its absolute
  lease deadline.
- Never replace stable verified identity with an in-progress target version.
- Never bypass signer, package, checksum, or ancestry checks to restore availability.
- Keep generated diagnostics separate from public secrets and credentials.

## Alternatives considered

### Link directly to unverified assets

Rejected because release naming and attachment alone do not prove APK identity.

### Generate download metadata inside the Android build job only

Rejected because independent verification provides an additional trust boundary and prevents build-job assertions from being the sole source.

## References

- `docs/versiondeck-release-runbook.md`
- `tool/versiondeck_apk_verifier.mjs`
- `tool/generate_versiondeck_manifest.mjs`
