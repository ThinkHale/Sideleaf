import { createAuthClient } from 'better-auth/react';
import {
  CURRENT_TERMS_VERSION,
  PRIVACY_PATH,
  RECORDING_LAW_ACKNOWLEDGEMENT,
  TERMS_EFFECTIVE_AT,
  TERMS_PATH,
  type LegalMetadata,
  type LegalStatus,
} from '../shared/legal';

export const authClient = createAuthClient();
export type { LegalMetadata, LegalStatus } from '../shared/legal';
export const LEGAL_ACCEPTANCE_REQUIRED_EVENT = 'sideleaf:legal-acceptance-required';
export const DEFAULT_LEGAL_METADATA: LegalMetadata = {
  termsVersion: CURRENT_TERMS_VERSION,
  effectiveAt: TERMS_EFFECTIVE_AT,
  termsUrl: TERMS_PATH,
  privacyUrl: PRIVACY_PATH,
  recordingLawAcknowledgement: RECORDING_LAW_ACKNOWLEDGEMENT,
};
export type ProductConfig = {
  name: string;
  development: boolean;
  passwordAuth: boolean;
  googleAuth: boolean;
  freeMinutes: number;
  meetingMinutes: number;
  price: number;
  capture: { ready: boolean; reason: string };
  legal: LegalMetadata;
};
export class ApiError extends Error {
  constructor(
    public status: number,
    public data: Record<string, unknown>,
  ) {
    super(String(data.error || 'Request failed'));
  }
}
function legalMetadataFromPayload(data: Record<string, unknown>): LegalMetadata | null {
  const legal = data.legal;
  if (
    !legal ||
    typeof legal !== 'object' ||
    !['termsVersion', 'effectiveAt', 'termsUrl', 'privacyUrl', 'recordingLawAcknowledgement'].every(
      (key) => typeof (legal as Record<string, unknown>)[key] === 'string',
    )
  )
    return null;
  return legal as LegalMetadata;
}
export function legalMetadataFromAcceptanceError(error: unknown): LegalMetadata | null {
  if (
    !(error instanceof ApiError) ||
    error.status !== 428 ||
    error.data.code !== 'TERMS_ACCEPTANCE_REQUIRED'
  )
    return null;
  return legalMetadataFromPayload(error.data);
}
export function notifyIfLegalAcceptanceRequired(status: number, data: Record<string, unknown>) {
  if (status !== 428 || data.code !== 'TERMS_ACCEPTANCE_REQUIRED' || typeof window === 'undefined')
    return;
  const legal = legalMetadataFromPayload(data);
  if (!legal) return;
  window.dispatchEvent(
    new CustomEvent<LegalMetadata>(LEGAL_ACCEPTANCE_REQUIRED_EVENT, {
      detail: legal,
    }),
  );
}
export function offlineProductConfig(config: ProductConfig | null = null): ProductConfig {
  const available =
    config ??
    ({
      name: 'Sideleaf',
      development: true,
      passwordAuth: true,
      googleAuth: false,
      freeMinutes: 120,
      meetingMinutes: 60,
      price: 29,
      legal: DEFAULT_LEGAL_METADATA,
    } satisfies Omit<ProductConfig, 'capture'>);
  return {
    ...available,
    capture: { ready: false, reason: 'Offline. Live capture is unavailable.' },
  };
}
export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`/api${path}`, {
    signal: AbortSignal.timeout(15000),
    ...options,
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', ...options.headers },
  });
  const data = await response.json();
  if (!response.ok) {
    notifyIfLegalAcceptanceRequired(response.status, data);
    throw new ApiError(response.status, data);
  }
  return data as T;
}
export function acceptLegalTerms(termsVersion: string) {
  return api<LegalStatus>('/legal/acceptance', {
    method: 'POST',
    body: JSON.stringify({
      termsVersion,
      acceptedTerms: true,
      recordingLawAcknowledged: true,
    }),
  });
}
export function download(content: string, name: string, type = 'text/markdown') {
  // Only text notebook artifacts. Audio is never accepted by this function.
  const url = URL.createObjectURL(new Blob([content], { type }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
