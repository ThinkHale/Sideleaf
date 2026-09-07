import { useState } from 'react';
import { ArrowRight, LockKeyhole } from 'lucide-react';
import { authClient, type ProductConfig } from '../api';
import { Brand } from './Brand';
export function Auth({ config, onDone }: { config: ProductConfig; onDone: () => void }) {
  const [register, setRegister] = useState(true),
    [busy, setBusy] = useState(false),
    [error, setError] = useState('');
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
                  else onDone();
                } catch {
                  setError('The notebook server is unavailable. Try again in a moment.');
                } finally {
                  setBusy(false);
                }
              }}
            >
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
              <button className="primary" disabled={busy}>
                {busy ? 'Opening notebook…' : register ? 'Create account' : 'Sign in'}
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
              }}
            >
              {register ? 'Already have an account? Sign in' : 'New here? Create an account'}
            </button>
          )}
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
