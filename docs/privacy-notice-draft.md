# Cloud transcription notice draft

Drafted 2026-09-07 for product discussion and legal review. This is proposed copy for the future cloud transcription feature, not a complete Privacy Policy or Terms of Service, and not a statement that the feature is live today.

## Proposed Privacy Policy paragraph

When you start cloud transcription, Sideleaf captures microphone audio and sends it to OpenAI to turn speech into text. Sideleaf processes audio in temporary buffers and does not save audio recordings in its application storage or provide audio playback. OpenAI may retain content in abuse-monitoring logs, generally for up to 30 days, with longer retention for legal requirements or protection from harm. Provider handling depends on the endpoint and account configuration. Sideleaf saves your transcript and notebook content so you can review and edit it later.

Source for the provider-retention portion: [OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data). Confirm against the actual deployment before publication. Link the final policy to Sideleaf's defined transcript retention, deletion and backup practices; do not promise immediate provider or backup erasure.

## Proposed notice immediately before cloud capture

Your microphone audio will be sent to OpenAI for live transcription. Sideleaf will save the transcript, but will not save an audio recording. OpenAI may temporarily retain processing data under its retention policy. Make sure everyone participating knows transcription is active and that you have any required permission before starting.

Place a link to the full audio/privacy notice alongside the deliberate Start action. Show the selected local or cloud mode accurately. Keep the microphone indicator and one-tap Pause visible throughout capture.

## Terms and review notes

The Terms should explain acceptable use and participant-permission responsibilities and link to the Privacy Policy. The Privacy Policy should identify the data collected, processing purpose, provider, retention, and user controls. Repeat the relevant facts in the start flow so someone can make an informed choice at the moment audio is transmitted.

Avoid the blanket claim that Sideleaf is not recording: microphone capture and transmission still occur, even without saved recordings. Avoid saying audio is never stored anywhere, or that all OpenAI data is automatically deleted after a fixed short period. The final wording must describe observed deployment behavior.

Terms acceptance should not be presented as a substitute for required participant consent. Have counsel review the notices and consent flow for the actual launch jurisdictions and customer use cases. No conclusion about a particular recording/interception law is made here. The FTC emphasizes that privacy promises must align with service-provider practices and continuing oversight: [service-provider guidance](https://www.ftc.gov/business-guidance/blog/2018/04/lesson-blu-make-right-privacy-security-calls-when-working-service-providers).

Publication depends on a working and tested capture pipeline, verified provider configuration, completed stored-text retention/deletion disclosures, and reviewed final copy. No notice was published or accepted on anyone's behalf.
