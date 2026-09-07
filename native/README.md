# Sideleaf native iPad feasibility slice

This is native SwiftUI, SwiftData, UIKit and PencilKit source, not a WebView. It has not been compiled or run in this Windows environment. XcodeBuildMCP `list_sims` failed with `spawn xcrun ENOENT`. There was no connected Mac, simulator, iPad or Apple Pencil available for validation.

Source includes a local notebook library and typed page editor, PencilKit ink serialization and PNG preview, native text rectangle hit testing in explicit Mark mode, original-quote preservation, and a SpeechTranscriber hardware/language/installed-asset probe. Model download requires a deliberate button press. The probe does not access the microphone.

## Supplied branding

`Sources/Assets.xcassets` bundles unmodified copies of the supplied artwork as `SideleafSymbol` (`Sideleaf icon 2.png`, 1254 x 1254), `SideleafWordmark` (`Sideleaf wordmark.png`, 2172 x 724), and `SideleafLockup` (`Sideleaf logo - no slogan.png`, 2172 x 724). The library toolbar uses the wordmark and the empty page uses the lockup, with original proportions and colors, accessible product labels, and a light paper background for contrast. The source PNGs retain their transparency and original bytes. `project.yml` includes the asset catalog through its existing `Sources` path.

No `AppIcon` asset is configured. Both supplied square icons are 1254 x 1254 and transparent. During the Mac packaging pass, prepare an approved 1024 x 1024 opaque default PNG from the supplied icon on a solid background, without baked rounded corners, then add and select a valid `AppIcon` asset catalog set. Apple's [app icon configuration documentation](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) describes the single 1024 x 1024 image workflow. This turn does not resample, flatten, redraw, or generate brand artwork. Asset packaging and native layout still require Xcode and simulator validation.

On a Mac with Xcode 26 or later and XcodeGen installed:

```sh
cd native
xcodegen generate
xcodebuild -project Sideleaf.xcodeproj -scheme Sideleaf -destination 'generic/platform=iOS Simulator' build
```

For tests, choose an actually installed iPad simulator identifier from `xcrun simctl list devices` and pass it as the destination to `xcodebuild test`. No simulator name is assumed. Configure your own signing team before a physical-device run. XcodeGen generation itself was not executable here.

## Required before calling it a working native client

- Compile and resolve any Swift 6 isolation, SwiftData, UIKit or SDK availability diagnostics.
- Run `AnchorTests` and add UI tests for editing, Pencil tools, persistence, reflow and selection.
- Verify portrait/landscape, palm rejection, long strokes, Pencil hover, touch scrolling and interruption behavior on real hardware. Browser pointer tests are not Pencil hardware validation.
- Complete native text phrase actions, annotation undo, ink selection and preparation screens.
- Map the local model to shared multi-block contracts, attach Better Auth session handling, protected token storage and the backend revision protocol.
- Upload only editable native ink plus portable artifacts through owner-authorized artifact routes; define origin/scale metadata and cross-client edit ownership. Those routes do not yet exist.
- Add a bounded on-device capture pipeline and final/interim segment handling without copying the recording and unbounded-stream parts of Apple's sample. Check assets before requesting microphone permission.
- Connect server-authoritative allowances and StoreKit verified entitlements before assisted capture is available.

Sideleaf is the product and target name. The existing development bundle ID `dev.meetingnotebook.ipad`, its bundle ID prefix, and SwiftData model names are preserved so this branding change does not deliberately select a new app container or rename persisted models. Choose the final distribution bundle ID before provisioning the app. `OnDeviceReadiness.swift` requires iPadOS 26. Unsupported hardware or language produces an explicit unavailable result; there is no remote fallback.
