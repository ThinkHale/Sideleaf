import { z } from 'zod';

export const captureStartSchema = z
  .object({
    pageId: z.string().uuid(),
    sdp: z.string().min(10).max(100000),
    consent: z.literal(true),
  })
  .strict();

export const captureStopSchema = z
  .object({
    reason: z.enum(['paused', 'stopped', 'interrupted']),
  })
  .strict();

export type CaptureStopReason = z.infer<typeof captureStopSchema>['reason'];
export type CaptureSession = {
  id: string;
  sdp: string;
  expiresAt: string;
  maxSeconds: number;
  heartbeatSeconds: number;
};
export type CaptureHeartbeat = { expiresAt: string; remainingSeconds: number };
export type SavedTranscriptSegment = {
  id: string;
  sessionId: string;
  itemId: string;
  previousItemId: string | null;
  text: string;
  createdAt: string;
};
export type CaptureSessionSummary = {
  id: string;
  state: string;
  startedAt: string;
  endedAt: string | null;
};
export type CapturePageResult = {
  segments: SavedTranscriptSegment[];
  sessions: CaptureSessionSummary[];
  usage?: unknown;
};
