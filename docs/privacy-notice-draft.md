# Cloud transcription notice draft

Updated September 7, 2026 for the implemented WebRTC transcription flow. The hosted browser flow passed a test with synthetic microphone input, real OpenAI transcription and saved text in Supabase. This is product copy for review, not a complete published Privacy Policy or Terms of Service. Physical microphone/native validation and the final retention/deletion policy remain separate work.

## Proposed Privacy Policy paragraph

When you start live transcription, Sideleaf captures your device's microphone and streams audio directly to OpenAI to turn speech into text. Sideleaf does not save audio recordings or provide audio playback. Sideleaf saves finalized transcript text, your notebook content and session timing so you can review your notes and usage. OpenAI may retain API content in abuse-monitoring logs for up to 30 days by default, with legal or safety exceptions. API content is not used for training unless the API account opts in.

The provider portion follows [OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data). Confirm the actual endpoint and account configuration before publishing. State the final transcript, billing and backup retention policies separately. Do not promise immediate provider or backup erasure.

## Proposed notice before Start

Your microphone audio streams to OpenAI for live transcription. Sideleaf saves the transcript, not audio recordings. OpenAI may retain API content for abuse monitoring for up to 30 days by default, with legal or safety exceptions. Inform everyone participating and obtain any required permission before starting.

Connected transcription time, including brief setup, counts toward your allowance. Pause releases the microphone and stops the usage clock. A brief connection interruption can leave a gap in the transcript; Sideleaf does not save audio to fill that gap later.

Suggested acknowledgement: “I have informed participants and obtained the consent required for this meeting.”

Keep the current microphone status and Pause/Stop controls visible during capture, including in focus mode. Link the final full policy from the start flow. Transcription is for what this device's microphone can hear; this build does not capture arbitrary remote-call or system audio.

## Terms and remaining review

The Terms should explain acceptable use and participant-permission responsibilities. The Privacy Policy should identify the collected information, processing purpose, providers, retention and user controls. Repeat the key facts at the Start action so users can make an informed choice before transmission.

Do not say “we never record” without explaining microphone capture. Do not say audio is never stored anywhere, or that every copy is deleted after a fixed period. Terms acceptance does not replace participant permission where it is required. Final wording should be reviewed for the actual launch jurisdictions and customer use cases; this document makes no conclusion about a particular recording or interception law.

The code has configuration gates, microphone controls, server-confirmed text persistence, account-scoped access and a session watchdog. The September 7 hosted real-provider tests also verified Pause/Resume, one full rollover and network-loss cleanup, and deleted their synthetic accounts. They did not validate a physical microphone, native capture, repeated long-meeting reliability or provider-internal retention. Final publication still needs defined backup and stored-text retention and reviewed customer-facing copy. This change does not publish legal terms or accept them on anyone's behalf.
