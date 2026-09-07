# Privacy and audio handling

Reviewed September 7, 2026. This document describes the implemented browser capture path, the provider's published data controls and the remaining device/operational checks. The hosted browser flow passed a test with synthetic microphone input and real OpenAI transcription. See [live capture setup](live-capture.md) for the connection and supervision design and [status](status.md) for the verification scope.

## Product direction

The owner permits disclosed OpenAI retention while Sideleaf itself must not save audio recordings. The browser captures the microphone for live transcription and sends audio directly to OpenAI over WebRTC. Sideleaf provides no audio recording library, playback, audio download, persistent audio queue or offline audio recovery. Microphone capture and transmission still happen; “no saved audio recordings” is the intended statement.

The live capture implementation is guarded by server configuration and a healthy session supervisor. A disabled deployment does not request microphone access through the Start control. A key alone is insufficient: `CAPTURE_ENABLED`, `CAPTURE_WATCHDOG_ENABLED` and recent watchdog health are also required. The September 7 hosted tests verified actual OpenAI transcription, saved text in Supabase, Pause/Resume, one full connection rollover and network-loss cleanup using Chromium with synthetic microphone input.

## Implemented browser behavior

The user chooses a saved notebook page, reads the audio disclosure, confirms participant permission and deliberately starts capture. The browser requests microphone access, creates a WebRTC connection and keeps its audio track disabled until the server's transcript observer is ready. The standard OpenAI API key stays on the server. The browser receives a session description, not the shared provider key.

A server-side WebSocket observer connects to the same OpenAI call. It accepts final transcript events from the provider, deduplicates them by session and provider item ID, and saves text in the private Supabase database. The browser receives confirmed saved segments over a server-sent event stream. Its own data channel can display interim speech, but a browser-supplied transcript cannot become trusted server transcript provenance. Saved transcripts remain separate from ordinary note documents and do not overwrite manual notes or ink.

Pause, Stop, component disposal and detected interruptions release microphone tracks. Long sessions reconnect before the host's function duration limit; speech during the brief reconnect is not preserved. There is no silent audio retry queue. Text not confirmed by the server is labeled unconfirmed and can be copied or exported by the user; it is not represented as saved transcript. Automatic offline storage of audio is absent.

The browser/operating system manages transient WebRTC audio buffers. Sideleaf does not use MediaRecorder, accumulate audio Blobs, write audio files or upload recordings. The server observer has a bounded event queue and message size, retains only selected text-event fields, and stops when text processing fails or falls behind. These code choices do not establish how OpenAI, device drivers or the operating system implement their own internal buffers.

Connected transcription time, including brief connection setup after the provider session is available, counts toward the allowance. Paused time is excluded. Session and usage records contain ownership, timing, provider call identifiers and final text rather than audio content. A watchdog terminates abandoned calls and keeps new starts unavailable when supervision becomes stale or cleanup remains unhealthy.

## OpenAI data controls

The implemented adapter creates a transcription-only Realtime call using `gpt-4o-mini-transcribe`. OpenAI documents WebRTC for browser transcription and a separate server connection for session monitoring. [Realtime transcription](https://developers.openai.com/api/docs/guides/realtime-transcription), [server-side controls](https://developers.openai.com/api/docs/guides/realtime-server-controls).

OpenAI's published `/v1/realtime` controls list no training use by default, 30-day abuse-monitoring retention and no application-state retention. Abuse logs can contain content, and retention can extend for legal or safety reasons. Account-specific controls may differ. The separate file-transcription retention entry must not be applied to Realtime. Do not promise that all audio is retained, or that every copy is deleted exactly on day 30. [OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data).

Sideleaf does not request Realtime tracing or send note preparation into the transcription adapter. No cloud coaching or summary generation is implemented by this slice. The hosted tests verify provider access, the browser-to-saved-text path and the exercised reconnection/cleanup cases. Physical microphone behavior, native capture and repeated long-meeting reliability remain unvalidated. The application code and tests cannot independently guarantee the provider's internal retention practices or establish a particular account's retention agreement.

## Stored text, controls and deletion

Sideleaf stores notebook text, preparation, annotation metadata, editable web ink points, page history, saved transcript segments, session timing and usage totals. Stripe billing stores provider identifiers and subscription state separately; it does not store card details in Sideleaf. Native source stores text, PencilKit drawing data and PNG previews. Native capture and synchronization remain unfinished.

The live transcript panel provides a transcript text export. Full account export includes saved transcripts as well as notes and versions. Ordinary page-document exports do not automatically merge the separate meeting transcript. Exclusion flags on ordinary note blocks do not redact or delete transcript records.

An active meeting must be stopped before deleting its page or account. Deleting a page cascades into its transcript segments and session records; aggregate monthly usage remains so deleting a page cannot reset the monthly allowance. Account deletion requires a sign-in within the previous five minutes and removes owned application/authentication records, after active capture and unresolved billing checks. Financial records retained by a payment processor and infrastructure backups have their own retention behavior.

Removing a note block does not erase older page revisions. Targeted irreversible phrase redaction across all revisions remains unfinished. Browser recovery copies can remain until sign-out; page deletion is not a promise of instant erasure from every device or backup.

The start notice asks the user to inform participants and obtain required permission. Sideleaf's Terms should explain those responsibilities and link to the final Privacy Policy. The [notice draft](privacy-notice-draft.md) describes this implementation but is not a complete published policy or a legal-compliance determination.

## Storage, logs and backups

The private Supabase schema is accessed by the authenticated Sideleaf API. The browser does not receive database credentials. Server errors omit request bodies, SQL values, stack traces, credentials and note/transcript content. Better Auth logging is disabled, and no analytics or error-reporting SDK is installed. Reverse proxies, traces, crash reports and provider dashboards must not be configured to collect audio or note bodies.

Local development data is outside the OneDrive repository. IndexedDB uses account namespaces for offline manual notes and recovery drafts; it is not application-encrypted. Signing out clears the account's page and recovery cache. An offline identity never grants API access. The service worker does not cache API responses or audio.

Backups, infrastructure snapshots, device backups and filesystem recovery can retain earlier data independently of active-record deletion. Sideleaf does not promise immediate backup erasure. Production operations must define retention windows, restoration access and expiry for those copies. Certificate-verified database TLS and least-privilege runtime access are implemented; native Keychain session storage and native cross-device operation still require the Mac/Xcode work.
