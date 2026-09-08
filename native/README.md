# Sideleaf native iPhone and iPad feasibility slice

This is native SwiftUI, SwiftData, UIKit and PencilKit source, not a WebView. On September 8, 2026, the app and unit-test products compiled successfully with Xcode 26.6 against the iOS/iPadOS 26.5 simulator SDK. No simulator was booted, so XCTest execution, runtime UI, physical iPhone/iPad, touch-ink and Apple Pencil behavior remain unvalidated.

Source includes a local notebook library and typed page editor, PencilKit ink serialization and PNG preview, native text rectangle hit testing in explicit Mark mode, original-quote preservation, and a SpeechTranscriber hardware/language/installed-asset probe. Model download requires a deliberate button press. The probe does not access the microphone.

## Supplied branding

`Sources/Assets.xcassets` bundles unmodified copies of the supplied artwork as `SideleafSymbol` (`Sideleaf icon 2.png`, 1254 x 1254), `SideleafWordmark` (`Sideleaf wordmark.png`, 2172 x 724), and `SideleafLockup` (`Sideleaf logo - no slogan.png`, 2172 x 724). The library toolbar uses the wordmark and the empty page uses the lockup, with original proportions and colors, accessible product labels, and a light paper background for contrast. The source PNGs retain their transparency and original bytes. `project.yml` includes the asset catalog through its existing `Sources` path.

The distribution `AppIcon` contains a 1024 x 1024 opaque sRGB PNG rendered from the supplied full-bleed dark square at `public/brand/sideleaf-app-icon-dark.png`. It includes the complete navy, sage, white, and gold identity without a baked rounded mask; iOS and iPadOS apply the final mask. `ASSETCATALOG_COMPILER_APPICON_NAME` selects this set for Debug and Release builds. After changing the source artwork, regenerate the icon from `native/` with `swift Scripts/GenerateAppIcon.swift ../public/brand/sideleaf-app-icon-dark.png Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. Apple's [app icon configuration documentation](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) describes the single-image workflow. Final masked appearance still requires Home Screen validation on a simulator or physical device.

The checked-in project opens and builds directly on a Mac with Xcode 26 or later:

```sh
cd native
xcodebuild -project Sideleaf.xcodeproj -scheme Sideleaf -destination 'generic/platform=iOS Simulator' build
```

`project.yml` remains the declarative source for project settings. After changing it, install XcodeGen and run `xcodegen generate`, then commit the regenerated `Sideleaf.xcodeproj` files with the specification change.

The first App Store release uses marketing version `1.0`; the universal iPhone/iPad upload is build `3`. Update `MARKETING_VERSION` for a user-visible release and increment `CURRENT_PROJECT_VERSION` for every App Store Connect upload, then regenerate the checked-in project. A previously uploaded iPad-only build remains iPad-only, so TestFlight must receive build `3` or later before iPhone testers can install it.

For tests, choose an actually installed iPhone or iPad simulator identifier from `xcrun simctl list devices` and pass it as the destination to `xcodebuild test`. No simulator name is assumed. The app target uses the registered bundle identifier `com.thinkhale.sideleaf` with automatic signing for the ThinkHale team. Xcode may need to download or create the matching provisioning profile during the first physical-device build.

## Mac continuation and shared services

`native/Sideleaf.xcodeproj` is checked in so Xcode, CI and fresh clones can build without a generation step. It is generated from `native/project.yml`, which remains the source of truth. The app and test targets support iPhone and iPad (`TARGETED_DEVICE_FAMILY: '1,2'`) with a minimum of iOS/iPadOS 26. iPhone is portrait-only for this release; iPad supports portrait, upside-down portrait and both landscape orientations. Compact-width navigation, controls and finger drawing are adapted in source, but still need simulator and device runtime testing.

The hosted API origin is `https://sideleaf.vercel.app`, with authenticated routes under `/api`. The native source still uses local models and does not yet sign in or synchronize with the hosted notebook. Connect Better Auth sessions and the revision protocol before adding cloud capture or paid access.

- [Hosting and secrets](../docs/hosting-secrets.md) describes the shared API and deployment. Database, OpenAI, Stripe and authentication server secrets stay in Vercel; the native app stores only its user's session credentials securely.
- [Live capture](../docs/live-capture.md) documents the working browser WebRTC flow, server-confirmed transcripts, usage limits, consent and cleanup. Native cloud capture remains to be implemented and validated. The existing on-device readiness probe does not provide this integration.
- [Billing](../docs/billing.md) documents server-authoritative access and Stripe web purchases. Stripe account configuration and sandbox verification are pending. StoreKit purchase verification and native entitlement integration remain unfinished.
- [Implementation status](../docs/status.md) records completed browser/provider checks and remaining native work. A successful native compile does not establish runtime behavior or web/native feature parity.

## Required before calling it a working native client

- Run `AnchorTests` and add UI tests for editing, touch/Pencil tools, compact navigation, persistence, reflow and selection.
- Verify iPhone portrait touch drawing and scrolling, plus iPad rotation, palm rejection, long strokes, Pencil hover, touch scrolling and interruption behavior on real hardware. Browser pointer tests are not native input hardware validation.
- Complete native text phrase actions, annotation undo, ink selection and preparation screens.
- Map the local model to shared multi-block contracts, attach Better Auth session handling, protected token storage and the backend revision protocol.
- Upload only editable native ink plus portable artifacts through owner-authorized artifact routes; define origin/scale metadata and cross-client edit ownership. Those routes do not yet exist.
- Add a bounded on-device capture pipeline and final/interim segment handling without copying the recording and unbounded-stream parts of Apple's sample. Check assets before requesting microphone permission.
- Connect server-authoritative allowances and StoreKit verified entitlements before assisted capture is available.

Sideleaf is the product and target name. Its distribution bundle ID is `com.thinkhale.sideleaf`; SwiftData model names remain unchanged. `OnDeviceReadiness.swift` requires iOS/iPadOS 26. Unsupported hardware or language produces an explicit unavailable result; there is no remote fallback.
