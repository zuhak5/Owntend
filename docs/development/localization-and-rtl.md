# Localization and Right-to-Left Layout

## Supported locales

Owntend currently supports English and Arabic. The ARB source files under `lib/l10n/` and `l10n.yaml` are authoritative. Generated localization Dart files are outputs and must not be edited manually.

The process splash appears before the full `MaterialApp`, so it performs a deliberately small device-locale selection: Arabic uses Arabic text/direction and every other device locale falls back to English. Its tagline, startup status, footer, and single semantic announcement come from the generated localization API. The `Owntend` brand remains left-to-right inside either surrounding direction.

## Workflow

1. Add or update the English message in `app_en.arb`.
2. Add the corresponding Arabic message and metadata.
3. Use meaningful message keys based on purpose rather than literal wording.
4. Add placeholder metadata, types, examples, and plural/select forms where needed.
5. Regenerate:

```powershell
flutter gen-l10n
```

6. Replace hardcoded user-visible strings with `AppLocalizations` access.
7. Test both locales and layout directions.

## Message rules

- Keep placeholders semantic and stable.
- Do not concatenate translated fragments to form sentences.
- Use ICU plural/select syntax for grammatical variation.
- Format dates, times, numbers, and quantities with locale-aware APIs.
- Avoid embedding punctuation assumptions that break Arabic text.
- Keep technical identifiers, file names, and version strings separate from translated prose.
- Do not expose raw backend error text directly to users.
- Keep capability status distinct from permission outcome in user-facing wording: an application preference is not proof that Android delivery, location service, or exact-alarm access is effective.
- Treat permission, account-deletion, ads/consent, backup, permanent deletion, and Undo strings as high-impact translations that require semantic review in both languages.
- Authentication copy must describe Google sign-in as required for the production account/cloud path. Backup copy must name the encrypted `.owntend-backup` container and must not call it a ZIP.

## Controlled domain values

Stable stored identifiers and wire values remain locale-neutral. Enum names, pet/fish tokens, and similar controlled values must be converted to localized display labels at the presentation boundary; user-entered names, notes, species, breeds, placement, and other free text remain exactly as entered.

Shared controlled-value presenters live in `lib/src/ui/domain_localization.dart`. Item Type presentation is centralized from the stable `AssetType` enum; Category is not a separate persisted or searchable item classifier. Quantity and recurrence text must use the existing ICU messages rather than manually composing English singular/plural fragments. Search indexes include English and Arabic aliases for controlled values such as Item Type so either language can discover the same canonical record without translating persisted data. User-authored display text and machine search aliases live in separate FTS columns, so snippets never expose canonical aliases merely because an Arabic synonym matched. Controlled search results must render through the same localized presenters used by the rest of the UI.

For relationship metadata that is not a sentence, use a direction-neutral separator such as `·` instead of embedding English grammar such as `in` or manually concatenating translated sentence fragments.

## RTL layout

Use directional APIs:

- `EdgeInsetsDirectional` instead of left/right-specific padding.
- `AlignmentDirectional` where start/end semantics are intended.
- `BorderRadiusDirectional` where corners follow reading direction.
- `TextAlign.start` and `TextAlign.end` where appropriate.
- Direction-aware icons and animation when meaning depends on navigation direction.

Do not mirror universal symbols such as media controls, checkmarks, or product logos unless their semantic direction requires it.

Floating SnackBars and capability-setup cards must use directional layout. Transient feedback uses directional margins while Flutter's `Scaffold` resolves the actual safe area, keyboard-adjusted content, navigation, footer, and floating-action-button obstruction; feature routes must not duplicate that vertical clearance. Mixed Trash batches use localized counts and labels; Trash and maintenance completion remain separate semantic operations.
Feedback raised from a modal sheet uses the root overlay but keeps the same
directional sides and localized content. Account-deletion confirmation text
must accurately explain silent same-account verification and the conditional
Google chooser fallback in both languages.

## Reduced motion and accessibility

- The process splash remains the first non-blank Flutter surface, but `MediaQuery.disableAnimations` completes its intro and stops the repeating loop.
- GoRouter pages use no transition when `disableAnimations` or `accessibleNavigation` is active.
- Startup, hydration, and other animated surfaces must preserve meaningful static state rather than hiding progress or content when motion is reduced.
- The process splash exposes one localized container announcement and excludes decorative children from duplicate semantics.
- An active Undo SnackBar uses Flutter's persistent actionable behavior when accessible navigation is enabled; it must not disappear merely because another message arrives.
- Test focus order, TalkBack announcements, text scaling, and hardware/software input on a physical device before claiming device accessibility evidence.

## Testing checklist

For meaningful UI changes, verify:

- English LTR and Arabic RTL.
- Long translations and text scaling.
- Form labels, validation, hints, and error states.
- Dialogs, snackbars, bottom sheets, and notifications.
- Process splash, static startup/failure branches, capability setup, and settings-return states.
- Charts, dates, recurrence text, and statistics.
- Route transitions, back affordances, and chevrons.
- Mixed Arabic/Latin content such as versions, asset serial numbers, and URLs.
- Accessibility labels in both locales.
- Reduced-motion and accessible-navigation modes.

Focused repository coverage for the remediated startup, permissions, and feedback surfaces can be run with:

```powershell
flutter test --no-pub test/owntend_splash_lifecycle_test.dart
flutter test --no-pub test/features/permissions/permission_education_overlay_test.dart
flutter test --no-pub test/feedback_coordinator_test.dart
```

This is widget/source evidence only. It does not replace English/Arabic review, TalkBack, keyboard/focus, system-settings return, or launch testing on a physical release device.

## Generated-file discipline

Generated files may change substantially after Flutter upgrades. Keep those changes isolated and review the source ARB diff first. Never patch generated localization output to fix a translation or build issue.

## Review ownership

Arabic changes should receive language review when wording affects destructive actions, permissions, privacy, monetization, account deletion, or backup/restore. A mechanically valid translation is not sufficient for high-impact consent text.
