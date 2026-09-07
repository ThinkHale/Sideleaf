# Architecture

## Current slice

React 19, TypeScript and Vite render the actual notebook UI. Hono serves same-origin authenticated APIs. Better Auth owns password hashing and session cookies. Its maintained Drizzle adapter is used rather than hand-written authentication. Local password authentication is development-only. Optional Google auth is configured in source but has not been exercised with an account.

`server/database.ts` uses PGlite for zero-service local development and node-postgres for a configured PostgreSQL service. Both execute the same SQL migration and Drizzle schema. The tested database is PGlite, not an external PostgreSQL server. A single-process filesystem lock protects local database ownership. Stale PGlite process markers are removed only while holding that lock. Development data lives outside synced source directories because OneDrive's read-only directory attributes interfere with the WASM filesystem.

## Recommended Supabase and OpenAI direction

Updated 2026-09-07. The owner is comparing Supabase with Firebase. For Sideleaf's existing implementation, Supabase is the recommended storage backend: it offers direct PostgreSQL and [Drizzle integration](https://supabase.com/docs/guides/database/drizzle), allowing the current schema, Hono API, Better Auth, and transactional revision protocol to remain. This is a recommendation based on the current code, not a completed provider selection or migration.

- Use **Supabase Postgres** for structured notebook data, versions, semantic anchors, and eventual finalized transcripts, usage and subscriptions. Keep the current IndexedDB queue and explicit conflicts. Database hosting alone does not implement offline synchronization.
- Use **private Supabase Storage** for editable PencilKit artifacts and portable previews, with owned references in Postgres. Hono must authorize artifact access while Better Auth remains in use. [Private bucket access](https://supabase.com/docs/guides/storage/buckets/fundamentals) and [CDN behavior](https://supabase.com/docs/guides/storage/cdn/smart-cdn) need explicit tests; do not promise immediate revocation based solely on signed-URL expiry. No audio belongs in these buckets or tables.
- Keep **Better Auth and the backend API initially**. A database-hosting change does not migrate sessions into Supabase Auth. Existing Better Auth identities do not automatically populate Supabase's `auth.uid()`.
- For the initial server-only database path, disable the **Data API**, keep database and privileged Storage credentials on the server, and use least-privilege roles. Review [API exposure, grants and RLS](https://supabase.com/docs/guides/api/securing-your-api) before any client access is introduced. Exposed tables need tested ownership policies; do not assume that changing providers makes our SQL schema secure automatically.
- Validate the actual deployment's [SSL and connection method](https://supabase.com/docs/guides/database/connecting-to-postgres), apply reviewed migrations, and rerun cross-account authorization, conflicts, exports, deletion and filesystem/artifact round trips. Preserve local data until migration is verified.

OpenAI remains the preferred transcription provider. The owner now permits disclosed provider retention while Sideleaf saves no audio recordings. See [updated privacy direction](privacy.md#updated-product-direction) and [draft disclosure](privacy-notice-draft.md). No Supabase project was created, credentials requested, data uploaded, or live transcription enabled by this documentation update.

## Earlier Firebase option

Recorded 2026-09-06. Firebase remains an alternative to the Supabase recommendation above. The running app still uses the local PostgreSQL implementation described above.

Firebase storage split assessed:

- **Structured records:** evaluate [Firebase SQL Connect](https://firebase.google.com/docs/sql-connect), formerly Data Connect, which uses Cloud SQL PostgreSQL. Keep the Hono API, Better Auth, stable IDs, and revision/idempotency protocol initially. Generated client connectors are a separate integration, not a replacement connection string. Retain one migration owner; review [schema management](https://firebase.google.com/docs/sql-connect/manage-schemas-and-connectors) before allowing SQL Connect to manage existing tables.
- **Binary notebook artifacts:** use Cloud Storage for Firebase for editable PencilKit data and portable previews, with database-owned artifact references and authorized access. Never store audio there. Cloud Storage requires the Blaze billing plan under its [current billing requirements](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024); SQL Connect and its database have [separate pricing components](https://firebase.google.com/docs/sql-connect/pricing). No billing was enabled.
- **Firestore alternative:** choose this only as an explicit data-model migration. Its [offline behavior](https://firebase.google.com/docs/firestore/manage-data/enable-offline) uses last-write-wins for changes to the same document, which does not replace Sideleaf's conflict recovery. Keep large ink artifacts and growing transcript histories out of a single document under the [document-size limit](https://firebase.google.com/docs/firestore/quotas). Server SDK access still needs application ownership checks because it [bypasses Security Rules](https://firebase.google.com/docs/firestore/security/insecure-rules).
- **Live cloud transcription:** OpenAI is the preferred candidate. Implement it behind the transcription adapter after the endpoint/account retention review in [privacy.md](privacy.md#openai-candidate-review). A key alone does not complete the capture pipeline or satisfy its privacy gate.

Before remote migration, validate accounts, saved pages, histories, annotations, ink references, conflicts, exports, and deletion against the chosen backend. Preserve existing local data throughout. Firebase Authentication is not automatically selected by choosing Firebase storage.

## Data ownership and contracts

`shared/domain.ts` is the executable Zod contract. UUIDs are stable across saves. A notebook belongs to one authenticated user; a page has both an owner and a notebook. Every API read, write, history lookup, export and deletion checks ownership. A page cannot be moved into another account's notebook. Resolved annotations must match the source block, revision and exact quote. Page-write bodies reject unknown fields and forged transcript/AI provenance in this notes-only build.

The implemented relational model has auth users/sessions/accounts/verifications, notebooks, pages, and page revisions. Page documents contain independent block, ink, annotation and preparation collections. Preparation is labeled as background. A note exclusion flag affects export eligibility, not storage. No model output mutates manual text or ink.

Future transcript events and source-grounded items have contracts in `shared/providers.ts`; there is no active provider implementation behind those interfaces. Separate meeting/session, transcript revision, coaching job, summary/action, usage, entitlement and subscription tables still need migrations. The current prepared-meeting state is not a captured meeting.

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

## Next live architecture

Use one API process plus a background text-job worker initially. Do not create additional microservices without a concrete need. Add authenticated, owner-bound leases and streams; one active assisted session per account; provider events with stable IDs/sequences; persisted finalized text; interim-only display; timestamped interruption gaps; pause/resume with prompt microphone release; and retryable finalization.

Build a single reviewed streaming adapter behind `TranscriptionAdapter`. A browser AudioWorklet should emit small PCM frames through bounded buffers with explicit backpressure. Neither an accumulating Blob nor MediaRecorder recordings belong in this architecture. Dropped or rejected frames must result in an honest interruption. Only accepted active assisted intervals are billable. Cloud text analysis should operate on compact finalized deltas and annotations, with debouncing, cancellation and stale-result rejection.

Treat all preparation, reference text and transcript content as untrusted data. No meeting content may execute tools, contact people, change privileges or access secrets. Validate structured outputs and all source references on the server before persistence. AI notes and summaries need independent versions so regeneration cannot overwrite user edits.

## Documentation checked

- [Better Auth Drizzle adapter](https://better-auth.com/docs/adapters/drizzle)
- [PGlite and Drizzle integration](https://pglite.dev/docs/orm-support)
- [Hono Better Auth integration](https://hono.dev/examples/better-auth)
- [Apple SpeechAnalyzer overview and sample](https://developer.apple.com/videos/play/wwdc2025/277/)
