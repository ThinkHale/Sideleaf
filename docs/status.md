# Implementation status

## Plan and assumptions

This repository was empty on 2026-09-06. The first verifiable slice is a real authenticated notebook, not a transcription simulation. Development uses embedded PostgreSQL (PGlite); deployment uses a PostgreSQL service. No paid services or public deployment are authorized.

- [x] Establish React/Vite, TypeScript API, shared schemas, migrations, Better Auth.
- [x] Persist notebooks, editable pages, version history, preparation, ink and semantic annotations.
- [x] Implement offline manual editing, autosave, conflict recovery, search and exports.
- [x] Inspect desktop/phone/iPad browser layouts and exercise real API workflows.
- [x] Establish native SwiftUI/PencilKit source and an on-device readiness probe.
- [x] Document privacy, billing, API contracts, evidence and exact next slices.

The product name is Sideleaf, with a configurable runtime display name. The supplied logo package is integrated into navigation, authentication, loading states, web app icons, and native source assets. Native app icon packaging and Xcode validation remain pending. Initial accounts and notes contain no real client data. Synthetic example content is opt-in and explicitly labeled. Cloud capture must remain unavailable until audio-retention prerequisites are verified for the deployment account. No audio recording fallback is permitted.

## Verified behavior

- TypeScript/Vite production build passed.
- 23 Vitest tests passed: anchors, geometry, schema/provenance, export filtering, real Better Auth/API access control, save idempotency, concurrent conflicts, deletion, and filesystem database reopening.
- 5 Chromium end-to-end tests passed after adding ink selection and keyboard movement/undo. These cover the manual notebook, preparation, geometric marks, follow-up edits, source correction, export, offline reconnect and two-tab recovery.
- Built-PWA test passed for a complete offline reload, recovered text synchronization and private-text exclusion from PDF.
- Desktop 1536x1024, phone 390x844, iPad portrait 820x1180 and landscape 1180x820 browser dimensions exercised. These are browser tests, not native devices.
- In-app browser inspected with a synthetic local account. Image concept and rendered screenshot compared through image inspection. Exported A4 PDF rendered and visually inspected.
- Final fresh in-app navigation produced no new warning/error console entries. An earlier development hot-reload error cleared on reload and did not recur in that interaction.
- All 29 automated tests passed. Production dependency audit reported zero vulnerabilities. These checks do not establish a complete security audit.
- Concept fidelity, repaired mobile title wrapping, and deliberate functional differences are recorded in [design-review.md](design-review.md).

## Integration and hardware boundary

The current runnable deliverable is the ordinary-note and meeting-preparation slice. It does not provide a real assisted meeting yet. Live audio, transcripts, text-AI coaching, summaries, completed meetings, billing, usage enforcement and native synchronization remain code work, not merely missing credentials.

Native source is uncompiled. XcodeBuildMCP reported `spawn xcrun ENOENT`. No Mac/Xcode, simulator or physical Pencil/iPad run was possible. The readiness probe follows current Apple APIs but actual device and asset results have not been observed. Google OAuth, external PostgreSQL, Docker/CI, provider retention guarantees and payment verification were not exercised.

## Exact continuation checklist

### 1. Live capture and saved meetings

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

- [ ] Complete storage provider selection. As of 2026-09-07, Supabase Postgres plus private Storage is recommended over the earlier Firebase option for this codebase. Keep Better Auth, Hono and conflict handling initially; verify Data API exposure, database roles, artifact authorization and migration before remote data transfer. No Supabase or Firebase project, billing, or service has been provisioned.

- [ ] Implement server-authoritative monthly periods, reset timestamps, active-time intervals, one-account session leases, reconnect-safe metering and free-limit finalization.
- [ ] Implement Stripe Checkout/portal and signed, idempotent webhook reconciliation including cancellation, failed payment and refund handling.
- [ ] Implement StoreKit verified transactions, restore purchases, backend notification validation and duplicate-subscription protection after reviewing target storefront rules.
- [ ] Add selective redaction across current data and revision history. Current exclusion and block deletion do not erase historical text.
- [ ] Verify PostgreSQL TLS and ownership tests against an external service; validate Docker and CI; define backup retention/deletion policy and storage encryption.
- [ ] Load-test large libraries and add pagination/search indexes, history compaction policy and operational metadata without content logging.

### 4. Native completion

- [ ] Generate and compile the Xcode project on Mac; run native anchor tests and resolve SDK/concurrency diagnostics.
- [ ] Complete native selection/actions/undo and preparation; connect the shared multi-block and sync contracts through authenticated APIs.
- [ ] Define native PKDrawing/portable artifact upload endpoints and coordinate metadata; preserve native editability across web viewing.
- [ ] Add a bounded SpeechAnalyzer capture pipeline with preflight device/language/assets checks and no remote fallback.
- [ ] Connect bounded native entitlements and cross-channel purchases.
- [ ] Validate real Apple Pencil, palm rejection, orientation/reflow, background interruption, offline notes and cross-client conflicts on physical hardware.

## Known limitations in this slice

No handwritten-text recognition/search; no collaborative CRDT; client-side library search loads all pages; snapshot history is not compacted. Native selection and annotation undo are incomplete. Web undo history is in-memory per open page and does not include every margin edit. Native preview PNG/PKDrawing artifacts are not yet synchronized to web. PDF reflows typed text and puts handwriting on a separate section/page.

If the API is restarting during initial library loading, reload the page once the API is ready. The current Retry sync control flushes pending edits but does not retry the initial library read when no edits are pending.

Local sign-up is deliberately labeled development-only. Production password signup is disabled and an identity provider must be configured. Cloud capture cannot be activated with an environment flag in this slice. The no-audio behavior is verified by absence of an input path, not by a live-provider retention test.

No services were purchased or provisioned; no public deployment, remote push or production resource change occurred.
