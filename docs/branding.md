# Sideleaf branding

The owner supplied the artwork on 2026-09-07. Original PNG files are preserved byte for byte in `public/brand`; no artwork was regenerated, recolored, or resampled.

| Supplied file | Repository asset | Usage |
| --- | --- | --- |
| Sideleaf icon 2.png | `sideleaf-icon.png` | Primary symbol, loading states, web app icon source, native symbol asset |
| Sideleaf icon.png | `sideleaf-icon-alternate.png` | Alternate symbol, retained for future use |
| Sideleaf wordmark.png | `sideleaf-wordmark.png` | Native library toolbar, reusable web wordmark variant |
| Sideleaf logo - no slogan.png | `sideleaf-logo.png` | Web navigation, compact authentication header, native empty page |
| Sideleaf Logo.png | `sideleaf-logo-tagline.png` | Desktop authentication panel |

The full logo's supplied wording is “Good notes. Better Questions.” Native images live in `native/Sources/Assets.xcassets`. The web `Brand` component provides accessible product labels, preserves intrinsic proportions, and falls back to text for an explicitly configured alternative product name.

## Application colors and icons

The interface retains its warm paper background. Supporting brand tokens are navy `#06233c`, sage `#628267`, and gold `#c6a25d`. Functional green controls use `#527358` and the darker `#3d5943` for readable white labels. These are interface colors; the supplied artwork keeps its original pixel colors.

`sideleaf-app-icon.svg` embeds the original primary PNG on paper `#fffdf8` and uses a square view box that reduces transparent outer padding without cutting painted artwork. The favicon and PWA manifest reference it. The original square PNG is also available in the manifest and as the Apple touch icon. Active web brand assets are included in the built service worker's offline cache.

The native source bundles the original assets but does not yet configure a distribution `AppIcon`. The Mac packaging pass needs a valid opaque 1024x1024 PNG export and Xcode validation, as recorded in [native/README.md](../native/README.md). No installed iPadOS PWA or native app icon appearance is claimed as tested.

## Verification

All five public PNGs match their source SHA-256 hashes. The production build and six browser tests passed after integration. Desktop and phone authentication screens and the desktop notebook were visually inspected; additional browser tests exercised phone and both iPad orientations. Details are in [acceptance-tests.md](acceptance-tests.md).
