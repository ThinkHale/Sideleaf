# Implementation status

## Plan and assumptions

This repository was empty on 2026-09-06. The first verifiable slice is a real authenticated notebook, not a transcription simulation. Development uses embedded PostgreSQL (PGlite). The owner selected and authorized the Vercel plus Supabase notebook beta on 2026-09-07, including deployment through the signed-in CLIs. The current cloud setup and remaining verification are recorded below.

- [x] Establish React/Vite, TypeScript API, shared schemas, migrations, Better Auth.
- [x] Persist notebooks, editable pages, version history, preparation, ink and semantic annotations.
- [x] Implement offline manual editing, autosave, conflict recovery, search and exports.
- [x] Inspect desktop/phone/iPad browser layouts and exercise real API workflows.
- [x] Establish native SwiftUI/PencilKit source and an on-device readiness probe.
- [x] Document privacy, billing, API contracts, evidence and exact next slices.

The product name is Sideleaf, with a configurable runtime display name. The supplied logo package is integrated into navigation, authentication, loading states, web app icons, and native source assets. Native app icon packaging and Xcode validation remain pending. Initial accounts and notes contain no real client data. Synthetic example content is opt-in and explicitly labeled. Cloud capture must remain unavailable until audio-retention prerequisites are verified for the deployment account. No audio recording fallback is permitted.

## Cloud beta setup

- [x] Confirm the signed-in Vercel and Supabase CLIs and select the owner's Sideleaf projects.
- [x] Create/link the Sideleaf Vercel team project to `ThinkHale/Sideleaf`, with assigned domain `sideleaf.vercel.app`.
- [x] Configure one Vercel project for both the Vite frontend and Hono Node API; the earlier separate Render API is no longer the deployment target.
- [x] Migrate the eight-table private `sideleaf` schema in Supabase project `qhgzilyanroqomafhybg`.
- [x] Establish the restricted `sideleaf_runtime` database role with table CRUD, RLS and a role-level schema search path. Keep administrative migrations outside request startup.
- [x] Add explicit hosted email/password beta opt-in and Better Auth database-backed authentication rate limits.
- [x] Keep the shared database and authentication secrets in Vercel's server environment. No shared provider keys belong in browser or native code.
- [x] Verify TLS through the actual restricted Supavisor transaction-pooler connection using the official bundled root certificate. Confirm `current_user=sideleaf_runtime`, `current_schema=sideleaf` and `auth_user` resolution, with schema creation and anonymous schema usage denied.
- [x] Apply both hosted migrations and align migration history, including revoking public execution of `public.rls_auto_enable` while preserving its event trigger.
- [x] Verify the corrected Vercel preview: `/api/health` returns 200; `/api/config` reports `development:false`, `passwordAuth:true` and `capture.ready:false`.
- [x] Complete the production deployment at `https://sideleaf.vercel.app`, deployment `dpl_BrxFMhpdHpDezQp6mVtU6GYNYcAa`.
- [x] Verify live production sign-up/sign-in, persistence, retry/conflict handling, account isolation, origin protection, exports, history and deletion. Delete the synthetic test accounts and verify old sessions are rejected.
- [x] Verify hosted desktop/phone UI sign-up, page creation, editing, saved state and reload persistence without console warnings or errors. Clean up synthetic UI accounts.
- [x] Complete the built-PWA test including runner teardown. All 62 automated tests passed.
- [x] Fix note text clipping after width changes and verify full text remains visible through desktop, phone and iPad resizing.
- [x] Add explicit `.vercelignore` exclusions and audit the replacement deployment to confirm no local database or secret files were uploaded. Superseded private uploads were removed.

Better Auth remains responsible for identity and sessions; Supabase provides PostgreSQL. The private schema is excluded from the Data API. Its RLS policy permits the backend role, while Hono enforces individual ownership. The remaining Supabase advisor warning concerns leaked-password protection in unused Supabase Auth. Private Storage, OpenAI processing and native synchronization remain future work. Preview and production share the beta database, so preview code can affect the same accounts and notes.

## Automated and database verification

- TypeScript/Vite production build passed.
- 56 Vitest tests passed in the cloud deployment pass, covering the notebook contracts and API behavior plus cloud configuration, verified transport requirements, explicit migrations, Vercel initialization and authentication configuration.
- 5 local Chromium end-to-end tests passed again. These cover the manual notebook, preparation, geometric marks, follow-up edits, source correction, export, offline reconnect and two-tab recovery.
- The built-PWA test passed for a complete offline reload, recovered text synchronization and private-text exclusion from PDF, including clean runner teardown.
- The actual restricted Supabase transaction-pooler connection passed certificate verification, resolved the intended role/schema/table, and denied schema creation and anonymous schema usage. Both migrations are aligned.
- Production and preview passed health and production-configuration checks, with email beta login enabled and capture disabled.
- Live production passed secure-cookie sign-up/sign-in for two synthetic accounts, notebook creation, Supabase page persistence after a fresh sign-in, idempotent retry, stale-edit 409, cross-account read/history/export/delete 404, cross-origin mutation 403, export/history/deletion and the intended capture 503. Both accounts were deleted and old sessions returned 401.
- Hosted Chromium UI checks at 1440x1000 and 390x844 passed sign-up, blank-page creation, title/text editing, saved state and retained content after reload, with no console warnings or errors. Synthetic UI accounts were cleaned up. Screenshots are under `%TEMP%/sideleaf-hosted-qa/`: `signup-desktop.png`, `notebook-desktop.png` and `notebook-phone.png`.
- All 62 automated tests passed: 56 Vitest, five local Chromium end-to-end tests and one built-PWA test. The hosted API and browser checks above are additional checks. Hosted offline behavior was not retested.

## Earlier visual verification

- Desktop 1536x1024, phone 390x844, iPad portrait 820x1180 and landscape 1180x820 browser dimensions exercised. These are browser tests, not native devices.
- In-app browser inspected with a synthetic local account. Image concept and rendered screenshot compared through image inspection. Exported A4 PDF rendered and visually inspected.
- Final fresh in-app navigation produced no new warning/error console entries. An earlier development hot-reload error cleared on reload and did not recur in that interaction.
- The earlier production dependency audit reported zero vulnerabilities. These checks do not establish a complete security audit.
- Concept fidelity, repaired mobile title wrapping, and deliberate functional differences are recorded in [design-review.md](design-review.md).

## Integration and hardware boundary

The current runnable deliverable is the ordinary-note and meeting-preparation slice. It does not provide a real assisted meeting yet. Live audio, transcripts, text-AI coaching, summaries, completed meetings, billing, usage enforcement and native synchronization remain code work, not merely missing credentials.

Native source is uncompiled. XcodeBuildMCP reported `spawn xcrun ENOENT`. No Mac/Xcode, simulator or physical Pencil/iPad run was possible. The readiness probe follows current Apple APIs but actual device and asset results have not been observed. Google OAuth, Docker/CI, provider retention guarantees and payment verification were not exercised. The Supabase schema, restricted runtime TLS, live notebook API workflows and hosted desktop/phone UI are verified.

## Exact continuation checklist

### 1. Finish hosted notebook verification, then live capture

- [x] Verify hosted email/password sign-up/sign-in and the notebook API workflows listed above.
- [x] Complete hosted desktop/phone UI verification.
- [ ] Retest offline behavior on the hosted origin and exercise rate-limit behavior across separate function instances.
- [ ] Add email verification delivery and password recovery before treating the beta account flow as a complete production account lifecycle.
- [ ] Isolate preview and production databases and credentials; both currently use the shared beta database. Verify callback origins and rollback behavior. Preserve existing local data; no automatic local-to-cloud migration is implemented.

- [ ] Add meeting/session/lease/usage tables and indexes, plus per-user stream and job authorization.
- [ ] Finish the OpenAI endpoint/account review and implement one streaming adapter with an enforced readiness gate. The owner's 2026-09-07 clarification permits disclosed provider retention while Sideleaf saves no audio. ZDR is optional under this direction. Implement the reviewed Privacy Policy/start-flow disclosure and verify application buffering and provider settings. Deepgram remains earlier research, not an integration.
- [ ] Implement bounded PCM AudioWorklet frames and server streaming relay with backpressure. No MediaRecorder, saved Blob, disk buffer or offline audio queue.
- [ ] Add explicit capture readiness/consent/permission states, pause/resume/end, track cleanup, silence handling, app suspension and timestamped interruption gaps.
- [ ] Persist finalized transcript segments incrementally using stable event IDs and revisions, show interim text separately, deduplicate reconnects and make finalization idempotent.
- [ ] Test real microphone and provider start/pause/resume/end/reopen before claiming live transcription.

### 2. Coaching and completed output

- [ ] Add a real swappable text-AI adapter, explicit configuration errors, compact context assembly and background jobs.
- [ ] Validate structured results and source quotes; reject stale jobs and deduplicate requests; treat all meeting content as untrusted data.
- [ ] Connect objectives, unanswered questions, concerns, decisions and annotations to debounced coaching with two visible suggestions and no repeat spam.
- [ ] Add versioned editable summaries, source navigation, action-owner/deadline uncertainty, selective exclusions and optional unsent follow-up email drafts.
- [ ] Extend marks to transcript revisions; test wrapped, zoomed, scrolled and corrected transcript text without moving active writing/selection.

### 3. Billing and production privacy

- [x] Select Supabase Postgres and migrate the private notebook schema while retaining Better Auth, Hono and conflict handling.
- [ ] Implement private Supabase Storage routes for permitted artifacts, with ownership checks, retention and deletion verification. No audio storage is permitted.

- [ ] Implement server-authoritative monthly periods, reset timestamps, active-time intervals, one-account session leases, reconnect-safe metering and free-limit finalization.
- [ ] Implement Stripe Checkout/portal and signed, idempotent webhook reconciliation including cancellation, failed payment and refund handling.
- [ ] Implement StoreKit verified transactions, restore purchases, backend notification validation and duplicate-subscription protection after reviewing target storefront rules.
- [ ] Add selective redaction across current data and revision history. Current exclusion and block deletion do not erase historical text.
- [ ] Validate CI; define backup retention/deletion policy and storage encryption. Hosted ownership, PostgreSQL TLS and role/schema access checks have passed. Docker is an optional alternate runtime, not a prerequisite for the selected Vercel deployment.
- [ ] Load-test large libraries and add pagination/search indexes, history compaction policy and operational metadata without content logging.

### 4. Native completion

- [ ] Continue from the same GitHub repository on Mac. Generate the Xcode project with XcodeGen and compile with Xcode 26 or later; run native anchor tests and resolve SDK/concurrency diagnostics.
- [ ] Complete signing and native app-icon packaging; keep all shared provider secrets in Vercel, with only user session credentials stored in the native Keychain.
- [ ] Complete native selection/actions/undo and preparation; connect the shared multi-block and sync contracts through authenticated APIs. No Supabase Auth or Supabase SDK setup is required in the native app.
- [ ] Define native PKDrawing/portable artifact upload endpoints and coordinate metadata; preserve native editability across web viewing.
- [ ] Add a bounded SpeechAnalyzer capture pipeline with preflight device/language/assets checks and no remote fallback.
- [ ] Connect bounded native entitlements and cross-channel purchases.
- [ ] Validate real Apple Pencil, palm rejection, orientation/reflow, background interruption, offline notes and cross-client conflicts on physical hardware.

## Known limitations in this slice

No handwritten-text recognition/search; no collaborative CRDT; client-side library search loads all pages; snapshot history is not compacted. Native selection and annotation undo are incomplete. Web undo history is in-memory per open page and does not include every margin edit. Native preview PNG/PKDrawing artifacts are not yet synchronized to web. PDF reflows typed text and puts handwriting on a separate section/page.

If the API is restarting during initial library loading, reload the page once the API is ready. The current Retry sync control flushes pending edits but does not retry the initial library read when no edits are pending.

Hosted password signup is disabled by default and enabled for the selected beta only with `ENABLE_PASSWORD_AUTH=true`. Email verification delivery and password recovery are unfinished. Cloud capture cannot be activated with an environment flag in this slice. The no-audio behavior is verified by absence of an input path, not by a live-provider retention test.

Current deployment and credential locations are documented in [hosting-secrets.md](hosting-secrets.md). The notebook beta deployment and the live API/browser checks above are complete at [sideleaf.vercel.app](https://sideleaf.vercel.app). OpenAI, private artifact storage and native completion remain the separate implementation work listed above.
