# Sideleaf native iPhone and iPad feasibility slice

This is native SwiftUI, SwiftData, UIKit and PencilKit source, not a WebView. On September 8, 2026, XcodeGen regenerated the checked-in project for build `4`. Build-for-testing succeeded against shutdown iPhone 17 Pro and iPad Pro simulator destinations, compiling both the app and XCTest products, and an unsigned generic iOS Release archive succeeded. No simulator was booted, so XCTest did not execute; runtime UI, physical iPhone/iPad, touch-ink, Apple Pencil and microphone behavior remain unvalidated.

Source includes a local notebook library and typed page editor, PencilKit ink serialization and PNG preview, native text rectangle hit testing in explicit Mark mode, and original-quote preservation. Build `4` adds email/password sign-in through the Sideleaf backend, a signed Better Auth bearer stored in Keychain, and revision-based synchronization for typed text and semantic marks. It preserves the rest of each shared remote document rather than replacing unknown blocks or web ink. PencilKit freehand ink remains device-only, and guest pages require an explicit adoption action before they are uploaded to an account.

Build `4` also adds iOS/iPadOS 26 on-device live transcription. The user must confirm participant consent before Sideleaf requests microphone and speech access. Microphone buffers are processed in memory by Apple's speech APIs and are neither saved as audio files nor uploaded; the resulting text can be saved and synchronized as user-authored personal content, not as a server-confirmed cloud transcript. Physical-device microphone, interruption and transcription behavior still require validation.

Build `5` fixes a live-transcription failure that could end or crash a session the moment recording started. `AVAudioEngineConfigurationChange` is posted routinely, including while the route settles after the audio session is activated, and the previous handler treated every one of those notifications as fatal: it discarded the engine reference while that engine was still running with an installed input tap. The handler now reconnects the tap on the still-valid engine instead, rate-limited so a route that keeps changing ends the session cleanly rather than looping. Only a media-services reset replaces the engine object, and the running engine is always stopped and untapped before it is released. Capture buffers are pooled with headroom because `installTap` may deliver more frames than the size requested, the pool reference is lock-guarded so it can be swapped during a reconnect without racing the render thread, and `setActive(true)` no longer passes the deactivation-only `notifyOthersOnDeactivation` option. This build has not been run on physical hardware; the crash fix is reasoned from the audio-engine contract and still needs device verification.

## Supplied branding

`Sources/Assets.xcassets` bundles unmodified copies of the supplied artwork as `SideleafSymbol` (`Sideleaf icon 2.png`, 1254 x 1254), `SideleafWordmark` (`Sideleaf wordmark.png`, 2172 x 724), and `SideleafLockup` (`Sideleaf logo - no slogan.png`, 2172 x 724). The library toolbar uses the wordmark and the empty page uses the lockup, with original proportions and colors, accessible product labels, and a light paper background for contrast. The source PNGs retain their transparency and original bytes. `project.yml` includes the asset catalog through its existing `Sources` path.

The distribution `AppIcon` contains a 1024 x 1024 opaque sRGB PNG rendered from the supplied full-bleed dark square at `public/brand/sideleaf-app-icon-dark.png`. It includes the complete navy, sage, white, and gold identity without a baked rounded mask; iOS and iPadOS apply the final mask. `ASSETCATALOG_COMPILER_APPICON_NAME` selects this set for Debug and Release builds. After changing the source artwork, regenerate the icon from `native/` with `swift Scripts/GenerateAppIcon.swift ../public/brand/sideleaf-app-icon-dark.png Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. Apple's [app icon configuration documentation](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) describes the single-image workflow. Final masked appearance still requires Home Screen validation on a simulator or physical device.

The checked-in project opens and builds directly on a Mac with Xcode 26 or later:

```sh
cd native
xcodebuild -project Sideleaf.xcodeproj -scheme Sideleaf -destination 'generic/platform=iOS Simulator' build
```

`project.yml` remains the declarative source for project settings. After changing it, install XcodeGen and run `xcodegen generate`, then commit the regenerated `Sideleaf.xcodeproj` files with the specification change.

The first App Store release uses marketing version `1.0`; the authentication, synchronization and on-device transcription update is build `4`. Update `MARKETING_VERSION` for a user-visible release and increment `CURRENT_PROJECT_VERSION` for every App Store Connect upload, then regenerate the checked-in project. The previously uploaded iPad-only build remains iPad-only; TestFlight must receive build `5` for the native connectivity and transcription changes described here.

The checked-in project declares build `5`; the last archive that was actually produced and inspected was build `4`. That archive reported `com.thinkhale.sideleaf`, version `1.0` (`4`), minimum OS `26.0`, device families `[1, 2]`, microphone and speech usage descriptions, and iPhone/iPad AppIcon entries. It also sets the Boolean `ITSAppUsesNonExemptEncryption` value to `false`, which answers App Store Connect's export-compliance prompt for the current app's OS-provided HTTPS and Keychain use. Export compliance remains the owner's responsibility: reassess that declaration before release if native cryptography, a cryptographic SDK, VPN behavior or other encryption capability is added.

For tests, choose an actually installed iPhone or iPad simulator identifier from `xcrun simctl list devices` and pass it as the destination to `xcodebuild test`. No simulator name is assumed. The app target uses the registered bundle identifier `com.thinkhale.sideleaf` with automatic signing for the ThinkHale team. Xcode may need to download or create the matching provisioning profile during the first physical-device build.

## Mac continuation and shared services

`native/Sideleaf.xcodeproj` is checked in so Xcode, CI and fresh clones can build without a generation step. It is generated from `native/project.yml`, which remains the source of truth. The app and test targets support iPhone and iPad (`TARGETED_DEVICE_FAMILY: '1,2'`) with a minimum of iOS/iPadOS 26. iPhone is portrait-only for this release; iPad supports portrait, upside-down portrait and both landscape orientations. Compact-width navigation, controls and finger drawing are adapted in source, but still need simulator and device runtime testing.

The hosted API origin is `https://sideleaf.vercel.app`, with authenticated routes under `/api`. Native email/password requests use that backend rather than connecting directly to Supabase. Better Auth returns a signed bearer. The bearer and cached account identity are treated as one session state in device-only Keychain records and are cleared together on sign-out or invalidation; the cached identity can reopen that account's local pages while offline but cannot authorize API access. Unsafe API requests also send the expected hosted origin. Signed-in pages use the backend's base-version and stable-mutation-ID protocol, retain an account-scoped local copy during network failures and preserve both sides of a conflict for recovery. Hosted deployment and physical-device verification of this build remain pending.

- [Hosting and secrets](../docs/hosting-secrets.md) describes the shared API and deployment. Database, OpenAI, Stripe and authentication server secrets stay in Vercel; the native app stores only its user's session credentials securely.
- [Live capture](../docs/live-capture.md) distinguishes the working browser WebRTC flow from native on-device transcription. Native audio does not use the cloud capture routes or provider allowance, and physical-device audio behavior remains unverified.
- [Billing](../docs/billing.md) documents server-authoritative access and Stripe web purchases. Stripe account configuration and sandbox verification are pending. StoreKit purchase verification and native entitlement integration remain unfinished.
- [Implementation status](../docs/status.md) records completed browser/provider checks and remaining native work. A successful native compile does not establish runtime behavior or web/native feature parity.

## Required before calling it a working native client

- Run `AnchorTests` and add UI tests for editing, touch/Pencil tools, compact navigation, persistence, reflow and selection.
- Verify iPhone portrait touch drawing and scrolling, plus iPad rotation, palm rejection, long strokes, Pencil hover, touch scrolling and interruption behavior on real hardware. Browser pointer tests are not native input hardware validation.
- Complete native text phrase actions, annotation undo, ink selection and preparation screens.
- Validate build `4` sign-in restoration, Keychain cleanup, explicit guest-page adoption, reconnect retries and two-client conflict recovery against the hosted API.
- Upload only editable native ink plus portable artifacts through owner-authorized artifact routes; define origin/scale metadata and cross-client edit ownership. Those routes do not yet exist.
- Validate the bounded on-device transcription pipeline on physical iPhone and iPad hardware, including permission denial, model availability, interruptions, route changes, backgrounding, finalization and microphone release.
- Connect server-authoritative allowances and StoreKit verified entitlements before assisted capture is available.

Sideleaf is the product and target name. Its distribution bundle ID is `com.thinkhale.sideleaf`; SwiftData model names remain unchanged. Native speech requires iOS/iPadOS 26. Unsupported hardware, permissions, language or model availability produces an explicit unavailable result; there is no remote transcription fallback.
