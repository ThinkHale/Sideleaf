# Architecture

## Current slice

React 19, TypeScript and Vite render the notebook UI. The hosted beta runs the frontend and Node/Hono API in one Vercel project at [sideleaf.vercel.app](https://sideleaf.vercel.app). `vercel.json` routes `/api/*` to `api/index.ts`, which exports a Web-standard fetch handler. The local development entry remains `server/index.ts`.

Better Auth owns password hashing, account identity and session cookies through its maintained Drizzle adapter. Supabase hosts the database; Supabase Auth is not in the request path. Password authentication works locally and is explicitly enabled for the hosted beta with `ENABLE_PASSWORD_AUTH=true`. Hosted Better Auth rate limits use the database so separate Vercel instances share counters. Google login remains optional and has not been exercised. Email verification delivery and password recovery are not implemented.

`server/database.ts` uses PGlite for local development and node-postgres for the hosted database. Local startup applies the local migration. Production disables startup DDL and uses separately reviewed Supabase migrations. The Vercel function reuses a bounded pool per warm instance, verifies auth-table access during initialization, and attaches Vercel's pool lifecycle integration. Invalid initialization returns a sanitized 503 and can retry later. Restricted TLS and live production sign-in, persistence, retry/conflict handling, ownership, export and deletion checks have passed. Hosted desktop/phone browser checks also verified page editing and persistence after reload without console warnings or errors. Synthetic test accounts were cleaned up and old API-test sessions were rejected.

A single-process filesystem lock protects local PGlite ownership. Stale process markers are removed only while holding that lock. Development data lives outside synced source directories because OneDrive's read-only directory attributes interfere with the WASM filesystem. The original local data-directory and IndexedDB names remain unchanged, and local accounts or notes are not automatically copied into the hosted beta.

## Supabase and shared secrets

The owner selected Supabase Postgres for the hosted notebook beta on 2026-09-07. Project `qhgzilyanroqomafhybg` contains the migrated 15-table `sideleaf` schema. The schema is excluded from the Data API, with schema/table access revoked from `PUBLIC`, `anon` and `authenticated`. Structured notebook data, versions and semantic anchors use the existing transactional revision protocol and IndexedDB recovery queue. Capture, usage, watchdog and billing records have separate backend-only tables.

The API connects through Supavisor transaction pooling on port 6543 as `sideleaf_runtime`. This non-owner role has table CRUD permissions and schema usage, cannot perform schema DDL, and cannot bypass RLS. Its persistent role-level `search_path` resolves unqualified Drizzle table names to `sideleaf`. Runtime SQL uses unnamed queries, avoiding named prepared statements in transaction mode. Verified TLS passed using the official bundled Supabase root certificate. The actual runtime role, schema and auth-table resolution were confirmed; schema creation and anonymous schema usage were denied. [Supabase connection modes](https://supabase.com/docs/guides/database/connecting-to-postgres).

RLS permits the backend role to access notebook rows; Hono and Better Auth enforce per-user ownership. This is a backend-only authorization model, not an `auth.uid()` policy for direct Supabase clients. Keep the schema outside Data API exposure. Any later client access requires its own reviewed grants and ownership policies. [API exposure, grants and RLS](https://supabase.com/docs/guides/api/securing-your-api).

Five reviewed hosted migrations are applied and aligned. They establish the private notebook/auth schema, remove public execution grants on the provider's RLS helper while preserving its event trigger, add seven capture/billing tables, and install the watchdog extensions with restricted access. The newly installed pg_net extension lives under `extensions`. The remaining advisor warning concerns unused Supabase Auth leaked-password protection. Sideleaf uses Better Auth, with email verification and password-reset delivery still unfinished.

`DATABASE_URL`, the stable `BETTER_AUTH_SECRET` and `OPENAI_API_KEY` live only in the Vercel project's server environment. Stripe server and webhook secrets belong there when configured. The watchdog's maintenance bearer secret is shared between Vercel and Supabase Vault. Administrative migration credentials stay outside the deployed request-serving process, and future privileged Storage credentials remain server-only. Neither browser `VITE_*` variables nor native source contain shared provider secrets. The native app will store its own user's session in Keychain and call the same public HTTPS API. [Hosting and secret locations](hosting-secrets.md).

Preview and production currently use the same beta database. This permits preview code to affect the same accounts and notes; isolate preview data and credentials before wider production use. Native development needs the shared API, not Supabase Auth or a Supabase SDK.

Private Supabase Storage remains planned for editable PencilKit artifacts, portable previews and permitted attachments, with owned references in Postgres. Artifact routes, authorization and deletion have not been implemented. [Private bucket access](https://supabase.com/docs/guides/storage/buckets/fundamentals) and [CDN behavior](https://supabase.com/docs/guides/storage/cdn/smart-cdn) require explicit tests. No audio belongs in these buckets or tables.

OpenAI Realtime is connected through the implemented WebRTC adapter and server observer using `gpt-4o-mini-transcribe`. A hosted Chromium test with synthetic microphone input passed actual provider transcription, Supabase text persistence and Pause cleanup on September 7, 2026. Physical microphone and native capture validation remain separate work. The owner permits disclosed provider retention while Sideleaf saves no audio recordings. See [privacy direction](privacy.md#product-direction) and [draft disclosure](privacy-notice-draft.md). The earlier Firebase and separate Render options are historical evaluations, not active services in the selected deployment.

## Data ownership and contracts

`shared/domain.ts` is the executable Zod contract. UUIDs are stable across saves. A notebook belongs to one authenticated user; a page has both an owner and a notebook. Every API read, write, history lookup, export and deletion checks ownership. A page cannot be moved into another account's notebook. Resolved annotations must match the source block, revision and exact quote. Page-write bodies reject unknown fields and forged transcript/AI provenance. Only server-observed provider events become saved transcript records.

The implemented relational model has auth users, sessions, accounts, verifications and rate limits, plus notebooks, pages and page revisions. Seven additional tables hold capture sessions, meeting transcripts, monthly usage, watchdog freshness, billing customers, subscriptions and processed billing events. Page documents contain independent block, ink, annotation and preparation collections. Preparation is labeled as background. A note exclusion flag affects export eligibility, not storage. No model output mutates manual text or ink.

`shared/capture.ts` defines the live client/server contract. The active provider implementation is `server/openai-capture.ts`, orchestrated by `server/capture.ts`. Saved transcript segments are deduplicated by session and provider item, separate from page revisions. Transcript revision/redaction, coaching jobs, structured summaries and actions remain future work. Source-grounded item contracts in `shared/providers.ts` do not establish that coaching or summarization is implemented.

`server/billing.ts` implements Stripe hosted Checkout, the customer portal and raw-body signature-verified webhooks. Server reconciliation retrieves authoritative provider state, isolates test/live records and grants entitlements from owned, verified subscriptions. Refund/dispute and account-deletion safeguards are covered by local tests. Stripe credentials and a real sandbox purchase remain pending. Apple and Google provider names are future entitlement channels, not implemented receipt verification. See [billing](billing.md).

## Save and recovery protocol

`PUT /api/pages/:id` accepts `{title, notebookId, document, baseVersion, mutationId}`. A new page uses base version zero. A PostgreSQL transaction locks the page and compares its version, updates it, and inserts an immutable revision. A unique `(page_id, mutation_id)` constraint makes retries idempotent. Stale edits receive 409 and the owned current version. A different owner receives 404.

The browser immediately stores a draft in IndexedDB, then saves after 700 ms of quiet. An in-flight acknowledgment updates the base version of newer pending edits without replacing their content. Network failures leave the local draft intact. Reconnect retries use the same mutation ID. Conflicts require keeping both versions or downloading the local draft before choosing the server copy. Displaced drafts from another tab are retained in a device recovery store. Signing out clears the account's local cache, including recovery copies, and is blocked while unsynced current drafts remain.

The PWA precaches the actual hashed entry assets and caches only static same-origin resources. The build hashes its HTML entry into the service-worker version. API responses, authentication and audio are never cached by the service worker. Previously authenticated users can reopen cached manual notes offline; all remote access is still authorized by the server.

This is revision-based synchronization, not simultaneous collaborative editing. The current library downloads owned documents and searches them in the client. Large-library pagination, server-side full-text indexing and storage quotas require a later scaling pass. Snapshot history stores complete page documents. Ink is bounded per page to protect request size; there is no total notebook/page limit tied to a paid plan.

## Marking and ink

Browser text is rendered into stable block/word spans. Selection offsets are UTF-16 code units, matching DOM Range and Foundation NSString. Mark mode measures current word rectangles and tests their centers against the lasso polygon. Each contiguous enclosed word run receives its own anchor. Measurements happen after the gesture, so browser scrolling, text wrapping, viewport changes and normal browser zoom are reflected in hit testing.

Anchors retain block ID, source revision, offsets, original quote, prefix and suffix. Corrections are remapped only when a unique exact quote and context match exists. Conservative failures show an unresolved state. Importance is not factual confirmation. Touch taps open phrase actions but do not create a mark until an action is selected. Write strokes never become semantic annotations.

Web ink uses editable point arrays on an 800-unit-wide paper coordinate system. Write adds strokes, Erase removes touched strokes, and Select can move individual strokes or use arrow keys/Delete after focusing a stroke. Ink movement is undoable. Handwriting recognition is absent; handwritten text is not searched or included in AI context. Reflow preserves semantic anchors, while ordinary ink remains a drawing in paper coordinates and is not automatically attached to text.

## Native boundary

`native/` contains SwiftUI navigation, SwiftData local pages, a narrow UIKit paper view, PencilKit serialization and a portable PNG representation. The explicit Mark overlay hit-tests TextKit word rectangles and retains semantic anchors separately from `PKDrawing`. The readiness probe checks iPad hardware support, a supported equivalent locale and installed speech assets. Asset installation is a deliberate action.

The native implementation currently has its own local page model. It has not yet been connected to the shared authenticated API. The native project's initial block ID maps to its single page text buffer; migration to multiple shared blocks and cross-client ink interchange is still required. Native undo is currently PencilKit ink undo; native phrase menus and annotation undo remain unfinished. No native capture service is attached to the UI.

Mac continuation starts from the same GitHub repository. Generate `native/Sideleaf.xcodeproj` with XcodeGen, compile with Xcode 26 or later, run the native anchor tests, and complete signing and app-icon packaging as recorded in [native/README.md](../native/README.md). Implement native session handling and revision-based synchronization against the shared Vercel API before claiming cross-device operation. No production provider credentials belong in Xcode or the distributed app.

## Live capture and future AI

The browser sends microphone audio directly to OpenAI over WebRTC after the authenticated API checks ownership, consent, allowance and supervision. A server WebSocket observes finalized provider text, persists it in Supabase and streams confirmed segments to the browser over SSE. Client interim text cannot establish saved transcript provenance. Pause and Stop release microphone tracks and settle the server session; manual notes remain independent.

The account lock serializes session starts and deletion. One assisted session per account, connection-attempt limits, monthly UTC usage and accumulated per-meeting allowance are enforced by the server. Metering starts when the provider SDP answer can enable audio and includes brief setup and silence. Paused time is excluded. A 70-second initial lease contains the provider's 45-second setup deadline; after the SDP answer, a 20-second lease allows observer attachment. The observer renews active leases at most 25 seconds ahead. An authenticated Supabase watchdog runs every 30 seconds, and stale or backlogged supervision blocks new starts.

The Vercel function requests 300 seconds. Each observer rolls its connection at about 225 seconds, with a disclosed reconnect gap because audio is not buffered for replay. The implementation has bounded text queues and retryable provider cleanup. No MediaRecorder, accumulating audio Blob, audio file or offline audio queue is used. Hosted real-provider tests passed saved text, Pause/Resume, one complete rollover with new saved text and network-loss cleanup. Physical microphone, native capture and repeated long-meeting reliability remain unvalidated. Exact setup and limits are in [live capture](live-capture.md).

Future cloud text analysis should operate on compact finalized deltas and annotations with debouncing, cancellation and stale-result rejection. A background text-job worker should be added when that processing requires it.

Treat all preparation, reference text and transcript content as untrusted data. No meeting content may execute tools, contact people, change privileges or access secrets. Validate structured outputs and all source references on the server before persistence. AI notes and summaries need independent versions so regeneration cannot overwrite user edits.

## Documentation checked

- [Better Auth Drizzle adapter](https://better-auth.com/docs/adapters/drizzle)
- [PGlite and Drizzle integration](https://pglite.dev/docs/orm-support)
- [Hono Better Auth integration](https://hono.dev/examples/better-auth)
- [Apple SpeechAnalyzer overview and sample](https://developer.apple.com/videos/play/wwdc2025/277/)
