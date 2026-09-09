import { afterEach, describe, expect, it, vi } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  ApiError,
  LEGAL_ACCEPTANCE_REQUIRED_EVENT,
  legalMetadataFromAcceptanceError,
  notifyIfLegalAcceptanceRequired,
  offlineProductConfig,
  type ProductConfig,
} from '../src/api';
import { LegalControls } from '../src/components/LegalControls';
import { LegalLinks } from '../src/components/LegalLinks';
import { CURRENT_TERMS_VERSION, legalMetadata } from '../shared/legal';

afterEach(() => vi.unstubAllGlobals());

describe('browser legal-version transition', () => {
  it('announces a current-terms gate from the server contract', () => {
    const events = new EventTarget();
    vi.stubGlobal('window', events);
    let received: unknown;
    events.addEventListener(LEGAL_ACCEPTANCE_REQUIRED_EVENT, (event) => {
      received = (event as CustomEvent).detail;
    });
    const legal = legalMetadata('https://sideleaf.example');

    notifyIfLegalAcceptanceRequired(428, {
      code: 'TERMS_ACCEPTANCE_REQUIRED',
      legal,
    });

    expect(received).toEqual(legal);
    expect((received as { termsVersion: string }).termsVersion).toBe(CURRENT_TERMS_VERSION);
  });

  it('ignores unrelated and malformed errors', () => {
    const events = new EventTarget();
    vi.stubGlobal('window', events);
    let count = 0;
    events.addEventListener(LEGAL_ACCEPTANCE_REQUIRED_EVENT, () => count++);

    notifyIfLegalAcceptanceRequired(403, {
      code: 'TERMS_ACCEPTANCE_REQUIRED',
      legal: legalMetadata('https://sideleaf.example'),
    });
    notifyIfLegalAcceptanceRequired(428, {
      code: 'TERMS_ACCEPTANCE_REQUIRED',
      legal: { termsVersion: CURRENT_TERMS_VERSION },
    });

    expect(count).toBe(0);
  });

  it('extracts current metadata only from a valid terms-required API error', () => {
    const legal = legalMetadata('https://sideleaf.example');
    expect(
      legalMetadataFromAcceptanceError(
        new ApiError(428, { code: 'TERMS_ACCEPTANCE_REQUIRED', legal }),
      ),
    ).toEqual(legal);
    expect(
      legalMetadataFromAcceptanceError(
        new ApiError(428, {
          code: 'TERMS_ACCEPTANCE_REQUIRED',
          legal: { termsVersion: CURRENT_TERMS_VERSION },
        }),
      ),
    ).toBeNull();
    expect(
      legalMetadataFromAcceptanceError(
        new ApiError(403, { code: 'TERMS_ACCEPTANCE_REQUIRED', legal }),
      ),
    ).toBeNull();
  });

  it('keeps newer fetched legal metadata when degrading the config offline', () => {
    const newerLegal = {
      ...legalMetadata('https://sideleaf.example'),
      termsVersion: '2026-10-01.1',
      effectiveAt: '2026-10-01',
    };
    const fetched: ProductConfig = {
      name: 'Fetched Sideleaf',
      development: false,
      passwordAuth: false,
      googleAuth: true,
      freeMinutes: 45,
      meetingMinutes: 30,
      price: 19,
      capture: { ready: true, reason: 'Ready' },
      legal: newerLegal,
    };

    expect(offlineProductConfig(fetched)).toEqual({
      ...fetched,
      capture: { ready: false, reason: 'Offline. Live capture is unavailable.' },
    });
  });

  it('renders the accepted version, effective date, and durable legal document links', () => {
    const legal = legalMetadata('https://sideleaf.example');
    const controls = renderToStaticMarkup(
      createElement(LegalControls, {
        legal,
        termsAccepted: false,
        recordingLawAcknowledged: false,
        onTermsAccepted: () => undefined,
        onRecordingLawAcknowledged: () => undefined,
      }),
    );
    const links = renderToStaticMarkup(createElement(LegalLinks, { legal }));

    expect(controls).toContain(`Terms version <strong>${legal.termsVersion}</strong>`);
    expect(controls).toContain(`<time dateTime="${legal.effectiveAt}">${legal.effectiveAt}</time>`);
    expect(links).toContain(`href="${legal.termsUrl}"`);
    expect(links).toContain(`href="${legal.privacyUrl}"`);
  });
});
