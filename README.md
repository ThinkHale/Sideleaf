# Sideleaf

A working first vertical slice of an AI-assisted meeting notebook. It provides authenticated ordinary note-taking, preparation, editable ink, semantic text marking, versioned saves, offline recovery, and exports. It is not yet a working live-transcription or subscription product.

Product repository: [ThinkHale/Sideleaf](https://github.com/ThinkHale/Sideleaf). Sideleaf is the product name; `PRODUCT_NAME` can override the runtime display name. The supplied Sideleaf logo package is integrated into the web app and native source. Asset mappings and usage are recorded in [branding.md](docs/branding.md).

The proposed web/native deployment and credential locations are described in [hosting-secrets.md](docs/hosting-secrets.md).

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

- Better Auth sign-up/sign-in locally, isolated accounts, optional Google authentication configuration, and server-enforced ownership.
- Notebooks, pages, typed notes, heading blocks, basic pressure-bearing ink data, drawing, erasing, moving individual ink strokes, undo/redo, search, and preparation templates.
- Explicit Type, Write, Mark, Select, and Erase tools. Write circles are ordinary ink. Mark circles select enclosed words and create independently stored semantic marks. Mouse, touch pointer events, keyboard text selection, and keyboard ink movement are supported in source; see the tested platforms below.
- Important marks, editable follow-up questions and action drafts, addressed/dismissed/later states, and at most two open questions in the margin. Questions use a clearly user-owned deterministic starter, not AI inference.
- IndexedDB drafts, debounced server saves, compare-and-swap versions, idempotency keys, retained revision history, and a conflict flow that keeps both pages. Cross-tab draft displacement is retained in device recovery.
- Markdown, plain text, account JSON, and print/PDF. Excluded notes and their marks are omitted from ordinary exports, while full data export retains them. PDF renders ink separately from reflowed text.
- Responsive library, notebook, preparation and settings; focus mode; visible microphone-off status; keyboard labels and reduced-motion handling.
- Native SwiftUI/SwiftData/PencilKit source, native anchor tests, and a SpeechTranscriber device/language/asset readiness probe. This native source has not been compiled or run here.

## Verification commands

```powershell
npm run check
npm run test:e2e
npm run test:pwa
```

Install the test browser once with `npx playwright install chromium`. `test:e2e` can reuse the running development server. `test:pwa` starts a separate built app on port 4173 with its own temporary database. Test accounts use synthetic `example.test` addresses. Test images/PDFs are written under the operating system temporary directory in `meeting-notebook-qa`.

`npm run format` formats the web, API, contracts, tests and documentation. SQL migration `server/migrations/001_notebook.sql` is idempotent and is applied at startup. `npm run db:migrate` applies it explicitly while the embedded API is stopped.

## Deployment configuration

Copy `.env.example` to `.env` only if you need to override local defaults. No secrets are included. The Dockerfile and CI workflow are provided but Docker/public deployment were not run. For a production deployment supply an HTTPS `APP_ORIGIN`, a random `BETTER_AUTH_SECRET` of at least 32 characters, an appropriately secured PostgreSQL `DATABASE_URL`, and configured authentication. Local password sign-up is disabled in production. Google OAuth redirect configuration must match the deployment origin and `/api/auth/callback/google`.

Terminate TLS at the ingress, use certificate-verified PostgreSQL transport, restrict database access to the API, and configure encrypted storage and backup retention before real customer use. Never enable payload capture in proxies, tracing, analytics or error reporting. No resources were provisioned, no purchases were made, and nothing was pushed or publicly deployed.

## Current boundary

Web audio capture, streaming transcripts, real text-AI coaching, grounded summaries, assisted usage accounting, billing and purchases, full native synchronization, and completed-meeting workflows remain unfinished. The disabled capture response is intentional and cannot be unlocked with an API key. The native project is an early feasibility implementation, not a verified shipped iPad client.

See [status and continuation checklist](docs/status.md), [architecture](docs/architecture.md), [privacy evidence](docs/privacy.md), [billing design](docs/billing.md), [acceptance tests](docs/acceptance-tests.md), [design comparison](docs/design-review.md), and [native setup](native/README.md).
