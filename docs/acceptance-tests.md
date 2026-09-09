# Acceptance tests and evidence

The September 7-9, 2026 implementation and verification results are recorded in [status.md](status.md), including the current 135-test Vitest suite, earlier browser/focus and built-PWA checks, production Supabase integration, hosted real OpenAI transcription with synthetic microphone input, versioned legal-acceptance checks, and native compile evidence. The dated results below preserve earlier baselines and their narrower scope.

Recorded 2026-09-06 on Windows, Node 24.18.0. No test results below represent a Mac simulator, physical iPhone or iPad, Apple Pencil, live microphone provider, real billing account, or production database run.

After the Sideleaf rename, `npm run check` passed again with 23 tests, and the built-PWA offline/export test passed again. The in-app browser showed Sideleaf as its title and navigation name, reopened the existing account's example page, and reported no new warning/error console entries after the final reload. The earlier screenshots and title entry below document the original development-name review.

## Commands exercised

- `npm run build`: TypeScript and Vite production build passed.
- `npm test`: 23 tests passed across domain, authenticated API and filesystem persistence suites.
- `npm run test:e2e`: 5 Chromium browser tests passed after ink selection and keyboard movement/undo were added.
- `npm run test:pwa`: built-app offline reload/reconnect and export exclusion test passed. It generated a real A4 PDF through Chromium.
- `npm audit --omit=dev`: zero vulnerabilities reported for the installed production dependency graph.
- In-app browser: loaded the real app, registered a synthetic local account, opened an example page and switched to Select. Rendered notebook screen was inspected. Final fresh navigation produced no new warning/error console entries.
- PDF: Poppler rendered the exported A4 document and the rendered page was inspected. The private test block was absent from the PDF's rendered page.

## Tested acceptance mapping

| Area                         | Evidence and boundary                                                                                                                                                                                      |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Authentication and ownership | Two real Better Auth accounts in an in-memory PostgreSQL instance. Anonymous reads denied. Other-account page/history/export/delete and notebook writes denied. Account deletion invalidates its sessions. |
| Persistence and retries      | Page save creates a durable revision, repeated mutation ID does not duplicate it, concurrent same-version writes yield one save and one 409. Filesystem database reopened successfully.                    |
| Offline manual notes         | Browser goes offline, edits, reconnects and reopens saved text. Built PWA additionally reloads completely offline and recovers its draft.                                                                  |
| Conflict recovery            | Two tabs edit the same page. Stale tab gets a conflict and creates a separate recovered page, preserving both texts.                                                                                       |
| Anchoring                    | UTF-16 emoji offsets, unique quote/context movement, ambiguity rejection, missing source, correction preserving original quote, duplicate IDs and invalid resolved anchors.                                |
| Geometry and ink             | Real browser pointer circle in Write creates ink only. Undo removes it. The same circle in Mark selects the enclosed word and creates a semantic mark. It persists after viewport reflow.                  |
| Preparation                  | Discovery template fills empty fields, participants persist, readiness can be checked without starting the microphone, unavailable capture is explained, preparation survives reopening.                   |
| Follow-ups                   | Selected phrase produces an editable user follow-up, saved question reopens, changed source shows unresolved status. No AI-generated output is represented as tested.                                      |
| Exports                      | Markdown download, excluded note/mark filtering, full account JSON, page deletion cascading through history. PWA print view excludes private text.                                                         |
| Privacy                      | Unknown audio fields and forged AI/transcript provenance rejected. Source scan and route design show no capture path. This is not a bounded-live-audio or provider-retention test.                         |
| Responsive                   | Chromium at 1536x1024, 390x844, 820x1180 and 1180x820. No horizontal page overflow. Phone margin uses a separate tab. Focus retains microphone status.                                                     |

## Render checks

| Check             | Result                                                                                                                      |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------- |
| URL and title     | App at 127.0.0.1:5173 is titled Sideleaf.                                                                                   |
| Nonblank content  | Auth, library and notebook render real controls/content.                                                                    |
| Framework overlay | No overlay in inspected passing screens.                                                                                    |
| Console           | Main end-to-end flow asserts zero page errors. In-app console inspection is recorded in final status.                       |
| Screenshots       | Desktop, phone, iPad portrait and landscape images captured in the OS temporary `meeting-notebook-qa` directory.            |
| Interactions      | Actual auth, persistence, preparation, marking and recovery APIs exercised. No fixtures substituted for live transcription. |

The in-app browser was available and used first for visible inspection once the server was running. Playwright supplies the requested repeatable automated regression tests, pointer gestures, viewport controls and offline network tests. It was not used to disguise a successful live-provider run.

## Bugs found and repaired

- Windows OneDrive directory attributes prevented PGlite reopening. Development data moved to local application data, with an exclusive lock and tested reopening.
- The initial API watch launcher stalled/restarted unreliably. The API now uses a direct Node/tsx launch; frontend hot reload remains available.
- Hidden mobile button labels removed accessible names. Explicit labels were added.
- The initial PWA precached HTML without the first-load script/CSS assets. Installation now precaches the actual hashed entry assets and gets a build-specific cache version.
- Long phone page titles were clipped in a single-line input. An auto-height title textarea now wraps the full title.
- Generic participant-label selection once matched an unrelated checkbox in a test. The test now uses the exact field label.
- Development sign-up tests exceeded Better Auth's default route rate limit. Local-only auth has an explicit 30-per-minute limit; production retains the maintained default rules.

## Not tested or not implemented

Real prepare/start/pause/resume/end/reopen cloud transcription in the earlier dated baseline; live notes/keywords/coaching; stale text-model outputs; summary grounding and summary editing; captured interruption gaps; payments/restore purchases; native XCTest execution and runtime UI; physical iPhone/iPad microphone, on-device transcription and live Pencil hardware; signed App Store archive/upload; build-7 TestFlight installation; Docker build; installed-PWA behavior on Safari/iPadOS; browser storage exhaustion; very large notebooks; deployment/backup retention.

These are acceptance gaps, not passes. The exact next implementation steps are in `status.md`.

The concept-to-render comparison, copy differences, and intentional design deviations are recorded in [design-review.md](design-review.md).

## Supplied branding verification

### Interface integration, 2026-09-07

- `npm run build` passed after integration of the supplied artwork.
- `npm run test:e2e` passed all five Chromium workflows, including desktop, phone and iPad browser dimensions.
- `npx playwright test --config playwright.pwa.config.ts` passed the built PWA offline reload, recovered draft synchronization and print exclusion workflow.
- An additional authentication layout check at 1536x1024 and 390x844 found no horizontal overflow or page errors. Visible logo images decoded at their expected original dimensions. Screenshots are `sideleaf-auth-desktop.png` and `sideleaf-auth-phone.png` in `%TEMP%/meeting-notebook-qa`.
- The current desktop notebook and both authentication screenshots were opened and visually inspected. The supplied lockups retain their proportions and remain legible against the paper surfaces.
- SHA-256 comparison confirmed that the five original interface assets in `public/brand` match their supplied source PNGs byte for byte.
- Native asset references and original bytes were checked on the original Windows host.

### Platform icon update, 2026-09-08

- SHA-256 comparison confirmed that all seven original files now preserved in `public/brand` match the supplied PNGs byte for byte.
- The supplied full-bleed dark square is the canonical platform-icon source. The light square is retained as marketing artwork but is not used as an OS icon because its rounded tile and shadow are already baked in.
- Generated favicon, Apple touch, PWA, and native PNGs have their declared dimensions, sRGB color, and no alpha channel. The PWA manifest and service worker reference the generated web sizes.
- The latest `npm run check` passed the production web build and all 108 Vitest tests across 10 files. No React or CSS changed in the platform-icon update, so the 2026-09-07 interface screenshots remain the relevant rendered logo review.
- Xcode 26.6 passed the iPad simulator build and build-for-testing. An unsigned generic iOS Release archive passed, contains marketing version `1.0`, build `2`, bundle ID `com.thinkhale.sideleaf`, `UIDeviceFamily` value `2`, and a compiled 1024 x 1024 `AppIcon` rendition.
- The local Playwright workflows did not execute on this Mac because their pinned Chromium headless-shell binary is not installed. The in-app browser also could not initialize in this agent environment, so installed PWA appearance and masked Home Screen appearance remain manual visual checks.

### Universal iPhone and iPad target, 2026-09-08

- Xcode 26.6 passed compile-only builds for shutdown iPhone 17 Pro and iPad Pro simulator destinations. The iPhone build-for-testing product also compiled, including the phone touch-input policy test; XCTest execution and runtime UI remain unvalidated because no simulator was booted.
- An unsigned generic iOS Release archive passed. Its app bundle contains marketing version `1.0`, build `3`, bundle ID `com.thinkhale.sideleaf`, minimum OS `26.0`, `UIDeviceFamily` values `[1, 2]`, and compiled iPhone and iPad app icons.
- The archive declares portrait orientation for iPhone and portrait, upside-down portrait, and both landscape orientations for iPad. Its only required device capability is `arm64`.
- Compact-width navigation, controls, branding, sheets, and paper sizing were adapted for iPhone. Phone ink accepts touch input; iPad keeps Pencil-only ink so fingers continue to scroll.

### Native authentication, synchronization and on-device transcription source, build 4

- Build `4` source adds native email/password sign-in through the Sideleaf backend. The signed Better Auth bearer is stored in Keychain and used for the same owner-authorized notebook/page API; no Supabase or provider credential is embedded in the app.
- Typed text and semantic marks use the existing base-version and stable-mutation-ID revision protocol. The adapter preserves unknown remote blocks, preparation and web ink, while a stale 409 retains both sides for recovery. PencilKit freehand ink remains device-only.
- Guest pages are not silently uploaded after sign-in. They require an explicit adoption action into the current account, and cached pages remain account-scoped.
- iOS/iPadOS 26 live transcription requires participant consent, keeps bounded microphone buffers in memory, saves no audio file and uploads no audio. Saved transcript text is ordinary personal content, not server-confirmed provider transcript provenance.
- XcodeGen regenerated the checked-in project. Build-for-testing passed for shutdown iPhone 17 Pro and iPad Pro simulator destinations, compiling both the Sideleaf app and XCTest products. No simulator was booted, so XCTest did not execute and no simulator UI result is claimed.
- An unsigned generic iOS Release archive passed. Its `Info.plist` reports bundle ID `com.thinkhale.sideleaf`, marketing version `1.0`, build `4`, minimum OS `26.0`, device families `[1, 2]`, microphone and speech usage descriptions, and iPhone/iPad AppIcon entries.
- The archive contains Boolean `ITSAppUsesNonExemptEncryption = false`, matching current OS-provided HTTPS and Keychain-only encryption use. Dependency or feature changes that add encryption require a new export-compliance review.
- Physical-device sign-in, synchronization, microphone, interruption, transcription, touch/Pencil and signed TestFlight installation remain unverified. The build-4 API changes have not yet been verified in the hosted deployment.

### Account-level legal acceptance and iOS release candidate, build 6

- Account creation presents the current Terms and Privacy Notice, requires separate unchecked Terms and recording-law responsibility controls, and stores server-owned timestamps plus a SHA-256 legal-bundle fingerprint. A stale version returns the current metadata and resets the assent controls instead of retrying an obsolete version.
- The server gates notebook, synchronization, billing-purchase and capture work on the exact current Terms version and fingerprint. Sign-out, subscription management, account export, account deletion and active-capture cleanup remain available. Account deletion automatically stops owned capture sessions and expires unfinished Sideleaf Checkout sessions before the active-subscription check.
- The per-capture attestation toggle is removed. Browser and native capture retain a responsibility reminder, deliberate Start action, operating-system permission, visible live-microphone state, and Pause/Stop controls.
- Web and native account dialogs cannot be dismissed during deletion work. If confirmed cloud deletion succeeds but device cleanup fails, the web client clears authenticated UI and warns about site data; the native client offers a cached-page retry that does not repeat the server deletion.
- `npm run check` passed the TypeScript/Vite production build and all 135 Vitest tests across 13 files. Two focused legal-acceptance browser flows passed locally. The complete browser and built-PWA suites were not rerun in this pass; CI remains configured to install Chromium and run both suites.
- Live capture now blocks page-changing actions, account and billing exits, reload, and tab closure until capture finalization and any unconfirmed text are resolved. Focused page-exit and capture-client tests passed; the corresponding full browser flow remains part of CI.
- XcodeGen regenerated the checked-in project. Warnings-as-errors simulator build-for-testing and generic iPhoneOS build passed without booting a simulator. XCTest compiled but did not execute.
- An unsigned generic iOS Release archive passed. Its `Info.plist` reports bundle ID `com.thinkhale.sideleaf`, marketing version `1.0`, build `6`, minimum OS `26.0`, device families `[1, 2]`, microphone and speech usage descriptions, iPhone/iPad AppIcon entries, and Boolean `ITSAppUsesNonExemptEncryption = false`.
- The microphone path now reconnects routine audio-engine configuration changes, removes the old tap before reading a changed route format, validates input/output formats, derives a 120 ms tap buffer from the active sample rate, and stops/untaps before releasing an engine. This is a reasoned fix for the reported crash until physical-iPhone testing or an `.ips` report confirms the exact signature.

### Swift 6 microphone callback isolation fix, build 7

- Compiler SIL inspection reproduced the defect: an unannotated AVAudioEngine tap closure created inside the `@MainActor` transcription controller is emitted with `MainActor` isolation. AVFoundation calls that closure on its real-time audio queue, so Swift 6 can trap in `_swift_task_checkIsolatedSwift` on the first microphone buffer.
- The tap callback is now explicitly `@Sendable`, captures only the thread-safe audio bridge, and is emitted as `nonisolated`. This matches [Apple Developer Technical Support's documented workaround](https://developer.apple.com/forums/thread/793455) for the same `AVAudioNodeTap::CheckEmitBuffer` crash signature.
- XcodeGen regenerated the checked-in project at build `7`. Warnings-as-errors generic simulator build, shutdown-iPhone build-for-testing, generic iPhoneOS build, and unsigned Release archive all passed. XCTest compiled but did not execute because no simulator was booted.
- The archive's `Info.plist` reports bundle ID `com.thinkhale.sideleaf`, marketing version `1.0`, build `7`, minimum OS `26.0`, device families `[1, 2]`, microphone and speech usage descriptions, iPhone/iPad AppIcon entries, and Boolean `ITSAppUsesNonExemptEncryption = false`. Its executable is arm64.
- The paired iPhone was offline and no local Sideleaf `.ips` report was available. Installing build `7` and starting the microphone on that phone remains the decisive runtime confirmation.
