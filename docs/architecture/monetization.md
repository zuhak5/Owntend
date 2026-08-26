# Monetization Architecture

### Journaled charged creation (WP-003)

Charged asset creation mirrors tasks: `AssetCreationController`
(features/assets/application) persists a durable operation journal entry
(shared `TaskCreationOperationStore`, payload discriminator `asset`) BEFORE the
`createAsset` RPC. Insufficient points and operation-id reuse are terminal;
transport ambiguity is `outcomeUnknown` and is reconciled at startup by
`ChargedOperationResolver` using the server's idempotent status lookup — the
same recovery walk tasks use. A new charged operation is blocked while any
ambiguous one awaits recovery.

## Scope and sources of truth

Owntend uses Google Mobile Ads for native, interstitial, rewarded, and rewarded-interstitial presentation, while Supabase remains authoritative for points, charged creation, reward claims, and reward settlement. Ads can become unavailable without making core asset or maintenance data inconsistent.

This document describes the production-v1 baseline. The executable sources are:

- [`monetization.dart`](../../lib/src/features/monetization/monetization.dart) for consent, lifecycle integration, format orchestration, placement policy, and reward preflight.
- [`ad_runtime.dart`](../../lib/src/features/monetization/ad_runtime.dart), [`ad_retry_policy.dart`](../../lib/src/features/monetization/ad_retry_policy.dart), and [`ad_cache.dart`](../../lib/src/features/monetization/ad_cache.dart) for eligibility generations, retry budgets, freshness, and ownership leases.
- [`OwntendNativeAdFactory.kt`](../../android/app/src/main/kotlin/app/owntend/mobile/OwntendNativeAdFactory.kt) and [`owntend_native_ad.xml`](../../android/app/src/main/res/layout/owntend_native_ad.xml) for Android native-ad presentation.
- [`proguard-rules.pro`](../../android/app/proguard-rules.pro) for Google Mobile Ads and native ad factory release retention.
- [`app-ads.txt`](../../download-site/app-ads.txt) for developer root-domain publisher authorization.
- The [canonical initial migration](../../supabase/migrations/20260821124930_initial_schema.sql) for backend authority and immutable charged-operation recovery identity.
- [`admob-ssv-handler`](../../supabase/functions/admob-ssv-handler/index.ts) for signed callback validation.

The operational disclosure worksheet is [`google-play-data-safety-evidence.md`](../operations/google-play-data-safety-evidence.md). It separates repository facts from Play Console, AdMob, hosted-service, and device evidence.

## Authority model

The Flutter client may decide whether an ad surface is eligible, request an ad, create a pending reward claim, and display cached wallet state. It cannot credit or debit the authoritative wallet directly.

Supabase is authoritative for:

- point balances and ledger entries;
- atomic point-debited creation;
- configuration and format kill switches;
- reward-claim eligibility, expiry, cooldowns, and limits;
- SSV signature and payload validation;
- transaction replay protection and idempotent settlement.

All user-owned monetization mutations derive the caller from the authenticated Supabase identity. The SSV settlement RPC is reserved for the service role used by the Edge Function. Row Level Security exposes only the authenticated user's permitted wallet, transaction, and pending-claim reads.

## Runtime eligibility

`AdRuntimeEligibility.sdkEligible` requires every global gate below. A missing configuration or consent value is represented by a fail-closed snapshot.

| Global gate | Eligible value | Runtime consequence when false |
| --- | --- | --- |
| Platform support | Android or iOS, never web or desktop | The Mobile Ads SDK is not initialized. |
| Application lifecycle | `AppLifecycleState.resumed` | Loads and presentation are blocked while detached, inactive, paused, or hidden. |
| Consent refresh completed | `ConsentSnapshot.updated == true` | Cached or assumed consent is not sufficient at startup. |
| UMP permission to request ads | `canRequestAds == true` | No format is allowed. |
| Global remote switch | `adsEnabled == true` | All formats are disabled. |

Each format also has its own remote switch and presentation constraints:

| Format | Client eligibility beyond the global gates | Additional presentation checks |
| --- | --- | --- |
| Native | `nativeAdsEnabled` | Current route, no active native-ad presentation suspension, and no explicit widget override of `false`. |
| Interstitial | `interstitialAdsEnabled` | A fresh cached ad, the shared fullscreen gate, and completion policy: not the first-ever session, not a rapid completion, no keyboard or modal, cooldown elapsed, and session cap not reached. |
| Rewarded | `rewardedAdsEnabled` | Authenticated monetization repository, fresh cached ad, shared fullscreen gate, and a successful server claim before show. |
| Rewarded interstitial | `rewardedInterstitialEnabled` | The same fullscreen and claim preflight as rewarded. The backend claim RPC additionally requires the general rewarded switch, so it fails closed if the client switches disagree. |

The service reports a format as allowed only after Mobile Ads initialization succeeds. Known native placements are explicitly mapped; an unknown production placement is rejected rather than silently using another unit.

## Consent freshness and lifecycle

`OwntendConsentService` starts blocked. Once per service lifetime—normally once per application launch/process—it calls UMP `requestConsentInfoUpdate`, presents a required consent form, and then reads both `canRequestAds` and the privacy-options requirement. This matches Google's requirement to refresh consent information on application launch without treating an application-owned cached string as current consent.

Non-production builds may additionally supply compile-time UMP debug settings through `ADMOB_TEST_DEVICE_IDS` and `ADMOB_CONSENT_DEBUG_GEOGRAPHY`. The app maps those values into `ConsentDebugSettings` only outside production. Production config validation fails closed if either debug key is set.

If the consent update or form reports an error, the app records only a technical warning and still asks UMP for its current `canRequestAds` value. Ads remain blocked unless UMP explicitly returns `true`; core application behavior continues. The privacy-options action presents the UMP privacy form and refreshes the snapshot afterward.

Lifecycle resume changes runtime eligibility, but it does not issue another UMP consent-information request. Consent is therefore launch-fresh and privacy-options-refreshable, not periodically refreshed on every resume. AdMob message configuration, geographic behavior, and the availability of a required privacy-options entry point are console and device evidence, not facts proven by this repository.

## Debugging and test-device safeguards

The runtime applies one `RequestConfiguration` before Mobile Ads initialization with `MaxAdContentRating.pg`, `AgeRestrictedTreatment.unspecified`, and any configured non-production test-device identifiers. The repository keeps production and non-production ad-unit IDs separate, and `AppConfig` rejects production builds that still declare test-device IDs or UMP debug geography.

For non-production troubleshooting, Settings exposes a debug-only Ad Inspector entry point. It is intentionally absent from production builds and becomes useful only after consent and SDK initialization on a registered test device.

## Generation invalidation and ownership

Every material eligibility change increments an `AdRuntimeController` generation. Applying a new generation cancels retry timers, resets per-format failure counters and in-flight load markers, and disposes cached formats that are no longer allowed. SDK initialization and load callbacks retain the generation they started under; a callback that arrives after a consent, lifecycle, configuration, or disposal transition is rejected and its ad is disposed.

Cached fullscreen and native ads are fresh strictly before 55 minutes from load. At 55 minutes or later they are disposed and replaced instead of being shown. `AdLease` makes native-ad release exactly once, while `FullScreenAdGate` serializes all interstitial and rewarded presentation. Dismissal, show failure, synchronous exceptions, and disposal all release their ownership through idempotent cleanup paths.

Native components add a request generation and a Flutter palette identity. A route change, presentation suspension, runtime-generation change, widget configuration change, theme change, or stale cache invalidates pending or displayed work. `runWithNativeAdsSuspended` removes Android platform-view ads before a modal overlay can receive its first gesture and restores eligibility when the overlay action finishes.

## Classified retry and dormancy

Load errors are classified from the SDK error code and domain. Retry delays use a random factor from 0.8 through 1.2, giving the configured 20% jitter around the base delay.

| Failure class | Total attempts in one automatic cycle | Automatic delays after failures | Dormancy behavior |
| --- | ---: | --- | --- |
| Network | 5 (initial load plus 4 automatic retries) | 2, 8, 30, and 60 seconds after failed attempts 1 through 4, each with ±20% jitter | Dormant after the fifth failed attempt. |
| Internal or unknown | 3 (initial load plus 2 automatic retries) | 2 and 8 seconds after failed attempts 1 and 2, each with ±20% jitter | Dormant after the third failed attempt. |
| No fill | 1 | None | Dormant immediately; rapid no-fill polling is avoided. |
| Invalid request | 1 | None | Dormant immediately; retry cannot repair the request. |

Dormancy means that no automatic retry timer remains for that cycle. The attempt count includes the initial load; only the later attempts are automatic retries. Dormancy is not a permanent process-wide ban: a later eligible runtime transition, explicit preload/show attempt, or native component resynchronization can begin a new bounded cycle. Generation checks prevent an old retry timer or callback from reviving a newly blocked format.

## Fullscreen presentation and reward preflight

An interstitial acquires the shared fullscreen gate before taking a fresh cached ad. If no fresh ad exists, the gate is released, a load is requested, and the call returns without showing anything. Only a confirmed show updates the completion policy's session state.

A rewarded flow is stricter:

After the final due-today task is completed, the optional daily reward decision is presented as a compact, content-sized bottom sheet. It uses user-facing video/reward wording, keeps both actions close to the explanation, stacks them when width or text scaling requires it, preserves bottom safe-area/keyboard reachability, and removes the sheet transition when reduced motion is requested. After the device reward callback, the client reports only that the reward is being verified; it does not present the points as credited or mutate the wallet.

1. Confirm the selected format is eligible and already has a fresh cached ad.
2. Acquire the shared fullscreen gate.
3. Resolve the reward time zone and call the authenticated `create_reward_claim_request` RPC.
4. Recheck disposal, runtime generation, format eligibility, and cache freshness after the network preflight.
5. Attach the returned Supabase user UUID as SSV `userId` and the opaque claim UUID as `customData`, then show the ad.
6. Treat the device reward callback only as “shown, awaiting server verification.” It never credits points.
7. Let Google's signed callback reach `admob-ssv-handler`; verify its ECDSA P-256/SHA-256 signature, exact field shape, key, timestamp, approved unit, reward item and amount, claim, and user binding.
8. Settle through `process_admob_ssv_reward`, which locks and validates the pending claim, rejects replay or mismatches, and updates the claim, wallet, and ledger atomically. Exact duplicates return an idempotent result without another credit.

Pending claims expire after the database-defined interval and remain visible for recovery while still valid. An ad dismissal, SDK reward callback, or client event is never settlement authority. Service-role credentials remain in the Edge Function environment and are not distributed in Flutter configuration.

## Native-ad bridge contract 1

Flutter owns native-ad lifetime, eligibility, placement, event callbacks, and app-theme selection. Android owns the actual `NativeAdView`, registered provider assets, AdChoices surface, and app-owned chrome.

For bridge contract 1, Flutter emits an entire `#RRGGBB` palette in one request:

| Surface | Keys |
| --- | --- |
| Card | `backgroundColor`, `borderColor` |
| Creative text | `headlineColor`, `bodyColor`, `advertiserColor`, `sponsoredColor` |
| Ad badge | `adBadgeBackgroundColor`, `adBadgeTextColor` |
| Call to action | `callToActionBackgroundColor`, `callToActionTextColor` |

The Kotlin factory validates the version and all ten colors before mutating the inflated view. An unknown version, missing key, wrong type, or malformed color rejects the entire supplied palette and atomically uses the complete light/dark Android resource palette. It does not log custom options or user data. Rounded fills and strokes remain app-owned drawables.

The factory registers headline, body, advertiser, icon, call-to-action, and AdChoices views before calling `setNativeAd`. Optional body, advertiser, call-to-action, and icon assets are cleared and hidden when absent. Provider-owned creative assets are not recolored. A Flutter theme identity change releases both displayed and in-flight native ads and requests one replacement; Android `values` and `values-night` colors are a safe fallback rather than the primary in-app theme authority.

Every routed application content screen declares a native-ad placement,
including task detail, Inbox, capability setup, and all Tools destinations. The
shared slot collapses without a gap when platform, lifecycle, consent,
configuration, initialization, route visibility, or presentation-suppression
gates are not satisfied. Splash/bootstrap frames, Google authentication,
system permission UI, dialogs, and modal sheets are not ad placements. Native
card and loading surfaces use the same theme-derived lowest card surface as
ordinary content cards in both light and dark themes.

## Point-debited creation and offline behavior

In the Owntend points economy, points are spent **only when creating a new standalone maintenance task** (1 point). All asset/item creation (across general, device, pet, plant, and safety categories) is completely free (0 points), including any bundled initial maintenance plans created as part of an asset creation operation.

Standalone task creation uses an authenticated, idempotent backend RPC (`create_task_with_point_debit`). The transaction checks configuration and wallet state, debits 1 point from the wallet, creates the target plan and metadata rows, records the operation and ledger entry, and returns the authoritative result—or commits none of those steps. Asset creation uses `create_asset` with a zero-point charge, atomic entity and initial plans creation, and replay protection without deducting wallet points or inserting negative ledger rows.

RLS denies direct authenticated insertion of a new charged plan. Ordinary synchronization may reconcile only a plan already created by the atomic task-creation RPC; the maintenance-completion RPC uses a transaction-scoped internal authorization marker when it must establish the first canonical plan row. This prevents a Data API insert from bypassing the wallet transaction without blocking post-RPC convergence.

A wallet below the required charge during task creation is an expected business outcome, not a transport failure. Task creation returns HTTP success with `status: insufficient_points`, the authoritative balance, a zero charge, and no entity, operation, wallet, or ledger mutation. The Flutter repository maps that structured payload to a typed shortage. Task creation persists the attempt as permanently rejected instead of outcome-unknown, and the task editor keeps a modal recovery surface visible until the user chooses to keep editing or earn points. Reward loading, no-fill, dismissal, rejection, and server-verification-pending states are shown inline so an unavailable ad never leaves the user waiting without an explanation.

When the server cannot confirm a charged operation, the client must not present it as completed or enqueue a blind wallet mutation. User input may be preserved only as an explicitly unfinished draft in a workflow that supports it. Every creation operation uses a durable pre-RPC journal write (`TaskCreationOperationStore` / `ChargedOperationJournal`) before invoking backend RPCs. If durable write to secure storage fails, the RPC is not executed. New charged-creation payloads include a client-generated SHA-256 `request_hash`; the same value is retained in the durable journal. The backend keeps this client recovery identity separately as `creation_point_operations.client_request_hash`, while the existing `request_hash` remains the server-computed digest of canonical JSONB used to reject altered create-RPC replays.

Ambiguous operations (`outcomeUnknown` or interrupted `submitting`) are considered during authenticated startup before the cached-ready shortcut and again before a new charged task can mint another operation ID. `ChargedOperationResolver` calls `get_charged_operation_status(p_operation_id, p_request_hash)` with both immutable values; the public status RPC has no operation-ID-only default. The contract-1 result returns the exact committed result only when both values match, returns `not_found` for an unknown operation in the authenticated account, and raises `OPERATION_ID_REUSED` for a known operation with a different hash. A `not_found` operation is resubmitted using the exact retained payload and operation ID; no replacement UUID is minted. Account scope is rechecked before applying remote recovery results. The canonical server result is reconciled into local state before the journal becomes terminal. Upon reaching terminal states (`reconciled` or `permanentRejected`), user-entered payloads are purged (`purgeTerminalPayloads`) to prevent unbounded content retention.

## Privacy and diagnostics boundaries

- Ad requests and reward identifiers must not contain room names, asset names, maintenance content, location, email, media references, tokens, or raw domain payloads.
- Current app-owned monetization events contain only technical fields: known placement and canonical Google ad-unit identifiers (`ca-app-pub-<16 digits>/<10 digits>`) for native events; cooldown/session counters for interstitials; and reward amount, entry point, and server-pending state for rewarded events. The authenticated event RPC derives the user ID and rejects unknown keys, malformed identifiers, wrong types, unbounded counters, and non-allowlisted values. New call sites therefore require a privacy review and an explicit backend allowlist update.
- SSV logs omit the raw query and signed content, redact claim and user values, record only signature length, and replace the provider transaction ID with a short SHA-256 fingerprint. They still contain technical request and reward metadata such as user agent, parameter names, ad unit, reward value, timestamp, key ID, failure details, and a request ID. Hosted log access and retention require operator review.
- Google Mobile Ads/UMP may process interaction, IP, diagnostic, consent, advertising-identifier, and other device/account data according to the installed SDK and console configuration. The repository cannot establish Google's final processing or the Play disclosure by itself.

See the [Google Play data-safety evidence worksheet](../operations/google-play-data-safety-evidence.md) for the exact repository evidence, unresolved provider and console decisions, deletion boundaries, and release sign-off fields.

## Validation and evidence boundary

Repository coverage includes:

- [`monetization_test.dart`](../../test/monetization_test.dart) for eligibility gates and per-format switches, generation changes, retry budgets and jitter bounds, 55-minute freshness, exact-once leases, fullscreen serialization, placement policy, and native slot states.
- [`native_ad_factory_contract_test.dart`](../../test/native_ad_factory_contract_test.dart) for bridge-contract parity, atomic fallback, registered assets, absent-asset hiding, rounded/stroked chrome, light/dark resources, and single native-constructor ownership.
- [`0012_points_monetization.test.sql`](../../supabase/tests/database/0012_points_monetization.test.sql), [`0013_admob_ssv_security.test.sql`](../../supabase/tests/database/0013_admob_ssv_security.test.sql), and [`0030_monetization_authority.test.sql`](../../supabase/tests/database/0030_monetization_authority.test.sql) for authorization, wallet conservation, reward limits, replay, canonical AdMob event identifiers, and idempotency.
- [`admob-ssv-handler/index_test.ts`](../../supabase/functions/admob-ssv-handler/index_test.ts) for callback parsing, signatures, setup probes, production validation, retry responses, duplicate settlement, and log redaction.

These checks do not prove:

- AdMob application/unit ownership, UMP messages, privacy-options configuration, or the production SSV callback URL;
- behavior of the resolved release SDK versions, the merged release manifest, or advertising-ID access;
- native rendering, AdChoices interaction, theme transitions, lifecycle races, or fullscreen overlap on a physical device;
- deployment of the reviewed migrations and Edge Function to the intended Supabase project;
- a successful signed AdMob callback and one-credit settlement in the hosted environment;
- the accuracy or submission state of the Play Console Data safety, Ads, target-audience, or account-deletion declarations.

Capture those items against the exact release artifact without recording tokens, direct user identifiers, full callback URLs, or provider payloads.


## Live wallet state

`point_wallets` is server-authoritative monetization state. It is **not** an
18th local-first sync/change-feed entity and is never written through the
generic outbox.

The client has one auth-scoped Riverpod wallet owner. It keeps the last-good
same-account wallet, subscribes to the owner-filtered Supabase wallet stream,
and performs canonical reads after resume/reconnect and after authoritative
mutation results. Charged task/item RPCs and hash-qualified charged-operation
recovery/replay publish their returned server balance to that owner
immediately; the client never computes wallet deltas.

Canonical wallet snapshots are ordered by server `updated_at`. When a charged
RPC returns only an authoritative balance, that balance is displayed
immediately and is protected from older initial/Realtime snapshots until the
post-mutation canonical read completes. A newer canonical server snapshot is
then accepted normally.

Rewarded-ad device callbacks remain `shownAwaitingServerVerification`. SSV
settlement changes `point_wallets` on the server; Realtime plus canonical
refetch/resume/reconnect convergence updates the same wallet owner. No device
callback fabricates a credit.
