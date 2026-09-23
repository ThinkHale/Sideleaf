# Sideleaf native iPhone, iPad and Apple Watch source

This is native SwiftUI, SwiftData, UIKit and PencilKit source, not a WebView. Build `8` targets iPhone and iPad on iOS/iPadOS 26 under `com.thinkhale.sideleaf`, and adds two products alongside the app: a WidgetKit extension (`com.thinkhale.sideleaf.widget`) and a watchOS companion (`com.thinkhale.sideleaf.watchkitapp`). Build `8` was written on a Linux session with no Swift toolchain, no Xcode, no simulator and no device. Xcode Cloud build 14 has since compiled and archived it with no errors, confirming that every target builds and that the bundle layout, background mode and watch companion metadata are right; it then failed at export because the new bundle identifiers and the App Group are not registered with Apple. Nothing has run: no test has executed and no build has launched on a simulator, phone or watch. Earlier builds were validated compile-only; runtime UI, physical iPhone/iPad, touch ink, Apple Pencil, microphone, widget and watch behavior all remain unvalidated.

Source includes a local notebook library and typed page editor, PencilKit ink serialization and PNG preview, native text rectangle hit testing in explicit Mark mode, and original-quote preservation. It includes email/password sign-in through the Sideleaf backend, a signed Better Auth bearer and last server-confirmed Terms version stored together in Keychain, and revision-based synchronization for typed text and semantic marks. It preserves the rest of each shared remote document rather than replacing unknown blocks or web ink. PencilKit freehand ink remains device-only, and guest pages require an explicit adoption action before they are uploaded to an account.

Account controls include permanent server account deletion from both the connected and Terms-review-required states. Deletion requires a destructive confirmation, may require a fresh sign-in, and is rejected while billing remains active. After the server confirms deletion, Sideleaf clears the session and removes that account's cached pages from the device while preserving unrelated device-only drafts.

Build `7` includes iOS/iPadOS 26 on-device live transcription. Current builds require a server-recorded Terms acceptance and recording-law responsibility acknowledgement before live transcription is available, then show a passive responsibility reminder instead of a per-use consent toggle. Microphone access still requires an explicit Start action and the operating-system permissions. Microphone buffers are processed in memory by Apple's speech APIs and are neither saved as audio files nor uploaded; the resulting text can be saved and synchronized as user-authored personal content, not as a server-confirmed cloud transcript. Physical-device microphone, interruption and transcription behavior still require validation.

Build `5` fixes a live-transcription failure that could end or crash a session the moment recording started. `AVAudioEngineConfigurationChange` is posted routinely, including while the route settles after the audio session is activated, and the previous handler treated every one of those notifications as fatal: it discarded the engine reference while that engine was still running with an installed input tap. The handler now reconnects the tap on the still-valid engine instead, rate-limited so a route that keeps changing ends the session cleanly rather than looping. Only a media-services reset replaces the engine object, and the running engine is always stopped and untapped before it is released. Capture buffers are pooled with headroom because `installTap` may deliver more frames than the size requested, the pool reference is lock-guarded so it can be swapped during a reconnect without racing the render thread, and `setActive(true)` no longer passes the deactivation-only `notifyOthersOnDeactivation` option. This build has not been run on physical hardware; the crash fix is reasoned from the audio-engine contract and still needs device verification.

Build `6` also removes the old tap before reading the post-route-change format, validates both the hardware and output formats, and derives a 120 ms tap size from the active sample rate. That keeps built-in and Bluetooth routes inside AVAudioNode's documented 100–400 ms range and avoids reusing a stale explicit format that can trigger an AVFAudio assertion. This remains a reasoned fix until the exact physical-device path passes or an `.ips` report confirms the prior signature.

Build `7` addresses a separate Swift 6 isolation trap in the live microphone callback. Because `LiveTranscription` is main-actor isolated, its unannotated AVAudioEngine tap closure inherited main-actor isolation even though AVFoundation invokes that closure on a real-time audio queue. The callback is now explicitly `@Sendable` and captures only the thread-safe bridge, preventing `_swift_task_checkIsolatedSwift` from terminating the app on the first microphone buffer. [Apple Developer Technical Support documents this exact `AVAudioNodeTap::CheckEmitBuffer` failure and workaround](https://developer.apple.com/forums/thread/793455). Generic simulator and iPhoneOS builds pass with warnings treated as errors; physical-device confirmation remains required.

## Build 8: the meeting is the product

The app used to open on a notebook with a microphone button in the corner, which made Sideleaf read as a note app that can also transcribe. Build `8` inverts that. Sideleaf opens on a meeting; typing and ink are the second tab.

- **Meeting tab.** One Start action, a kind (meeting, interview, class, one to one, call) and an optional minute of planning: what you want out of the conversation and the points that have to be covered.
- **Live view.** Questions to ask now come first, what Sideleaf is keeping for you comes second, the plan points still uncovered come third, and the raw transcript is collapsed at the bottom. Each suggestion carries the sentence it came from and can be asked, kept or dismissed in one tap.
- **Recap.** Stopping opens a review rather than a save dialog: edit any line, leave anything out, add reminders, then write it to a page.
- **Notes tab.** The previous library, page editor, Type/Write/Mark/Select/Erase tools and PencilKit ink, unchanged. Its microphone button now starts a meeting attached to that page.

`Sources/MeetingIntelligence.swift` turns transcript text into those suggestions with written rules over the words that were actually said: first-person commitments, requests made of someone, decisions, named dates (`Sources/MeetingDates.swift`), questions that never got a substantive answer, blockers, vague timing and quantities, figures worth reading back, unexplained acronyms, and plan points that have not come up. It is deterministic, runs on device, keeps the source sentence for every cue, and applies per-kind cooldowns and duplicate suppression so the live view stays quiet. Nothing here is a model inference, which keeps the existing product rule that questions use a clearly user-owned starter rather than AI inference.

Suggestions are not frozen once they appear. Every new sentence is offered to everything still open before it is read for anything new, so a question the room answers stops being asked, a vague "at some point" closes the moment someone says Friday, a commitment picks up the date named two sentences later, an acronym closes when it is explained, a blocker closes when it is cleared, a plan point retires when it is covered, and a decision is marked as reversed when someone takes it back. A cue is only ever closed by words that were actually said, and those words are kept on the cue, so the live view and the recap both show why Sideleaf changed its mind and offer a one-tap way to disagree ("Ask anyway", "Still open"). The recap follows: answered questions move under their own heading instead of the list of things to send, reversed decisions are not listed as decisions, and points covered late are not listed as gaps.

Sideleaf also takes the person's verdict seriously. Asking, keeping or dismissing a suggestion is fed back to the engine: dismissals stretch that kind's cooldown, and three dismissals of one kind with nothing kept stops that kind for the rest of the meeting. `MeetingCuePreferences` keeps the same tally across meetings in the shared container and stops offering a kind after six lifetime dismissals with nothing ever kept. This is a counter, not a model. It is visible on the meeting screen, which names every kind it has stopped offering and gives one tap to bring it back or to forget the tally entirely.

Saving a recap appends plain text to the page's typed notes and anchors each kept item to the exact words it came from, using the shared document contract's `follow-up`, `action` and `important` marks. A follow-up captured on iPhone therefore appears in the browser margin with its source quote intact, through the existing revision-based sync path. No new server route, schema or migration is involved.

Reminders are local notifications scheduled by `UNUserNotificationCenter` from the recap, defaulting to a date Sideleaf resolved from the conversation. They are opt-in per item and never leave the device.

## Telling your voice from the room's

Every useful thing a meeting produces belongs to someone, and until build `8` Sideleaf assumed it all belonged to the person holding the phone. A promise the client made read as a task you owed. Cues that describe work now carry an owner: a promise belongs to whoever made it, a request to whoever it was made of, and the recap splits "Your next steps" from "What they owe you".

Who is speaking comes from an optional voice profile, recorded once in Settings under "Your voice". It takes about 25 seconds of ordinary speech. `SpeakerRecognizing` is the seam; `FluidAudioSpeakerRecognizer` is the only file that imports the speech library, and the model lives inside an actor so Core ML inference never touches the main actor.

There is no Apple API for this. `SpeechAnalyzer` on iOS 26 exposes `SpeechTranscriber` and `SpeechDetector` and neither returns who was talking, so attribution uses [FluidAudio](https://github.com/FluidInference/FluidAudio) (Sortformer: four stable speaker slots, pyannote and WeSpeaker models compiled for the Neural Engine). It is the native app's first third-party dependency, pinned to its minor series in `project.yml` because the library is pre-1.0.

AVAudioEngine allows one tap per bus and the transcriber owns it, so attribution never installs its own. `LiveTranscription` hands every buffer to the transcriber first and then copies it into `VoiceAudioSink`, a bounded ring buffer that follows the same rules the microphone crash fixes established: the render thread never waits on its lock, never allocates, and drops a buffer rather than stalling. With no voice profile recorded, nothing is attached at all and the capture path is byte for byte what it was.

Attribution is deliberately reticent. It answers for the stretch of audio that produced the text being read, allowing for how far a finalised transcript trails the room, and returns nothing at all unless one voice held at least 70 per cent of that window. Anything it will not answer stays marked "Assumed yours" and is one tap from being moved.

The voice profile is the one recording Sideleaf keeps. It sits in the app container with complete file protection and is deleted from the same settings screen. Meeting audio is still never written to disk, and the microphone purpose string now says both of those things. Other people in the room are told apart from you for the length of the meeting and are never enrolled or stored.

## Home Screen widget, Control Center and Siri

`Widget/` builds `SideleafWidget.appex`: a configurable Home Screen widget (small, medium and large), Lock Screen widgets (rectangular, circular and inline) and an iOS control for Control Center, the Lock Screen and the Action button. Idle, it offers Start for the kind the widget is configured with. Live, it shows the elapsed time, how many questions are waiting, the newest question and an End button.

A widget process cannot open a microphone, so `StartMeetingIntent` and `StopMeetingIntent` set `openAppWhenRun` and record the request in the shared App Group; the app performs it when it comes forward. `Sources/SideleafShortcuts.swift` exposes the same two intents to Siri and Shortcuts.

The widget reads `MeetingSnapshot`, a small record holding the phase, title, elapsed start, counts, the top few questions and the uncovered plan points. It never holds the transcript. A snapshot older than fifteen minutes is treated as stale and the widget falls back to its idle face, so an interrupted app cannot leave a timer running on the Home Screen.

## Apple Watch companion

`Watch/` builds a single-target watchOS app. The iPhone keeps the microphone and the cue engine; the watch is a remote control and a second screen. It offers Start with a kind, End, "Mark this moment", and the same top questions with an Asked button, and it taps the wrist when a new question arrives. Messages cross WatchConnectivity as JSON payloads, so only `Sendable` values cross a thread boundary; the transcript is never sent to the watch. When the phone is unreachable, a request falls back to `transferUserInfo` and the watch says so instead of pretending the meeting started.

## Before build 8 can be exported

Xcode Cloud, and automatic signing generally, never registers identifiers or capabilities with Apple. These five entries must exist in the Apple Developer portal first, or every export flavour fails:

1. App ID `com.thinkhale.sideleaf.widget` (explicit), with App Groups enabled.
2. App ID `com.thinkhale.sideleaf.watchkitapp` (explicit). It needs no capabilities; the watch target carries no entitlements.
3. App Group `group.com.thinkhale.sideleaf`.
4. App Groups enabled on the existing `com.thinkhale.sideleaf` identifier, with that group assigned.
5. The same group assigned to `com.thinkhale.sideleaf.widget`.

An embedded watch app needs no separate App Store Connect record; it ships inside the iPhone app.

## Capability and entitlement requirements

Build `8` needs three capabilities the earlier builds did not:

- **App Groups** (`group.com.thinkhale.sideleaf`) on the app and the widget, declared in `Support/Sideleaf.entitlements` and `Support/SideleafWidget.entitlements`. The group must be created for the team in the Apple Developer portal, or automatic signing will fail. Build 14 proved this the hard way: exporting an archive that carries the entitlement fails with "Automatic signing cannot update bundle identifier" until the capability is enabled on the identifier, and that failure blocks the iPhone app too, not only the widget. `MeetingSharedStore` degrades to a private container rather than crashing if the entitlement is missing; the widget then only ever shows its idle face.
- **Background audio** (`UIBackgroundModes`, `Support/Sideleaf-Info.plist`), so a meeting keeps listening when the screen locks. Confirm the built `Info.plist` contains `UIBackgroundModes` as an array with `audio`, and confirm App Review expectations for a continuously listening app before submitting.
- **Notifications**, requested the first time someone adds a reminder from a recap.

`Support/` holds the Info.plist fragments and entitlements for all three targets. Each target also keeps `GENERATE_INFOPLIST_FILE`, so Xcode merges its generated keys into these files.

## Supplied branding

`Sources/Assets.xcassets` bundles unmodified copies of the supplied artwork as `SideleafSymbol` (`Sideleaf icon 2.png`, 1254 x 1254), `SideleafWordmark` (`Sideleaf wordmark.png`, 2172 x 724), and `SideleafLockup` (`Sideleaf logo - no slogan.png`, 2172 x 724). The library toolbar uses the wordmark and the empty page uses the lockup, with original proportions and colors, accessible product labels, and a light paper background for contrast. The source PNGs retain their transparency and original bytes. `project.yml` includes the asset catalog through its existing `Sources` path.

The distribution `AppIcon` contains a 1024 x 1024 opaque sRGB PNG rendered from the supplied full-bleed dark square at `public/brand/sideleaf-app-icon-dark.png`. It includes the complete navy, sage, white, and gold identity without a baked rounded mask; iOS and iPadOS apply the final mask. `ASSETCATALOG_COMPILER_APPICON_NAME` selects this set for Debug and Release builds. After changing the source artwork, regenerate the icon from `native/` with `swift Scripts/GenerateAppIcon.swift ../public/brand/sideleaf-app-icon-dark.png Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. Apple's [app icon configuration documentation](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) describes the single-image workflow. Final masked appearance still requires Home Screen validation on a simulator or physical device.

The checked-in project opens and builds directly on a Mac with Xcode 26 or later:

```sh
cd native
xcodegen generate
xcodebuild -project Sideleaf.xcodeproj -scheme Sideleaf -destination 'generic/platform=iOS Simulator' build
```

The `Sideleaf` scheme builds the widget extension and the watch app as embedded dependencies. The watch app also builds on its own with `-scheme SideleafWatch -destination 'generic/platform=watchOS Simulator'`.

`project.yml` remains the declarative source for project settings. After changing it, install XcodeGen and run `xcodegen generate`, then commit the regenerated `Sideleaf.xcodeproj` files with the specification change.

The checked-in `project.pbxproj` for build `8` was written without XcodeGen, because the session that added the widget and watch targets had no Swift toolchain. Its object graph was validated structurally (every identifier defined once and referenced, sections balanced, no orphans), but it has not been opened by Xcode. Run `xcodegen generate` first on a Mac and commit the result; treat `project.yml` as authoritative if the two ever disagree.

The first App Store release uses marketing version `1.0`; the current candidate is build `8`. Update `MARKETING_VERSION` for a user-visible release and increment `CURRENT_PROJECT_VERSION` for every App Store Connect upload, keeping the app, widget and watch targets on the same numbers, then regenerate the checked-in project. Previously uploaded builds do not inherit later iPhone, sync, legal or microphone fixes.

The checked-in project declares build `8`, bundle IDs `com.thinkhale.sideleaf`, `com.thinkhale.sideleaf.widget` and `com.thinkhale.sideleaf.watchkitapp`, marketing version `1.0`, minimum OS `26.0` on both platforms, device families `[1, 2]` for iOS and `[4]` for watchOS, microphone and speech usage descriptions, and iPhone/iPad AppIcon entries. The watch app carries the same 1024 x 1024 opaque sRGB artwork as the iPhone app, in `Watch/Assets.xcassets`, because App Store distribution refuses an archive whose embedded watch app has no icon. It also sets the Boolean `ITSAppUsesNonExemptEncryption` value to `false`, which answers App Store Connect's export-compliance prompt for the current app's OS-provided HTTPS and Keychain use. Export compliance remains the owner's responsibility: reassess that declaration before release if native cryptography, a cryptographic SDK, VPN behavior or other encryption capability is added.

For tests, choose an actually installed iPhone or iPad simulator identifier from `xcrun simctl list devices` and pass it as the destination to `xcodebuild test`. No simulator name is assumed. The app target uses the registered bundle identifier `com.thinkhale.sideleaf` with automatic signing for the ThinkHale team. Xcode may need to download or create the matching provisioning profile during the first physical-device build.

## Mac continuation and shared services

`native/Sideleaf.xcodeproj` is checked in so Xcode, CI and fresh clones can build without a generation step. It is generated from `native/project.yml`, which remains the source of truth. The app and test targets support iPhone and iPad (`TARGETED_DEVICE_FAMILY: '1,2'`) with a minimum of iOS/iPadOS 26. iPhone is portrait-only for this release; iPad supports portrait, upside-down portrait and both landscape orientations. Compact-width navigation, controls and finger drawing are adapted in source, but still need simulator and device runtime testing.

The hosted API origin is `https://sideleaf.vercel.app`, with authenticated routes under `/api`. Native email/password requests use that backend rather than connecting directly to Supabase. Better Auth returns a signed bearer. The bearer, cached account identity and last server-confirmed Terms version are treated as one session state in device-only Keychain records and are cleared together on sign-out or invalidation; the cached identity can reopen that account's local pages while offline but cannot authorize API access. Unsafe API requests also send the expected hosted origin. Signed-in pages use the backend's base-version and stable-mutation-ID protocol, retain an account-scoped local copy during network failures and preserve both sides of a conflict for recovery. Hosted deployment and physical-device verification of this build remain pending.

- [Hosting and secrets](../docs/hosting-secrets.md) describes the shared API and deployment. Database, OpenAI, Stripe and authentication server secrets stay in Vercel; the native app stores only its user's session credentials securely.
- [Live capture](../docs/live-capture.md) distinguishes the working browser WebRTC flow from native on-device transcription. Native audio does not use the cloud capture routes or provider allowance, and physical-device audio behavior remains unverified.
- [Billing](../docs/billing.md) documents server-authoritative access and Stripe web purchases. Stripe account configuration and sandbox verification are pending. StoreKit purchase verification and native entitlement integration remain unfinished.
- [Implementation status](../docs/status.md) records completed browser/provider checks and remaining native work. A successful native compile does not establish runtime behavior or web/native feature parity.

## Required before calling it a working native client

- Run `AnchorTests` and add UI tests for editing, touch/Pencil tools, compact navigation, persistence, reflow and selection.
- Verify iPhone portrait touch drawing and scrolling, plus iPad rotation, palm rejection, long strokes, Pencil hover, touch scrolling and interruption behavior on real hardware. Browser pointer tests are not native input hardware validation.
- Complete native text phrase actions, annotation undo, ink selection and preparation screens.
- Validate build `7` sign-in restoration, legal-version transitions, Keychain cleanup, explicit guest-page adoption, reconnect retries and two-client conflict recovery against the hosted API.
- Upload only editable native ink plus portable artifacts through owner-authorized artifact routes; define origin/scale metadata and cross-client edit ownership. Those routes do not yet exist.
- Validate the bounded on-device transcription pipeline on physical iPhone and iPad hardware, including permission denial, model availability, interruptions, route changes, backgrounding, finalization and microphone release.
- Exercise voice attribution on a device with two people in the room, which is the only way to know whether it works. Nothing about it has run. The adapter was written against FluidAudio's documented signatures without the library present, so `FluidAudioSpeakerRecognizer` is the first file to check if the build breaks, and `SpeakerSpan.identifier` is the specific line to check if attribution compiles but never matches: it compares whatever `segment.speakerId` describes itself as against the name the profile was enrolled under, and the settings screen prints the identifiers actually heard so the real format is visible.
- Confirm the audio fan-out costs the transcriber nothing: a meeting with a profile enrolled should transcribe exactly as well as one without.
- Check that the 70 per cent threshold and the 1.5 second transcript lag are right on real speech. Both are named constants in `FluidAudioSpeakerRecognizer` and `MeetingSession`, and both were chosen by reasoning rather than measurement.
- Run `MeetingIntelligenceTests`, `MeetingDatesTests` and `MeetingRecapTests` in a booted simulator, then judge the cue rules against real conversations. The tests fix the contract; only listening to actual meetings shows whether the suggestions are worth reading.
- Create the `group.com.thinkhale.sideleaf` App Group for the team and confirm the widget reads live meeting state from a device rather than falling back to its idle face.
- Confirm the built `Info.plist` carries `UIBackgroundModes` as an array containing `audio`, then verify a meeting survives a locked screen, an incoming call and a Bluetooth route change, and that the microphone is released when it ends.
- Verify the watch companion against a paired watch: start and stop from the wrist, the fallback when the phone is unreachable, haptics on a new question, and that starting from the watch while the phone is backgrounded either works or says plainly that it could not.
- Confirm reminders fire, and that the recap's marks appear in the browser margin with their source quotes after the page syncs.
- Connect server-authoritative allowances and StoreKit verified entitlements before assisted capture is available.

Build `8` adds two optional properties to the `LocalPage` SwiftData model, `meetingKind` and `meetingEndedAt`, so the meeting tab can list recent meetings. Adding optional attributes is a lightweight migration, but it has not been exercised against a store created by an earlier build; verify that an upgrade over an existing install keeps its pages before shipping.

Sideleaf is the product and target name. Its distribution bundle ID is `com.thinkhale.sideleaf`; SwiftData model names remain unchanged. Native speech requires iOS/iPadOS 26. Unsupported hardware, permissions, language or model availability produces an explicit unavailable result; there is no remote transcription fallback.
