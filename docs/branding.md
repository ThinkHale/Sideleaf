# Sideleaf branding

The owner supplied the artwork on 2026-09-07 and the two dedicated square icon treatments on 2026-09-08. All seven original PNG files are preserved byte for byte in `public/brand`; no source artwork was regenerated, recolored, or resampled.

| Supplied file                | Repository asset              | Usage                                                                                                               |
| ---------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Full logo with tagline       | `sideleaf-logo-tagline.png`   | Desktop authentication panel                                                                                        |
| Full logo without tagline    | `sideleaf-logo.png`           | Web navigation, compact authentication header, native empty page                                                    |
| Wordmark                     | `sideleaf-wordmark.png`       | Native library toolbar, reusable web wordmark variant                                                               |
| Alternate transparent symbol | `sideleaf-icon-alternate.png` | Retained for future use                                                                                             |
| Light square icon treatment  | `sideleaf-app-icon-light.png` | Retained as marketing artwork; not used as a platform icon because its rounded tile and shadow are already baked in |
| Primary transparent symbol   | `sideleaf-icon.png`           | Loading states and native symbol asset                                                                              |
| Dark square icon treatment   | `sideleaf-app-icon-dark.png`  | Canonical source for native, favicon, Apple touch, and PWA icons                                                    |

The full logo's supplied wording is “Good notes. Better Questions.” Native images live in `native/Sources/Assets.xcassets`. The web `Brand` component provides accessible product labels, preserves intrinsic proportions, and falls back to text for an explicitly configured alternative product name.

## Application colors and icons

The interface retains its warm paper background. Supporting brand tokens are navy `#06233c`, sage `#628267`, and gold `#c6a25d`. Functional green controls use `#527358` and the darker `#3d5943` for readable white labels. These are interface colors; the supplied artwork keeps its original pixel colors.

The dark square treatment is the platform-icon source because it is opaque, full bleed, and has no baked rounded mask. Its generated 32, 180, 192, and 512 pixel PNGs supply the favicon, Apple touch icon, and PWA manifest. The light square treatment is preserved as a presentation asset only: using its inset rounded tile as an OS icon would create a second mask and excess margin. Active web brand assets are included in the built service worker's offline cache. The older generated `sideleaf-app-icon-legacy.svg` remains only as a historical reference and is no longer shipped in icon metadata.

The native `AppIcon` packages an opaque 1024x1024 sRGB PNG rendered from `sideleaf-app-icon-dark.png`. The app and icon catalog compile-validate in Xcode; final masked appearance still needs Home Screen inspection on a simulator or physical device as recorded in [native/README.md](../native/README.md).

Regenerate every checked-in platform size from the canonical source with:

```sh
swift native/Scripts/GenerateAppIcon.swift public/brand/sideleaf-app-icon-dark.png public/brand/sideleaf-favicon-32.png 32
swift native/Scripts/GenerateAppIcon.swift public/brand/sideleaf-app-icon-dark.png public/brand/sideleaf-apple-touch-icon-180.png 180
swift native/Scripts/GenerateAppIcon.swift public/brand/sideleaf-app-icon-dark.png public/brand/sideleaf-pwa-icon-192.png 192
swift native/Scripts/GenerateAppIcon.swift public/brand/sideleaf-app-icon-dark.png public/brand/sideleaf-pwa-icon-512.png 512
swift native/Scripts/GenerateAppIcon.swift public/brand/sideleaf-app-icon-dark.png native/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

## Verification

All seven original public PNGs match their source SHA-256 hashes. Generated platform sizes are checked for exact dimensions, sRGB color, and opacity. Build and rendered-browser results are recorded in [acceptance-tests.md](acceptance-tests.md).
