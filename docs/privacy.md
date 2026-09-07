# Privacy and audio handling

Reviewed 2026-09-07. This document separates actual code behavior, provider statements, and future deployment obligations.

## Updated product direction

The owner clarified on 2026-09-07 that disclosed OpenAI retention is acceptable while Sideleaf itself must not save audio. This replaces the original requirement for zero audio persistence across all providers. Standard provider retention may be used after checking the deployed endpoint/account and implementing clear disclosures. Zero Data Retention is optional under this revised direction, not a prerequisite for all cloud transcription.

Sideleaf must still use bounded temporary audio buffers, avoid audio files and persistent audio queues, and provide no recording library or replay feature. A change in Terms of Service does not implement or verify these behaviors. The app still has no capture implementation. [Draft notice language](privacy-notice-draft.md) is for the future cloud feature and legal review, not published terms.

## Implemented behavior

The shipped web slice never requests a microphone, opens an audio stream, calls browser speech recognition, or connects to a transcription provider. `/api/capture/start` returns 503 with `CAPTURE_NOT_CONFIGURED`. The readiness UI states that live transcription is not connected. This is not a simulated transcription demo or a credential-only integration.

The native source checks SpeechTranscriber and downloads model assets only after a button press. It does not start capture. No audio input pipeline exists yet on either client. Consequently there are no application audio buffers, recordings, replay controls, storage paths or background audio upload queues to audit as an implemented streaming feature.

The app stores text, preparation, annotation metadata, editable web ink points and page history. Native source stores text, `PKDrawing` data and PNG previews. Binary ink artifacts are not audio. Browser Blob creation is limited to downloadable text/JSON artifacts. API schemas reject unknown audio fields. This does not establish a future provider's memory or retention behavior.

No analytics or error-reporting SDK is installed. Better Auth logging is disabled. Application API errors omit request bodies, SQL values, stack traces, passwords and note content. Server startup logs contain only service status. Do not enable request-body logging when adding reverse proxies, APM, traces, crash reports, WebSockets or worker queues.

## Provider evidence and remaining gates

| Route                    | Official evidence                                                                                                                                                                                                                                                                                                                                                                           | Current decision                                                                                                                                                                                                                                                                           |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Apple SpeechTranscriber  | Apple's [SpeechAnalyzer session](https://developer.apple.com/videos/play/wwdc2025/277/) describes an on-device model, device/language restrictions and downloadable assets. Its sample also writes recordings and uses an unbounded stream; those portions must not be copied.                                                                                                              | Readiness probe only. Physical iPad checks, bounded capture, interruption handling and asset readiness must be tested before enabling capture.                                                                                                                                             |
| Deepgram cloud streaming | The [Model Improvement Partnership documentation](https://developers.deepgram.com/docs/the-deepgram-model-improvement-partnership-program) documents `mip_opt_out=true` and says opted-out request data is retained only for the time needed to process the request. The [streaming API](https://developers.deepgram.com/reference/speech-to-text/listen-streaming) exposes this parameter. | Candidate only. No adapter is implemented or enabled. Confirm the actual account/contract, service logging and transient-processing interpretation against the no-persistence requirement. A training opt-out alone must not be described as independently verified zero disk persistence. |
| Browser speech services  | No specific browser/vendor retention terms have been established for this product.                                                                                                                                                                                                                                                                                                          | Disabled. No Web Speech API fallback.                                                                                                                                                                                                                                                      |
| Cloud text AI            | No provider has been connected. Audio and text retention are different questions.                                                                                                                                                                                                                                                                                                           | Review text-provider retention/training and user disclosures before connecting coaching. Do not call cloud coaching fully local or offline.                                                                                                                                                |

Before a cloud audio route is enabled, record dated official policy URLs, exact request settings, the deployment account's retention mode and applicable exceptions, and provider confirmation where an endpoint's handling is ambiguous. Add an executable readiness gate for configuration and reviewed disclosure. Verify no audio is intentionally written to Sideleaf application files, database, object storage, browser storage, logs, analytics, backups or error reports. Limit processing queues in bytes/time, stop on backpressure, dispose frames promptly and never preserve an offline audio queue. Provider retention is a separate disclosed practice under the updated direction above.

No live-provider test was run, and no provider privacy guarantee has been independently established for this deployment.

## OpenAI candidate review

Reviewed 2026-09-07 following the owner's preference for OpenAI transcription. OpenAI is the preferred cloud candidate; the route remains unimplemented and disabled.

OpenAI's [data controls](https://developers.openai.com/api/docs/guides/your-data) list `/v1/realtime` with 30-day abuse-monitoring retention and no application-state retention. Logs can contain customer content; retention can extend for legal requirements or protection from harm. ZDR requires approval and project configuration. The separate `/v1/audio/transcriptions` row lists no abuse-monitoring or application-state retention; do not transfer that promise to Realtime. Confirm the exact route and account mode rather than asserting every audio frame is retained or deletion always occurs by day 30.

The [Realtime transcription guide](https://developers.openai.com/api/docs/guides/realtime-transcription) supports transcription-only sessions, incremental text, and completed turns. It currently recommends `gpt-live-transcribe`. This is the intended live integration to evaluate, subject to the retention gate. File-oriented transcription is not a substitute for the requested live workflow.

Implementation requirements: keep the standard OpenAI key in a server secret; bound all audio queues; disable payload tracing; persist only accepted text; release microphone tracks on pause/end; and test live failures. Do not put audio into Supabase, Firebase, browser storage, temporary recordings, logs, or retry jobs. Preserve supported on-device iPad transcription as a separate path with no silent remote fallback. No key was supplied or used in this review.

## User controls and consent

The preparation flow identifies device-microphone capture as an in-person feature and explicitly excludes arbitrary remote-call audio capture. The consent checkbox enables only the readiness check. The displayed notice is a draft for legal review and makes no legal-compliance claim.

The microphone-off indicator remains visible in focus mode. Future capture must have truthful ready/connecting/listening/paused/interrupted/finalizing/complete states, participant-facing consent information and one-tap Pause. Capture interruptions must be recorded as gaps, not filled with invented speech.

Ordinary exports omit excluded text blocks and linked marks. Exclusion does not delete the source, preparation or history. Full account export intentionally includes excluded source and versions. Handwriting can contain private information, so the export dialog explains that ink is included separately in PDF. There is no handwriting recognition or automatic extraction into AI context.

Page deletion removes the active page and revision history through database cascading deletes. Account deletion requires a fresh sign-in within five minutes and removes owned application/authentication records. Targeted irreversible redaction of a phrase across its historical versions remains unimplemented; users must not mistake removing a block for erasing revision history. Browser device recovery copies remain until sign-out, so deleting a page is not a claim of erasing every client copy.

## Storage and backups

Local development data is under the user's local application-data folder, not the OneDrive repository. The code does not set up database backups. Operating-system backups, device sync, administrative snapshots and filesystem recovery may still retain data outside the application's control. There is no promised immediate backup erasure.

IndexedDB is account-namespaced, but it is not application-encrypted. Someone with access to the same unlocked browser profile may access cached notes. Use OS account protections and encrypted device storage. Signing out clears this account's local page and recovery caches. Session cookies authorize every server request; cached offline identity never grants API access.

Production configuration requires HTTPS and a persistent PostgreSQL service. Before real data is used, configure certificate-verified database TLS, encrypted volumes, least-privilege credentials, retention windows, backup expiration, restoration access and a documented deletion process. These are deployment gates, not guarantees supplied by the Dockerfile. Google OAuth configuration sends normal authentication data to Google when used; it has not been exercised here.
