import { useState } from 'react';
import { Download, LogOut } from 'lucide-react';
import { Modal } from './Modal';
import { api, download, type ProductConfig } from '../api';
import { Recovery } from './Recovery';
import { BillingPlan } from './BillingPlan';
import { LegalLinks } from './LegalLinks';
export function Settings({
  config,
  email,
  userId,
  onClose,
  onLogout,
  onDeleted,
  beforePageExit = () => undefined,
  termsRequired = false,
}: {
  config: ProductConfig;
  email: string;
  userId: string;
  onClose: () => void;
  onLogout: () => Promise<void>;
  onDeleted: () => Promise<void>;
  beforePageExit?: () => void;
  termsRequired?: boolean;
}) {
  const [confirmation, setConfirmation] = useState(''),
    [error, setError] = useState(''),
    [cleanup, setCleanup] = useState<'capture' | 'checkout' | null>(null),
    [cleanupMessage, setCleanupMessage] = useState(''),
    [working, setWorking] = useState(false);
  async function act(fn: () => Promise<unknown>) {
    if (working || cleanup !== null) return;
    setWorking(true);
    try {
      setError('');
      await fn();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Request failed');
    } finally {
      setWorking(false);
    }
  }
  return (
    <Modal
      title="Your notebook, your data"
      onClose={onClose}
      dismissDisabled={working || cleanup !== null}
    >
      <p className="muted">{email}</p>
      <section className="settings-section">
        <h3>Account</h3>
        <button disabled={working || cleanup !== null} onClick={() => act(onLogout)}>
          <LogOut size={16} />
          Sign out and clear this device’s cache
        </button>
        <small>
          Save pending edits first. Signing out clears this account’s local drafts and recovery
          cache.
        </small>
      </section>
      <BillingPlan
        config={config}
        termsRequired={termsRequired}
        beforePageExit={beforePageExit}
        disabled={working || cleanup !== null}
      />
      {termsRequired && (
        <section className="settings-section">
          <h3>Finish account activity</h3>
          <p>
            These controls close Sideleaf activity that may have started on another device. They do
            not cancel an active subscription; use Manage subscription above for that.
          </p>
          <div className="settings-actions">
            <button
              type="button"
              disabled={working || cleanup !== null}
              onClick={() => {
                setCleanup('capture');
                setError('');
                setCleanupMessage('');
                void api<{ stopped: number }>('/capture/sessions/stop-all', {
                  method: 'POST',
                  body: JSON.stringify({}),
                })
                  .then(({ stopped }) =>
                    setCleanupMessage(
                      stopped
                        ? 'Active transcription was ended safely.'
                        : 'No active transcription was found.',
                    ),
                  )
                  .catch((cause) =>
                    setError(
                      cause instanceof Error
                        ? cause.message
                        : 'Active transcription could not be ended. Try again shortly.',
                    ),
                  )
                  .finally(() => setCleanup(null));
              }}
            >
              {cleanup === 'capture' ? 'Ending transcription…' : 'End active transcription'}
            </button>
            <button
              type="button"
              disabled={working || cleanup !== null}
              onClick={() => {
                setCleanup('checkout');
                setError('');
                setCleanupMessage('');
                void api<{ expired: number }>('/billing/checkout/expire', {
                  method: 'POST',
                  body: JSON.stringify({}),
                })
                  .then(({ expired }) =>
                    setCleanupMessage(
                      expired
                        ? 'The unfinished Sideleaf checkout was canceled.'
                        : 'No unfinished Sideleaf checkout was found.',
                    ),
                  )
                  .catch((cause) =>
                    setError(
                      cause instanceof Error
                        ? cause.message
                        : 'The unfinished checkout could not be canceled. Try again shortly.',
                    ),
                  )
                  .finally(() => setCleanup(null));
              }}
            >
              {cleanup === 'checkout' ? 'Canceling checkout…' : 'Cancel unfinished checkout'}
            </button>
          </div>
          {cleanupMessage && <p role="status">{cleanupMessage}</p>}
        </section>
      )}
      <section className="settings-section">
        <h3>Privacy</h3>
        <LegalLinks legal={config.legal} className="settings-legal-links" />
        <p>
          Typed notes, preparation, semantic marks, editable ink, and live transcription text are
          saved. When you start live transcription, your microphone audio streams to OpenAI for
          processing. Sideleaf does not save audio recordings.
        </p>
        <p>
          OpenAI may retain content in abuse monitoring logs for up to 30 days by default, or longer
          when required by law or necessary to prevent harm. See{' '}
          <a
            href="https://developers.openai.com/api/docs/guides/your-data"
            target="_blank"
            rel="noreferrer"
          >
            OpenAI’s data retention policy
          </a>
          .
        </p>
        <p>
          Offline drafts are stored in this browser. Other people using this browser profile may be
          able to read them. Use a private device and sign out when finished.
        </p>
        <button
          disabled={working || cleanup !== null}
          onClick={() =>
            act(async () =>
              download(
                JSON.stringify(await api('/account/export'), null, 2),
                'sideleaf-data.json',
                'application/json',
              ),
            )
          }
        >
          <Download size={16} />
          Export all account data
        </button>
        <small>
          This export includes excluded notes and saved revision history. Exclusion from a normal
          export does not delete source text.
        </small>
      </section>
      <Recovery userId={userId} />
      <section className="settings-section danger-zone">
        <h3>Delete account</h3>
        <p>
          Permanently delete the account, notebooks, pages, and their history from the active
          database. This does not guarantee removal from infrastructure backups.
        </p>
        <label>
          Type DELETE to confirm
          <input
            value={confirmation}
            disabled={working || cleanup !== null}
            onChange={(e) => setConfirmation(e.target.value)}
          />
        </label>
        <button
          className="danger"
          disabled={confirmation !== 'DELETE' || working || cleanup !== null}
          onClick={() =>
            act(async () => {
              beforePageExit();
              await api('/account', { method: 'DELETE', body: JSON.stringify({ confirmation }) });
              await onDeleted();
            })
          }
        >
          {working ? 'Finishing account action…' : 'Delete my account'}
        </button>
      </section>
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
    </Modal>
  );
}
