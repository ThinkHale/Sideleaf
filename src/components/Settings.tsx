import { useState } from 'react';
import { Download, LogOut } from 'lucide-react';
import { Modal } from './Modal';
import { api, download, type ProductConfig } from '../api';
import { Recovery } from './Recovery';
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
      <section className="settings-section">
        <h3>Privacy</h3>
        <p>
          Typed notes, preparation, semantic marks, and editable ink are saved. This build does not
          access the microphone or send notes to an AI provider.
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
      <section className="settings-section">
        <h3>Plans</h3>
        <div className="plan-row">
          <div>
            <strong>Free</strong>
            <p>
              Unlimited ordinary notes
              <br />
              {config.freeMinutes} assisted minutes per month
              <br />
              {config.meetingMinutes} minutes per assisted meeting
            </p>
          </div>
          <div>
            <strong>Pro · ${config.price}/month</strong>
            <p>
              Unlimited assisted minutes
              <br />
              One active assisted session
              <br />
              Configurable test price
            </p>
          </div>
        </div>
        <div className="notice">
          Plan preview. Capture, usage metering, checkout, and purchases are not enabled in this
          build. No payment is collected.
        </div>
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
