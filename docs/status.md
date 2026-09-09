# Implementation status

Updated September 9, 2026. Sideleaf's authenticated notebook beta is hosted at [sideleaf.vercel.app](https://sideleaf.vercel.app). Browser live transcription passed an earlier hosted Chromium test using synthetic microphone input, the real OpenAI service and actual Supabase persistence. Native build `7` targets iPhone and iPad on iOS/iPadOS 26 or later under the registered `com.thinkhale.sideleaf` identifier. It adds versioned Terms acceptance, hardens the audio-engine tap lifecycle, and removes the Swift 6 main-actor isolation trap from AVFoundation's real-time microphone callback. Stripe credentials and a real sandbox purchase are still pending. XCTest execution, simulator runtime, and physical-device microphone behavior remain separate verification work.

## Implemented product behavior

- Authenticated notebooks, editable pages, preparation, web ink, semantic annotations and immutable version history.
- Offline manual editing, autosave, conflict recovery, library search and exports.
- Sideleaf branding from the supplied logo package.
- Browser focus mode with a centered, responsive notebook layout and working controls.
- Browser microphone permission, deliberate Start, conspicuous live status, WebRTC transcription connection, interim text, server-confirmed saved transcript segments, Pause/Resume/Stop and connection rollover.
- Server-authoritative monthly connected-time accounting, per-meeting Free allowance, one active assisted session per account, connection-attempt throttling and watchdog cleanup.
- Stripe hosted Checkout, customer portal, signed raw-body webhooks, idempotent authoritative subscription reconciliation, mode-isolated entitlements, cancellation, payment failure, refund/dispute handling and account-deletion safeguards.
- Settings for the actual plan, usage, reset instant and billing availability. Paid controls stay unavailable until provider configuration is complete and explicitly enabled.
- Native SwiftUI/PencilKit source for iPhone and iPad. Build `7` includes email/password sign-in through the Sideleaf API, a signed Better Auth bearer stored in Keychain, explicit adoption of device-only guest pages, versioned legal gating, and conflict-safe synchronization of typed text and semantic marks. The sync adapter preserves remote blocks and web ink it does not own; PencilKit freehand ink remains device-only.
- Account creation requires explicit acceptance of the current Terms of Service and a separate recording-law responsibility acknowledgement. Later Terms versions gate notebook APIs, synchronization and capture while preserving sign-out, subscription management, account export, account deletion and active-session Stop. The repeated per-session attestation toggle has been removed; both clients retain a responsibility reminder and deliberate Start action. Account deletion now stops owned capture sessions and expires unfinished Sideleaf Checkout sessions before applying the existing active-subscription safeguard.
- Native iOS/iPadOS 26 live transcription processes bounded microphone buffers on-device without creating an audio file or uploading audio. Its transcript text may synchronize as personal user content rather than trusted server/provider transcript provenance. Build `7` includes audio-engine configuration-change reconnection, route-derived tap-buffer sizing, and a nonisolated `@Sendable` tap callback; physical-device audio behavior remains to be verified.

Connected transcription time includes brief setup after the provider connection becomes available. Paused time is excluded. Sideleaf saves text rather than audio recordings; there is no audio playback, audio file, audio Storage bucket or offline audio upload queue. See [live capture](live-capture.md), [billing](billing.md) and [audio privacy](privacy.md) for the exact boundaries.

## Hosted services and migrations

The owner's selected Vercel Sideleaf project hosts both the Vite frontend and Hono Node API and is linked to [ThinkHale/Sideleaf](https://github.com/ThinkHale/Sideleaf). Better Auth owns accounts and sessions; Supabase provides PostgreSQL. Email/password login is explicitly enabled for this beta. The backend can issue a signed Better Auth bearer for native API calls while browser sessions continue to use cookies. Google OAuth remains optional and unverified.

Supabase project `qhgzilyanroqomafhybg` now has 16 application tables in the private `sideleaf` schema. Eight reviewed migrations are applied and aligned:

1. `20260907130025`: private notebook/auth schema and restricted backend role.
2. `20260907131718`: remove public execution grants from the provider's RLS helper while retaining its event trigger.
3. `20260907145716`: seven capture, usage, watchdog and billing tables with backend-only grants, RLS and indexes.
4. `20260907151500`: install the watchdog's pg_cron/pg_net extensions and restrict cron/net access.
5. `20260907152500`: recreate the newly installed pg_net extension under `extensions` and retain restricted net access.
6. `20260909173109`: add immutable, versioned Terms and recording-responsibility acceptance records with backend-only grants and RLS.
7. `20260909175945`: bind every acceptance row to the SHA-256 fingerprint of the displayed legal bundle.
8. `20260909180045`: narrow legal-acceptance RLS to explicit SELECT and INSERT policies.

The runtime role `sideleaf_runtime` has schema usage and table CRUD, cannot create schema objects or bypass RLS, and uses the intended role-level search path. The private schema is excluded from the Data API. Hono and Better Auth enforce individual ownership. The database advisor now reports only the existing leaked-password warning for unused Supabase Auth. This is not a complete security audit.

The selected database connection uses the Supavisor transaction pooler with certificate-verified TLS and a bounded reusable pool. Production startup does not apply DDL. The Vercel function requests a 300-second execution duration; capture rolls its connection at about 225 seconds. The Supabase watchdog runs every 30 seconds using a secret from Vault. New starts require recent healthy supervision.

Preview and production still share the beta database. Stripe test/live records are isolated by mode, but notebook and account data are not isolated between preview and production. Separate those databases and credentials before wider production use.

## Verification completed

The current `npm run check` pass completed the production build and **135 Vitest tests across 13 files**. Two focused legal-acceptance browser flows passed. The complete browser end-to-end and built-PWA suites were updated but were not rerun in this pass. Real-provider checks below are additional evidence.

- TypeScript/Vite production build passed.
- **135 Vitest tests passed**, covering notebook/API contracts, authentication, cloud initialization, versioned and content-fingerprinted legal acceptance, stale-Terms recovery, protected document blocks, capture controls and metering, transcript provenance, live-capture page-exit protection, watchdog handling, browser capture state and Stripe billing boundaries.
- Live capture now prevents in-app page changes, billing/account exits, reload, and tab closure until finalization and any unconfirmed text are resolved. A Terms update received mid-capture is deferred until that safe point and announced accessibly.
- Account deletion locks its UI while in progress. A local-cache failure after confirmed cloud deletion no longer leaves the web UI appearing signed in, and native cached-page cleanup can be retried without issuing a second remote deletion.
- **13 browser end-to-end tests passed**, including the notebook workflows, focus-mode layout and billing UI behavior.
- The earlier built-PWA test passed, covering offline reload, recovered text synchronization and private-text exclusion from PDF. It was not rerun in this pass, and hosted offline behavior has not been freshly retested.
- Three capture UI checks passed after the mobile margin/footer adjustment.
- Actual Supabase runtime TLS, role/schema/table resolution and denial of schema creation and anonymous schema access passed.
- A real Supabase capture integration probe created an exclusively synthetic account/notebook/page, used the production database adapter with a fake provider, and returned 200 for capture start and stop. Reservation completed in about 0.55 seconds. The synthetic account and dependent records were deleted. This verifies the database transaction path, not the real OpenAI transport.
- A separate hosted Chromium test with synthetic microphone input passed real OpenAI WebRTC transcription using `gpt-4o-mini-transcribe`, the server observer/SSE stream, saved transcript text in Supabase and Pause cleanup. All microphone tracks ended, the server session reached a terminal state and the synthetic account was deleted.
- A second hosted real-provider test passed the approximately 225-second connection rollover, saved new transcript text after reconnection, Pause, Resume and network-loss cleanup. Its synthetic account was also removed.
- All eight hosted migrations are aligned. The advisor result is described above.
- The existing hosted notebook passed secure-cookie sign-up/sign-in, persistence after a fresh sign-in, idempotent retries, stale-edit 409 responses, cross-account 404s, cross-origin mutation rejection, exports, history and deletion. Synthetic accounts were cleaned up and old sessions were rejected.
- Earlier hosted Chromium checks at desktop and phone sizes passed page creation, editing, saved state and reload persistence without console warnings or errors.
- Prior deployment upload verification confirmed no local database or real secret files in the replacement deployment; explicit Git, Docker and Vercel exclusions remain in place.
- XcodeGen regenerated `native/Sideleaf.xcodeproj`. Build-for-testing passed for shutdown iPhone 17 Pro and iPad Pro simulator destinations, compiling both the app and XCTest products. Because no simulator was booted, XCTest did not execute and no runtime UI result is claimed.
- An unsigned generic iOS Release archive passed. Its app metadata reports bundle ID `com.thinkhale.sideleaf`, version `1.0` (`7`), minimum OS `26.0`, device families `[1, 2]`, microphone and speech usage descriptions, iPhone/iPad AppIcon entries and Boolean `ITSAppUsesNonExemptEncryption = false`.

## Provider verification

### OpenAI

On September 7, 2026, the hosted test passed with `gpt-4o-mini-transcribe` on deployment `dpl_BwDrqTrnTLS3bGUqKDUgJw6xmSnj`. Chromium supplied a synthetic microphone fixture through the same WebRTC path used by the app. The real OpenAI service produced text, the server observer persisted it in Supabase, and the browser received confirmed saved transcript segments. Pause ended every microphone track and finalized the server session. The synthetic account and its dependent records were removed afterward. Local screenshots are in `C:/Users/think/AppData/Local/Temp/sideleaf-live-capture-1814f810-4516-45a1-b8f5-a3c439834731`.

A second hosted test on September 7 passed a full approximately 225-second rollover, new provider text saved after reconnection, Pause, Resume and network-loss cleanup. The original connection settled 226,658 milliseconds, and the new session produced confirmed saved text. Its synthetic account was removed. Evidence is in `C:/Users/think/AppData/Local/Temp/sideleaf-live-capture-dd76f155-38c7-4e7b-9610-3f586913da43`.

These tests verify the hosted provider account, transport, saved-text path and the exercised cleanup/reconnection cases. Physical microphone behavior, native capture and repeated long-meeting reliability have not been validated. One successful rollover test is not a long-duration reliability guarantee. The synthetic audio fixture is test input, not an audio recording saved by Sideleaf. The runtime key remains server-side. Provider-internal retention still follows the account's controls and published policies rather than a guarantee established by these tests.

### Stripe

The backend and UI are implemented. No real Stripe sandbox checkout, webhook endpoint delivery, portal session, live product/price or charge has been verified. Credentials and environment-specific resources must be configured before testing. Only enable live purchases after sandbox checkout, recovery, cancellation, refund/dispute and re-subscription checks pass. StoreKit and Google Play Billing remain native implementation work with a shared Sideleaf entitlement model.

## Remaining product work

- Add email verification delivery and password recovery.
- Isolate preview/production databases and credentials; retest hosted offline recovery and cross-instance behavior as part of the next release validation.
- Complete the remaining physical-device, repeated long-session and Stripe checks above and review customer-facing retention, participant-permission, backup and deletion disclosures.
- Build coaching, source-grounded suggestions, structured summaries, actions and unsent follow-up drafts. The present transcription path does not implement those features.
- Extend semantic marking to transcript revisions and define targeted redaction across current data and history.
- Add private Supabase Storage endpoints for permitted PencilKit artifacts and attachments with ownership, retention and deletion verification. Audio storage is excluded.
- Validate the proposed Pro economics and operating costs. Add pagination, server-side search and history-management policies before scaling large libraries.
- Complete native signing and App Store upload validation, and execute the compiled anchor tests on booted iPhone and iPad simulators.
- Validate build `7` native authentication, legal-state transitions, guest-page adoption, revision-based text/mark synchronization, conflict recovery and on-device transcription. Implement editable cloud ink artifacts and verified store purchases. Validate iPhone touch ink and compact navigation, plus actual Apple Pencil, palm rejection, iPad rotation, audio/background interruptions and offline conflicts on physical hardware.

## Known boundaries

Build `7` remains compile-only until final verification in this change. No simulator was booted, XCTest did not execute, and no physical device/Pencil/microphone runtime was verified. The target uses device family `1,2`; iPhone supports portrait and iPad supports all four orientations, with iOS/iPadOS 26 as the minimum. Native synchronization covers typed text, semantic marks and saved on-device transcript text, not PencilKit freehand ink. There is no handwritten-text recognition/search, collaborative CRDT, cloud coaching or automatic summary generation. The library still downloads owned pages for client-side search. Web undo is held in memory for the open page and does not cover every margin edit. PDF reflows typed text and places handwriting separately.

If initial library loading fails while the API restarts, a reload is still required once the API is ready; the current Retry sync action retries pending edits rather than an empty initial read. Page-document exports and meeting-transcript exports remain separate. Deleting a note block does not erase its historical revisions.

Credential and deployment details are in [hosting-secrets.md](hosting-secrets.md). The verification scope above distinguishes the tested browser path from remaining device and purchase work.
