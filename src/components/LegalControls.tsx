import type { LegalMetadata } from '../api';

export function LegalControls({
  legal,
  termsAccepted,
  recordingLawAcknowledged,
  onTermsAccepted,
  onRecordingLawAcknowledged,
  disabled = false,
}: {
  legal: LegalMetadata;
  termsAccepted: boolean;
  recordingLawAcknowledged: boolean;
  onTermsAccepted: (accepted: boolean) => void;
  onRecordingLawAcknowledged: (acknowledged: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <fieldset className="legal-controls" disabled={disabled}>
      <legend>Agreements required to continue</legend>
      <p className="legal-control-meta">
        Terms version <strong>{legal.termsVersion}</strong>
        <span aria-hidden="true"> · </span>
        Effective <time dateTime={legal.effectiveAt}>{legal.effectiveAt}</time>
      </p>
      <label className="legal-check">
        <input
          type="checkbox"
          required
          checked={termsAccepted}
          onChange={(event) => onTermsAccepted(event.target.checked)}
        />
        <span>
          I agree to the{' '}
          <a
            href={legal.termsUrl}
            target="_blank"
            rel="noreferrer"
            aria-label="Terms of Service (opens in a new tab)"
          >
            Terms of Service
          </a>{' '}
          and acknowledge the{' '}
          <a
            href={legal.privacyUrl}
            target="_blank"
            rel="noreferrer"
            aria-label="Privacy Notice (opens in a new tab)"
          >
            Privacy Notice
          </a>
          .
        </span>
      </label>
      <label className="legal-check">
        <input
          type="checkbox"
          required
          checked={recordingLawAcknowledged}
          onChange={(event) => onRecordingLawAcknowledged(event.target.checked)}
        />
        <span>{legal.recordingLawAcknowledgement}</span>
      </label>
    </fieldset>
  );
}
