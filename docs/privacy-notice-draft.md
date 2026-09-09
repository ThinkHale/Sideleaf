# Legal-copy review status

Updated September 9, 2026. The earlier cloud-transcription notice draft has been superseded by the versioned product copy in [`shared/legal.ts`](../shared/legal.ts). The web app publishes that copy at `/terms` and `/privacy`; account creation requires two unchecked, affirmative controls for the current Terms version and the recording-law responsibility acknowledgement.

The Start surfaces still explain the microphone data path, provider retention boundary, deliberate Start action, live microphone state, and Pause/Stop behavior. They now use a passive reminder rather than asking the user to repeat the same legal attestation for every capture.

This implementation records assent and makes the user-responsibility allocation conspicuous, but it does not decide which recording, interception, workplace, education, privacy, or confidentiality rules apply to a particular conversation. It also does not make the Terms or liability provisions enforceable in every jurisdiction. ThinkHale should have qualified counsel review the operator identity/contact details, launch jurisdictions, age/eligibility rules, governing law and dispute terms, retention commitments, consumer subscription requirements, and the complete Terms and Privacy Notice before broad release.

Do not describe Sideleaf as never capturing audio: browser live transcription transmits microphone audio to OpenAI, while native live transcription processes bounded microphone buffers on device. Sideleaf does not create a user audio library or save an audio file in the implemented paths. Provider, operating-system, infrastructure-backup, billing, and legal-retention behavior remain separate boundaries documented in [privacy.md](privacy.md).
