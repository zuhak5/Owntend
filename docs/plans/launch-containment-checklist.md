# Launch containment checklist (execute ONLY at launch authorization)

WP-019. This file is staged documentation; none of these steps run during
pre-launch hardening. Every item requires the operator authorization recorded
in `docs/operations/production-containment.md`.

## 1. Flip the lifecycle marker

- [ ] Change the `AGENTS.md` lifecycle checkbox from `[ ]` to `[x]`.
  - This arms the guard in `deploy-supabase-migrations.yml` whose preflight
    greps `AGENTS.md` for the unchecked box.

## 2. Remove the pre-launch reset footgun

- [ ] Delete the `reset-prelaunch-database` job from
      `.github/workflows/deploy-supabase-migrations.yml`
      (`supabase db reset --linked` must never exist post-launch).

## 3. Supabase

- [ ] From here on, schema changes are forward migrations only; the single
      `20260821124930_initial_schema.sql` baseline becomes immutable history.
- [ ] Run hosted advisors and record results.

## 4. Drift upgrade machinery

- [ ] At the first post-launch schema change: bump `currentSchemaVersion`, add
      `onUpgrade` from the shipped v1, add fixture coverage for every shipped
      version (`docs/architecture/data-model.md` trigger section), and
      coordinate with the backup container format.

## 5. VersionDeck

- [ ] After an authorized production Shorebird publication succeeds, confirm
      `Verify Production APK Artifact Set` validates the APK set and that its
      successful `workflow_run` triggers `Deploy VersionDeck`. That downstream
      run selects the `verified` workflow input and generates an active manifest
      from `tool/versiondeck-control.json`; the control file itself has no
      publication-mode field.
- [ ] Do not manually dispatch `verified` publication as a containment or
      artifact-verification bypass. Use the documented disabled-publication
      procedure when downloads must remain contained.
- [ ] Confirm repository identity (`zuhak5/Owntend`) and domain
      (`owntend.app`) are still correct before enabling.

## 6. External evidence gates (per SECURITY.md)

- [ ] Physical-device matrix: notifications across reboot/timezone, Google
      sign-in round trip, real ad serving + SSV settlement, encrypted backup
      restore on hardware, min-spec memory benchmark.
- [ ] Play Data safety rows completed in
      `docs/operations/google-play-data-safety-evidence.md`.
- [ ] Containment lift recorded in `production-containment.md`.
