import { and, eq } from 'drizzle-orm';
import {
  CURRENT_LEGAL_BUNDLE_SHA256,
  CURRENT_TERMS_VERSION,
  legalAcceptanceSchema,
  legalMetadata,
  type LegalStatus,
} from '../shared/legal.js';
import type { Config } from './config.js';
import type { Database } from './database.js';
import { legalAcceptances } from './schema.js';

export const TERMS_ACCEPTANCE_REQUIRED = 'TERMS_ACCEPTANCE_REQUIRED';

export class LegalVersionMismatchError extends Error {
  constructor() {
    super('Review and accept the current Terms of Service to continue.');
    this.name = 'LegalVersionMismatchError';
  }
}

export function createLegal(db: Database, config: Config) {
  const legal = legalMetadata(config.origin);

  async function status(userId: string): Promise<LegalStatus> {
    const [acceptance] = await db
      .select({
        acceptedAt: legalAcceptances.acceptedAt,
        recordingLawAcknowledgedAt: legalAcceptances.recordingLawAcknowledgedAt,
      })
      .from(legalAcceptances)
      .where(
        and(
          eq(legalAcceptances.userId, userId),
          eq(legalAcceptances.termsVersion, CURRENT_TERMS_VERSION),
          eq(legalAcceptances.legalBundleSha256, CURRENT_LEGAL_BUNDLE_SHA256),
        ),
      )
      .limit(1);

    return {
      accepted: Boolean(acceptance),
      acceptedAt: acceptance?.acceptedAt.toISOString() ?? null,
      recordingLawAcknowledgedAt: acceptance?.recordingLawAcknowledgedAt.toISOString() ?? null,
      legal,
    };
  }

  async function accept(userId: string, input: unknown): Promise<LegalStatus> {
    const submittedVersion =
      typeof input === 'object' && input !== null && 'termsVersion' in input
        ? (input as { termsVersion?: unknown }).termsVersion
        : undefined;
    if (typeof submittedVersion === 'string' && submittedVersion !== CURRENT_TERMS_VERSION)
      throw new LegalVersionMismatchError();
    const accepted = legalAcceptanceSchema.parse(input);
    const now = new Date();
    await db
      .insert(legalAcceptances)
      .values({
        userId,
        termsVersion: accepted.termsVersion,
        acceptedAt: now,
        recordingLawAcknowledgedAt: now,
        legalBundleSha256: CURRENT_LEGAL_BUNDLE_SHA256,
      })
      .onConflictDoNothing({
        target: [legalAcceptances.userId, legalAcceptances.termsVersion],
      });
    return status(userId);
  }

  return { metadata: legal, status, accept };
}
