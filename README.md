# Sideleaf

A working beta of an AI-assisted meeting notebook. It provides authenticated notes, preparation, editable ink, semantic text marking, versioned saves, offline recovery, exports, and live OpenAI transcription. Server-enforced allowances and Stripe Checkout/portal are implemented; purchases await Stripe account configuration and sandbox verification.

Product repository: [ThinkHale/Sideleaf](https://github.com/ThinkHale/Sideleaf). Sideleaf is the product name; `PRODUCT_NAME` can override the runtime display name. The supplied Sideleaf logo package is integrated into the web app and native source. Asset mappings and usage are recorded in [branding.md](docs/branding.md).

The hosted notebook beta is live at [sideleaf.vercel.app](https://sideleaf.vercel.app). One Vercel project serves the web app and Hono API, with Supabase Postgres for data and Better Auth for accounts. Verified database TLS and live account, persistence, conflict, ownership, export and deletion checks have passed. Shared web/native credential locations and the Mac handoff are described in [hosting-secrets.md](docs/hosting-secrets.md).

## Run locally

Node.js 24 is required. From this repository:

```powershell
npm ci
npm run dev
```

Open http://127.0.0.1:5173. Create a local account, then create a blank page or choose the explicitly labeled synthetic example. No cloud credentials are needed for this slice. The frontend reloads automatically; restart `npm run dev` after backend edits.

The API listens on 127.0.0.1:3001. Development uses actual embedded PostgreSQL through PGlite, with Better Auth account/session persistence. Data and the generated development authentication secret live under `%LOCALAPPDATA%/MeetingNotebook/<checkout-hash>/`, outside the OneDrive source tree. `APP_DATA_DIR` overrides this location. On other operating systems the default base is `~/.local/share`. Do not run two API processes against the same embedded database.

The original `MeetingNotebook` data-directory name and `meeting-notebook-v1` IndexedDB name are intentionally retained so the Sideleaf rename preserves existing accounts, notes, and offline drafts.

To try the built PWA and offline reload, stop the development server first:

```powershell
npm run build
npm run preview
```

Then open http://127.0.0.1:3001. `preview` serves the built assets with local development authentication. It does not enable cloud features. Visit once online before going offline. Creating an account or notebook still needs the API; creating pages in an existing cached notebook and editing manual notes can work offline.

## Implemented

- Better Auth sign-up/sign-in locally, explicit email/password opt-in for the hosted beta, isolated accounts, optional Google authentication configuration, and server-enforced ownership. Hosted authentication rate limits use database storage shared across Vercel instances.
- Notebooks, pages, typed notes, heading blocks, basic pressure-bearing ink data, drawing, erasing, moving individual ink strokes, undo/redo, search, and preparation templates.
- Explicit Type, Write, Mark, Select, and Erase tools. Write circles are ordinary ink. Mark circles select enclosed words and create independently stored semantic marks. Mouse, touch pointer events, keyboard text selection, and keyboard ink movement are supported in source; see the tested platforms below.
- Important marks, editable follow-up questions and action drafts, addressed/dismissed/later states, and at most two open questions in the margin. Questions use a clearly user-owned deterministic starter, not AI inference.
- IndexedDB drafts, debounced server saves, compare-and-swap versions, idempotency keys, retained revision history, and a conflict flow that keeps both pages. Cross-tab draft displacement is retained in device recovery.
- Markdown, plain text, account JSON, and print/PDF. Excluded notes and their marks are omitted from ordinary exports, while full data export retains them. PDF renders ink separately from reflowed text.
- Responsive library, notebook, preparation and settings; centered focus mode; accurate microphone status; keyboard labels and reduced-motion handling.
- Live microphone transcription over WebRTC, server-confirmed transcript storage, pause/resume, connection cleanup and authenticated usage accounting. No saved audio recordings or offline audio queue.
- Free and Pro plan UI, server-authoritative entitlements, Stripe Checkout, customer portal, signed webhooks, cancellation and refund handling. Payments stay disabled until Stripe is configured.
- Native SwiftUI/SwiftData/PencilKit source, native anchor tests, and a SpeechTranscriber device/language/asset readiness probe. The iPad app and test products compile with Xcode 26.6; simulator runtime and physical-device validation remain.

## Verification commands

```powershell
npm run check
npm run test:e2e
npm run test:pwa
```

Install the test browser once with `npx playwright install chromium`. `test:e2e` can reuse the running development server. `test:pwa` starts a separate built app on port 4173 with its own temporary database. Test accounts use synthetic `example.test` addresses. Test images/PDFs are written under the operating system temporary directory in `meeting-notebook-qa`.

`npm run format` formats the web, API, contracts, tests and documentation. The local SQL migration `server/migrations/001_notebook.sql` is applied at development startup. `npm run db:migrate` applies that local/general PostgreSQL migration explicitly while the embedded API is stopped. Hosted Supabase uses the reviewed migrations under `supabase/migrations/`; the production request-serving process never runs schema DDL.

The current pass has a passing production build, 106 Vitest tests and 13 browser tests. Hosted synthetic speech passed the real OpenAI connection, server-confirmed transcript storage, microphone pause and session closure. Synthetic test accounts were removed. Detailed evidence and remaining native/payment validation are recorded in [status.md](docs/status.md).

## Deployment configuration

The root `vercel.json` builds the Vite frontend into `dist/web` and routes `/api/*` to the Node function in `api/index.ts`. This function initializes Hono and a bounded PostgreSQL pool, checks access to the auth table, and uses Vercel's pool lifecycle integration. The assigned public origin is `https://sideleaf.vercel.app`. The Vercel Sideleaf team/project is linked to [ThinkHale/Sideleaf](https://github.com/ThinkHale/Sideleaf). The Dockerfile remains an alternative runtime, not a dependency of this deployment.

Supabase project `qhgzilyanroqomafhybg` has the 15-table private `sideleaf` schema and five migrations applied. That schema is excluded from the Data API. The API uses the restricted `sideleaf_runtime` role through the Supavisor transaction pooler; Better Auth remains the identity system. Verified TLS succeeds using the official bundled Supabase root certificate. Supabase Cron and Vault supervise expired transcription calls without putting credentials in scheduled SQL.

Database credentials and the stable `BETTER_AUTH_SECRET` are set only in the Vercel project's server environment. The selected beta enables email/password login with `ENABLE_PASSWORD_AUTH=true`; email verification and password-reset delivery are not implemented. Google login remains optional and unverified. Preview and production currently share the beta database, so preview changes can affect the same accounts and notes. Separate environments before wider production use.

Local `.env` overrides are optional and no secrets belong in `.env.example`. Keep real development credentials outside this OneDrive checkout or inject them into the API process environment. Never place database, OpenAI, or authentication secrets in `VITE_*` variables or native app files. Mac native development needs the shared API contract and user sessions, not Supabase Auth or a Supabase SDK.

## Current boundary

Live web transcription and assisted usage accounting are implemented. Real text-AI coaching, grounded summaries, full native synchronization, and completed-meeting workflows remain unfinished. Stripe purchase activation and native store billing need their provider setup and end-to-end validation. The early native project now compiles for an iPad simulator but has not yet been exercised in a simulator or on a physical iPad.

See [status and continuation checklist](docs/status.md), [architecture](docs/architecture.md), [privacy evidence](docs/privacy.md), [billing design](docs/billing.md), [acceptance tests](docs/acceptance-tests.md), [design comparison](docs/design-review.md), and [native setup](native/README.md).
