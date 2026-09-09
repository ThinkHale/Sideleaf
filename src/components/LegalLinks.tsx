import type { LegalMetadata } from '../api';

export function LegalLinks({
  legal,
  className = '',
}: {
  legal: LegalMetadata;
  className?: string;
}) {
  return (
    <nav className={`legal-links ${className}`.trim()} aria-label="Legal documents">
      <a href={legal.termsUrl} target="_blank" rel="noreferrer">
        Terms of Service
      </a>
      <a href={legal.privacyUrl} target="_blank" rel="noreferrer">
        Privacy Notice
      </a>
    </nav>
  );
}
