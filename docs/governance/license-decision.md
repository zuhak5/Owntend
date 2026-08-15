# Repository License and Asset Provenance Decision

## Status: Resolved and Approved

The repository licensing decision and asset provenance registry have been formally approved and recorded.

- **Primary Repository License**: MIT License (Copyright (c) 2026 Thulfiqar AL-Zamili and Owntend contributors). See [`LICENSE`](../../LICENSE).
- **Notices and Trademarks**: Explanatory disclosures and brand restrictions are maintained in [`NOTICE`](../../NOTICE).
- **Third-Party Dependency Notices**: Complete SPDX 2.3 SBOM and dependency notices are maintained in [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md).
- **Asset Provenance Registry**: Cryptographically hash-bound provenance, licensing, origin, and redistribution metadata for all visual, font, audio, and branding assets is maintained in [`config/asset_provenance.json`](../../config/asset_provenance.json).
- **Approval Date**: 2026-08-14
- **Reviewer / Decision Authority**: `zuhak5` (Thulfiqar AL-Zamili)
- **Legal Disposition**: `APPROVED_FOR_DISTRIBUTION`

## Distribution Scope

1. **Source Code**: Released under the permissive MIT License. Contributions are incorporated under the same terms.
2. **Trademarks & Branding**: The "Owntend" and "VersionDeck" names, logos, app icons, and branding assets remain proprietary trademarks with all rights reserved.
3. **Typography**: The Geist font family is bundled under the SIL Open Font License 1.1 (OFL-1.1).
4. **Audio Assets**: UI sound effects are dedicated to the public domain under CC0 1.0 Universal (CC0-1.0) / MIT app distribution.
5. **Google Branding**: The Google 'G' mark is used strictly in accordance with Google Brand Permissions and Identity Guidelines for third-party sign-in buttons.
6. **Binaries & VersionDeck**: Distributable APK/AAB packages and static VersionDeck assets bundle all required notices and license terms.

## Verification Gate

The asset provenance and licensing state is automatically enforced by:
```powershell
npm run validate:asset-provenance
npm run test:asset-provenance
```