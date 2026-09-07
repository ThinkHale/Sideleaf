# Acceptance tests and evidence

The September 7, 2026 implementation and hosted verification results are recorded in [status.md](status.md), including the 106-test suite, browser/focus checks, built-PWA check, production Supabase integration and hosted real OpenAI transcription with synthetic microphone input. The dated results below preserve the earlier baseline and its narrower scope.

Recorded 2026-09-06 on Windows, Node 24.18.0. No test results below represent a Mac simulator, physical iPad, Apple Pencil, live microphone provider, real billing account, or production database run.

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
| Preparation                  | Discovery template fills empty fields, participants persist, consent enables readiness check, unavailable capture is explained, preparation survives reopening.                                            |
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
- Generic participant-label selection matched the consent checkbox in a test. The test now uses the exact field label.
- Development sign-up tests exceeded Better Auth's default route rate limit. Local-only auth has an explicit 30-per-minute limit; production retains the maintained default rules.

## Not tested or not implemented

Real prepare/start/pause/resume/end/reopen transcription; live notes/keywords/coaching; stale text-model outputs; summary grounding and summary editing; captured interruption gaps; server usage leases and billing webhooks; payments/restore purchases; native compilation and UI; live Pencil hardware; external PostgreSQL TLS; Docker build; installed-PWA behavior on Safari/iPadOS; browser storage exhaustion; very large notebooks; deployment/backup retention.

These are acceptance gaps, not passes. The exact next implementation steps are in `status.md`.

The concept-to-render comparison, copy differences, and intentional design deviations are recorded in [design-review.md](design-review.md).

## Supplied branding verification, 2026-09-07

- `npm run build` passed after integration of the supplied artwork.
- `npm run test:e2e` passed all five Chromium workflows, including desktop, phone and iPad browser dimensions.
- `npx playwright test --config playwright.pwa.config.ts` passed the built PWA offline reload, recovered draft synchronization and print exclusion workflow.
- An additional authentication layout check at 1536x1024 and 390x844 found no horizontal overflow or page errors. Visible logo images decoded at their expected original dimensions. Screenshots are `sideleaf-auth-desktop.png` and `sideleaf-auth-phone.png` in `%TEMP%/meeting-notebook-qa`.
- The current desktop notebook and both authentication screenshots were opened and visually inspected. The supplied lockups retain their proportions and remain legible against the paper surfaces.
- SHA-256 comparison confirmed that all five files in `public/brand` match their supplied source PNGs byte for byte. The SVG web app icon embeds the original primary PNG on a paper background.
- Native asset references and original bytes were checked, but native rendering and app icon packaging are not validated on this Windows host.
