import { useEffect } from 'react';
import { Printer } from 'lucide-react';
import {
  CURRENT_TERMS_VERSION,
  PRIVACY_PATH,
  PRIVACY_SECTIONS,
  TERMS_EFFECTIVE_AT,
  TERMS_PATH,
  TERMS_SECTIONS,
} from '../../shared/legal';
import { Brand } from './Brand';

export function LegalDocument({ kind }: { kind: 'terms' | 'privacy' }) {
  const terms = kind === 'terms';
  const title = terms ? 'Terms of Service' : 'Privacy Notice';
  const sections = terms ? TERMS_SECTIONS : PRIVACY_SECTIONS;
  const alternatePath = terms ? PRIVACY_PATH : TERMS_PATH;
  const alternateLabel = terms ? 'Privacy Notice' : 'Terms of Service';
  const effectiveDate = new Date(`${TERMS_EFFECTIVE_AT}T00:00:00Z`).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    timeZone: 'UTC',
  });

  useEffect(() => {
    document.title = `${title} · Sideleaf`;
  }, [title]);

  return (
    <main className="legal-document-shell">
      <article className="legal-document" aria-labelledby="legal-document-title">
        <header className="legal-document-header">
          <a className="legal-brand" href="/" aria-label="Return to Sideleaf">
            <Brand />
          </a>
          <div className="legal-document-actions">
            <a href={alternatePath}>{alternateLabel}</a>
            <button type="button" onClick={() => window.print()}>
              <Printer size={16} aria-hidden="true" />
              Print
            </button>
          </div>
          <p className="legal-eyebrow">Sideleaf</p>
          <h1 id="legal-document-title">{title}</h1>
          <p className="legal-document-meta">
            Effective <time dateTime={TERMS_EFFECTIVE_AT}>{effectiveDate}</time>
            {terms && <> · Version {CURRENT_TERMS_VERSION}</>}
          </p>
        </header>
        <div className="legal-document-intro">
          {terms
            ? 'Please read these Terms carefully. They govern your access to and use of Sideleaf.'
            : 'This notice explains what information Sideleaf handles, why it is used, and the choices available to you.'}
        </div>
        {sections.map((section) => (
          <section key={section.heading}>
            <h2>{section.heading}</h2>
            {section.paragraphs.map((paragraph) => (
              <p key={paragraph}>{paragraph}</p>
            ))}
            {section.bullets && (
              <ul>
                {section.bullets.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            )}
          </section>
        ))}
        <footer className="legal-document-footer">
          <a href="/">Return to Sideleaf</a>
          <a href={alternatePath}>{alternateLabel}</a>
        </footer>
      </article>
    </main>
  );
}
