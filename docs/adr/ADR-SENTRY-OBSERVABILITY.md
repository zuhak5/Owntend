# ADR: Privacy-Preserving Sentry Observability

- Status: Accepted
- Date: August 4, 2026

## Context

Owntend needs crash and performance diagnostics across Flutter, Android, synchronization, authentication, backup, monetization, and release behavior. The application also handles sensitive household content, identity/session information, media, location-dependent features, and backup files.

Default or expansive telemetry collection could expose data that is unnecessary for diagnosis.

## Decision

Use `sentry_flutter` for opt-in/configuration-controlled technical diagnostics with a strict privacy baseline:

- Apply recursive event scrubbing and allowlisted technical context.
- Do not set user identity from account names or email addresses.
- Disable screenshots.
- Disable session replay.
- Disable view hierarchy.
- Do not capture raw HTTP request/response bodies.
- Do not attach database, backup, media, or log files.
- Keep route names and subsystem context free of entity identifiers and user content.
- Associate production events with a published release.

Production release mutation is performed through controlled scripts rather than ordinary local development commands.

## Consequences

### Positive

- Technical regressions can be diagnosed by release and subsystem.
- Privacy exposure is reduced compared with broad default capture.
- Release publication and source association remain reproducible.

### Negative

- Some issues are harder to diagnose without rich payloads or screenshots.
- The scrubber and every new integration require tests and ongoing review.
- Operators must reproduce issues using synthetic or local data.

## Required controls

- Scrubber tests for nested authentication, synchronization, media, ads, backup, and backend errors.
- No credentials or direct identifiers in tags, breadcrumbs, exception messages, or contexts.
- Immediate containment if prohibited data reaches Sentry.
- Review after every SDK upgrade or new Sentry integration.
- Documentation and privacy updates for material telemetry changes.

## Alternatives considered

### Full default SDK capture

Rejected because it may collect more context than is necessary and compatible with Owntend's privacy goals.

### No remote observability

Rejected because production-only crashes, release regressions, and device-specific failures would be substantially harder to diagnose.

## References

- `docs/SENTRY_OPERATIONS.md`
- `PRIVACY.md`
- Sentry initialization and scrubber tests
- `tool/publish_sentry_release.ps1`