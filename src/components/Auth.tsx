import { useEffect, useState } from 'react';
import { ArrowRight, LockKeyhole } from 'lucide-react';
import {
  acceptLegalTerms,
  authClient,
  legalMetadataFromAcceptanceError,
  type ProductConfig,
} from '../api';
import { Brand } from './Brand';
import { LegalControls } from './LegalControls';
import { LegalLinks } from './LegalLinks';
export function Auth({
  config,
  onDone,
  accountNotice = '',
}: {
  config: ProductConfig;
  onDone: () => void;
  accountNotice?: string;
}) {
  const [register, setRegister] = useState(true),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [termsAccepted, setTermsAccepted] = useState(false),
    [recordingLawAcknowledged, setRecordingLawAcknowledged] = useState(false),
    [acceptancePending, setAcceptancePending] = useState(false),
    [currentLegal, setCurrentLegal] = useState(config.legal);
  useEffect(() => {
    setCurrentLegal(config.legal);
    setTermsAccepted(false);
    setRecordingLawAcknowledged(false);
  }, [config.legal]);
  async function saveAcceptance() {
    const status = await acceptLegalTerms(currentLegal.termsVersion);
    if (!status.accepted || status.legal.termsVersion !== currentLegal.termsVersion)
      throw new Error('The current terms still need your acceptance. Please try again.');
  }
  function recoverChangedTerms(cause: unknown) {
    const metadata = legalMetadataFromAcceptanceError(cause);
    if (!metadata) return false;
    setCurrentLegal(metadata);
    setAcceptancePending(true);
    setTermsAccepted(false);
    setRecordingLawAcknowledged(false);
    setError('The Terms of Service changed. Review the current version before continuing.');
    return true;
  }
  return (
    <main className="auth-layout">
      <div className="auth-aside">
        <Brand name={config.name} variant="tagline" className="auth-brand" />
        <div>
          <h1>
            A little space
            <br />
            to think clearly.
          </h1>
          <p>
            Your notes, questions, and next steps.
            <br />
            All in one quiet place.
          </p>
        </div>
        <small>{config.name}</small>
      </div>
      <section className="auth-form">
        <div className="auth-content">
          <Brand name={config.name} className="mobile-brand" />
          <h2>{register ? 'Open your notebook' : 'Welcome back'}</h2>
          <p className="muted">A place for the things worth remembering.</p>
          {accountNotice && (
            <div className="notice" role="status">
              <span>{accountNotice}</span>
            </div>
          )}
          {config.development && (
            <div className="notice">
              <LockKeyhole size={16} />
              <span>
                Local development. Create an account on this computer. No cloud services are
                connected.
              </span>
            </div>
          )}
          {config.passwordAuth && (
            <form
              onSubmit={async (e) => {
                e.preventDefault();
                setBusy(true);
                setError('');
                const data = new FormData(e.currentTarget);
                try {
                  if (acceptancePending) {
                    await saveAcceptance();
                    onDone();
                    return;
                  }
                  const credentials = {
                    email: String(data.get('email')),
                    password: String(data.get('password')),
                  };
                  const result = register
                    ? await authClient.signUp.email({
                        ...credentials,
                        name: String(data.get('name')),
                      })
                    : await authClient.signIn.email(credentials);
                  if (result.error) setError(result.error.message || 'Unable to sign in.');
                  else if (register) {
                    try {
                      await saveAcceptance();
                      onDone();
                    } catch (cause) {
                      if (recoverChangedTerms(cause)) return;
                      setAcceptancePending(true);
                      setError(
                        'Your account was created, but we could not save your acceptance. Check your connection and try again.',
                      );
                    }
                  } else onDone();
                } catch (cause) {
                  if (recoverChangedTerms(cause)) return;
                  setError(
                    cause instanceof Error
                      ? cause.message
                      : 'The notebook server is unavailable. Try again in a moment.',
                  );
                } finally {
                  setBusy(false);
                }
              }}
              aria-busy={busy}
            >
              <fieldset className="auth-fields" disabled={acceptancePending}>
                {register && (
                  <label>
                    Your name
                    <input name="name" autoComplete="name" required maxLength={100} />
                  </label>
                )}
                <label>
                  Email
                  <input name="email" type="email" autoComplete="email" required />
                </label>
                <label>
                  Password
                  <input
                    name="password"
                    type="password"
                    autoComplete={register ? 'new-password' : 'current-password'}
                    required
                    minLength={10}
                  />
                  <small>At least 10 characters</small>
                </label>
              </fieldset>
              {register && (
                <LegalControls
                  legal={currentLegal}
                  termsAccepted={termsAccepted}
                  recordingLawAcknowledged={recordingLawAcknowledged}
                  onTermsAccepted={setTermsAccepted}
                  onRecordingLawAcknowledged={setRecordingLawAcknowledged}
                  disabled={busy}
                />
              )}
              <button
                className="primary"
                disabled={busy || (register && (!termsAccepted || !recordingLawAcknowledged))}
              >
                {busy
                  ? acceptancePending
                    ? 'Saving your acceptance…'
                    : 'Opening notebook…'
                  : acceptancePending
                    ? 'Try saving acceptance again'
                    : register
                      ? 'Create account'
                      : 'Sign in'}
                <ArrowRight size={17} />
              </button>
            </form>
          )}
          {config.googleAuth && (
            <button
              onClick={() => authClient.signIn.social({ provider: 'google', callbackURL: '/' })}
            >
              Continue with Google
            </button>
          )}
          {!config.passwordAuth && !config.googleAuth && (
            <p className="error">
              Authentication is not configured. A verified identity provider is required for this
              deployment.
            </p>
          )}
          {error && (
            <p role="alert" className="error">
              {error}
            </p>
          )}
          {config.passwordAuth && (
            <button
              className="text-button auth-switch"
              onClick={() => {
                setRegister(!register);
                setError('');
                setAcceptancePending(false);
                setTermsAccepted(false);
                setRecordingLawAcknowledged(false);
              }}
            >
              {acceptancePending
                ? 'Return to sign in'
                : register
                  ? 'Already have an account? Sign in'
                  : 'New here? Create an account'}
            </button>
          )}
          <LegalLinks legal={currentLegal} className="auth-legal-links" />
          <p className="fine-print">
            Manual notes work without a meeting.
            <br />
            The microphone stays off until capture is available and you deliberately start it.
          </p>
        </div>
      </section>
    </main>
  );
}
