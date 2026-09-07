import { useState } from 'react';
import { Download, LogOut } from 'lucide-react';
import { Modal } from './Modal';
import { api, download, type ProductConfig } from '../api';
import { Recovery } from './Recovery';
import { BillingPlan } from './BillingPlan';
export function Settings({
  config,
  email,
  userId,
  onClose,
  onLogout,
  onDeleted,
}: {
  config: ProductConfig;
  email: string;
  userId: string;
  onClose: () => void;
  onLogout: () => Promise<void>;
  onDeleted: () => Promise<void>;
}) {
  const [confirmation, setConfirmation] = useState(''),
    [error, setError] = useState('');
  async function act(fn: () => Promise<unknown>) {
    try {
      setError('');
      await fn();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Request failed');
    }
  }
  return (
    <Modal title="Your notebook, your data" onClose={onClose}>
      <p className="muted">{email}</p>
      <section className="settings-section">
        <h3>Account</h3>
        <button onClick={() => act(onLogout)}>
          <LogOut size={16} />
          Sign out and clear this device’s cache
        </button>
        <small>
          Save pending edits first. Signing out clears this account’s local drafts and recovery
          cache.
        </small>
      </section>
      <BillingPlan config={config} />
      <section className="settings-section">
        <h3>Privacy</h3>
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
          <input value={confirmation} onChange={(e) => setConfirmation(e.target.value)} />
        </label>
        <button
          className="danger"
          disabled={confirmation !== 'DELETE'}
          onClick={() =>
            act(async () => {
              await api('/account', { method: 'DELETE', body: JSON.stringify({ confirmation }) });
              await onDeleted();
            })
          }
        >
          Delete my account
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
