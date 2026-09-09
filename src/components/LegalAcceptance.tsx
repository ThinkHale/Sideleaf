import { useState } from 'react';
import { ArrowRight, ShieldCheck } from 'lucide-react';
import {
  acceptLegalTerms,
  legalMetadataFromAcceptanceError,
  type LegalMetadata,
  type LegalStatus,
  type ProductConfig,
} from '../api';
import { Brand } from './Brand';
import { LegalControls } from './LegalControls';
import { Settings } from './Settings';

export function LegalAcceptance({
  legal,
  config,
  identity,
  initialError = '',
  onAccepted,
  onLogout,
  onDeleted,
}: {
  legal: LegalMetadata;
  config: ProductConfig;
  identity: { id: string; email: string };
  initialError?: string;
  onAccepted: (status: LegalStatus) => void | Promise<void>;
  onLogout: () => Promise<void>;
  onDeleted: () => Promise<void>;
}) {
  const [termsAccepted, setTermsAccepted] = useState(false);
  const [recordingLawAcknowledged, setRecordingLawAcknowledged] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(initialError);
  const [showAccountOptions, setShowAccountOptions] = useState(false);

  return (
    <main className="legal-gate">
      <section className="legal-gate-card" aria-labelledby="legal-gate-title">
        <Brand variant="icon" />
        <div className="legal-gate-heading">
          <ShieldCheck size={22} aria-hidden="true" />
          <div>
            <h1 id="legal-gate-title">Before you continue</h1>
            <p>
              Please review Sideleaf’s terms and confirm your responsibility when using live
              transcription.
            </p>
          </div>
        </div>
        <form
          aria-busy={busy}
          onSubmit={async (event) => {
            event.preventDefault();
            setBusy(true);
            setError('');
            try {
              const status = await acceptLegalTerms(legal.termsVersion);
              if (!status.accepted || status.legal.termsVersion !== legal.termsVersion)
                throw new Error('The current terms still need your acceptance. Please try again.');
              await onAccepted(status);
            } catch (cause) {
              if (legalMetadataFromAcceptanceError(cause)) {
                setTermsAccepted(false);
                setRecordingLawAcknowledged(false);
                setError('The Terms of Service changed. Review the current version to continue.');
                return;
              }
              setError(
                cause instanceof Error
                  ? cause.message
                  : 'We could not save your acceptance. Check your connection and try again.',
              );
            } finally {
              setBusy(false);
            }
          }}
        >
          <LegalControls
            legal={legal}
            termsAccepted={termsAccepted}
            recordingLawAcknowledged={recordingLawAcknowledged}
            onTermsAccepted={setTermsAccepted}
            onRecordingLawAcknowledged={setRecordingLawAcknowledged}
            disabled={busy}
          />
          {error && (
            <p className="error legal-gate-error" role="alert">
              {error}
            </p>
          )}
          <button
            className="primary legal-continue"
            disabled={busy || !termsAccepted || !recordingLawAcknowledged}
          >
            {busy ? 'Saving your acceptance…' : error ? 'Try again' : 'Agree and continue'}
            {!busy && <ArrowRight size={17} aria-hidden="true" />}
          </button>
        </form>
        <p className="fine-print">
          Sideleaf’s notice and controls do not determine which laws apply to a conversation.
        </p>
        <button
          type="button"
          className="text-button legal-account-options"
          onClick={() => setShowAccountOptions(true)}
        >
          Account, billing, and data options
        </button>
      </section>
      {showAccountOptions && (
        <Settings
          config={config}
          email={identity.email}
          userId={identity.id}
          termsRequired
          onClose={() => setShowAccountOptions(false)}
          onLogout={onLogout}
          onDeleted={onDeleted}
        />
      )}
    </main>
  );
}
