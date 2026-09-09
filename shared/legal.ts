import { z } from 'zod';

export const CURRENT_TERMS_VERSION = '2026-09-09.1';
export const TERMS_EFFECTIVE_AT = '2026-09-09';
export const TERMS_PATH = '/terms';
export const PRIVACY_PATH = '/privacy';
// SHA-256 of the canonical JSON bundle asserted in tests/legal.test.ts. The server stores this
// fingerprint with each acceptance so the accepted copy remains identifiable after later updates.
export const CURRENT_LEGAL_BUNDLE_SHA256 =
  'ea207ddf60331f6b136fe4fdf3749484827d97315dc8e8a726c5febecdc5af64';

export const RECORDING_LAW_ACKNOWLEDGEMENT =
  'I understand that laws governing recording and transcription vary by jurisdiction and circumstance. I am responsible for determining which requirements apply, informing participants, obtaining any required consent, and using Sideleaf lawfully.';

export const RECORDING_LAW_REMINDER =
  'Recording and transcription laws vary. You are responsible for any required notice and consent.';

export type LegalSection = {
  heading: string;
  paragraphs: readonly string[];
  bullets?: readonly string[];
};

export const TERMS_SECTIONS: readonly LegalSection[] = [
  {
    heading: '1. Agreement to these Terms',
    paragraphs: [
      'These Terms of Service govern your access to and use of Sideleaf, a service operated by ThinkHale. By creating an account, selecting the acceptance controls, or using Sideleaf, you agree to these Terms. If you do not agree, do not create an account or use the service.',
      'Sideleaf may present an updated version of these Terms for acceptance when material changes are made. The version and effective date shown with the Terms identify the agreement you accepted.',
    ],
  },
  {
    heading: '2. Accounts',
    paragraphs: [
      'You must provide accurate account information, protect your sign-in credentials, and promptly notify us through an available support channel if you believe your account has been compromised. You are responsible for activity carried out through your account to the extent permitted by law.',
    ],
  },
  {
    heading: '3. Your notes and transcripts',
    paragraphs: [
      'You retain ownership of the notes, transcript text, and other content you submit to Sideleaf. You give ThinkHale a limited license to host, process, transmit, reproduce, and format that content only as needed to operate, secure, support, and improve the service.',
      'You represent that you have the rights and permissions needed to provide content to Sideleaf. You are responsible for reviewing transcript text for errors before relying on it.',
    ],
  },
  {
    heading: '4. Microphone capture and your legal responsibilities',
    paragraphs: [
      'Sideleaf can use a device microphone to create live transcript text. The browser experience sends live microphone audio to OpenAI for transcription. The native iPhone and iPad experience uses Apple on-device speech processing. Sideleaf saves transcript text when you choose or authorize that action; Sideleaf does not provide an audio-recording library or save an audio file in your notebook.',
      'Recording, interception, privacy, wiretap, workplace, education, and confidentiality requirements vary by location, participant, and circumstance. You—not Sideleaf—are responsible for identifying the requirements that apply before you begin, giving every required notice, obtaining every required consent or other authorization, and stopping capture if authorization is absent or withdrawn.',
      'You may not use Sideleaf to capture or transcribe a communication secretly, unlawfully, or for a criminal, tortious, harassing, discriminatory, or otherwise harmful purpose. Sideleaf notices and controls do not determine whether a particular use is lawful and are not legal advice.',
    ],
  },
  {
    heading: '5. Acceptable use',
    paragraphs: ['You agree not to misuse Sideleaf or help another person do so.'],
    bullets: [
      'Do not violate law, another person’s rights, or a duty of confidentiality.',
      'Do not attempt to access another account or content without authorization.',
      'Do not disrupt, overload, reverse engineer, probe, or circumvent service safeguards except where applicable law expressly permits it.',
      'Do not upload malware or use Sideleaf to facilitate fraud, abuse, or harmful activity.',
    ],
  },
  {
    heading: '6. Privacy and service providers',
    paragraphs: [
      'Our Privacy Notice explains how Sideleaf handles account data, notes, transcript text, microphone audio, diagnostics, and service records. Sideleaf relies on service providers—including hosting, database, authentication, payment, and transcription providers—to operate the service. Their processing is described in the Privacy Notice and may also be governed by their terms.',
    ],
  },
  {
    heading: '7. Plans and billing',
    paragraphs: [
      'If Sideleaf offers a paid plan, the price, billing period, included features, and renewal terms will be shown before purchase. You authorize the displayed charges and applicable taxes. You can manage or cancel a subscription through the purchase channel made available to you; cancellation ordinarily applies at the end of the current paid period unless law or the purchase channel requires otherwise.',
    ],
  },
  {
    heading: '8. Beta service and changes',
    paragraphs: [
      'Sideleaf is an evolving service. Features may be added, changed, suspended, or discontinued, and beta functionality may be incomplete or unavailable. We may impose reasonable limits to protect users, providers, and the service. When practical, we will provide notice of a material change that significantly reduces paid functionality.',
    ],
  },
  {
    heading: '9. Suspension and termination',
    paragraphs: [
      'You may stop using Sideleaf and request account deletion through the available account controls. We may restrict or terminate access if reasonably necessary to address a Terms violation, unlawful use, security risk, nonpayment, provider requirement, or material harm to Sideleaf or others. Rights that by their nature should survive termination—including ownership, disclaimers, limits of liability, and responsibility for prior conduct—will survive.',
    ],
  },
  {
    heading: '10. Disclaimers',
    paragraphs: [
      'To the fullest extent permitted by law, Sideleaf is provided “as is” and “as available.” ThinkHale disclaims implied warranties, including merchantability, fitness for a particular purpose, title, and non-infringement. We do not promise that Sideleaf will be uninterrupted, error-free, secure, or suitable for legal, medical, employment, financial, or other professional decisions. Some jurisdictions do not allow certain disclaimers, so parts of this section may not apply to you.',
    ],
  },
  {
    heading: '11. Limitation of liability',
    paragraphs: [
      'To the fullest extent permitted by law, ThinkHale and its service providers will not be liable for indirect, incidental, special, consequential, exemplary, or punitive damages, or for lost profits, revenue, data, goodwill, or business interruption arising from Sideleaf. ThinkHale’s total liability for claims relating to Sideleaf will not exceed the greater of the amount you paid for Sideleaf during the 12 months before the event giving rise to the claim or 100 US dollars. These limits do not apply where prohibited by law.',
    ],
  },
  {
    heading: '12. General terms',
    paragraphs: [
      'If a provision of these Terms is unenforceable, it will be limited to the minimum extent necessary and the remaining provisions will continue in effect. A failure to enforce a provision is not a waiver. You may not transfer these Terms without our consent; ThinkHale may transfer them as part of a reorganization, financing, merger, acquisition, or sale of assets. These Terms and the documents they incorporate are the entire agreement about Sideleaf unless a separate written agreement applies.',
    ],
  },
];

export const PRIVACY_SECTIONS: readonly LegalSection[] = [
  {
    heading: 'Information Sideleaf handles',
    paragraphs: [
      'Sideleaf handles account details such as your name and email address; notebook titles, notes, transcript text, marks, and revision data; and limited service, authentication, billing, usage, and diagnostic records needed to operate and secure the service.',
    ],
  },
  {
    heading: 'Microphone and transcription data',
    paragraphs: [
      'In the browser, live microphone audio is sent directly to OpenAI over an encrypted connection to generate text. Sideleaf stores the resulting transcript text and session timing, not an audio file. OpenAI states that Realtime API content may appear in abuse-monitoring logs retained for up to 30 days by default, unless longer retention is legally required; approved data-control settings can differ.',
      'In the native iPhone and iPad app, Apple’s on-device speech APIs process bounded microphone buffers in memory. Microphone audio is not uploaded to Sideleaf, OpenAI, Vercel, or Supabase. Only transcript text you add to a page enters the ordinary synchronization path.',
    ],
  },
  {
    heading: 'How information is used and shared',
    paragraphs: [
      'Information is used to authenticate you, synchronize and export notebooks, provide transcription, operate billing, prevent abuse, troubleshoot failures, and maintain the service. Sideleaf shares information with service providers only as needed for those functions, or when required by law, to protect rights and safety, or as part of a business transaction subject to appropriate safeguards.',
    ],
  },
  {
    heading: 'Retention, security, and your choices',
    paragraphs: [
      'Sideleaf retains account content while your account is active and as reasonably needed to provide the service, resolve disputes, secure the service, and meet legal obligations. Account controls let you export or delete cloud account data. Device-only copies and operating-system backups may require separate removal on your devices.',
      'Sideleaf uses technical and organizational safeguards designed to protect information, but no service can guarantee absolute security. You can deny microphone permission and continue using ordinary notes; microphone capture begins only after a deliberate Start action.',
    ],
  },
];

export const legalAcceptanceSchema = z
  .object({
    termsVersion: z.literal(CURRENT_TERMS_VERSION),
    acceptedTerms: z.literal(true),
    recordingLawAcknowledged: z.literal(true),
  })
  .strict();

export type LegalMetadata = {
  termsVersion: string;
  effectiveAt: string;
  termsUrl: string;
  privacyUrl: string;
  recordingLawAcknowledgement: string;
};

export type LegalStatus = {
  accepted: boolean;
  acceptedAt: string | null;
  recordingLawAcknowledgedAt: string | null;
  legal: LegalMetadata;
};

export function legalMetadata(origin: string): LegalMetadata {
  return {
    termsVersion: CURRENT_TERMS_VERSION,
    effectiveAt: TERMS_EFFECTIVE_AT,
    termsUrl: new URL(TERMS_PATH, origin).toString(),
    privacyUrl: new URL(PRIVACY_PATH, origin).toString(),
    recordingLawAcknowledgement: RECORDING_LAW_ACKNOWLEDGEMENT,
  };
}
