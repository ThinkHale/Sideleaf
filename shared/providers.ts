import { z } from 'zod';
import type { CaptureState } from './domain';

// Contracts for future provider adapters. No implementation is selected implicitly.
export const transcriptEventSchema = z
  .object({
    id: z.string().uuid(),
    sessionId: z.string().uuid(),
    sequence: z.number().int().nonnegative(),
    revision: z.number().int().positive(),
    text: z.string().max(20000),
    startMs: z.number().nonnegative(),
    endMs: z.number().nonnegative(),
    final: z.boolean(),
    speaker: z.string().nullable(),
  })
  .strict();
export const sourceRefSchema = z
  .object({
    blockId: z.string().uuid(),
    revision: z.number().int().positive(),
    quote: z.string().min(1),
  })
  .strict();
export const groundedItemSchema = z
  .object({
    text: z.string().min(1).max(2000),
    sources: z.array(sourceRefSchema).min(1),
    certainty: z.enum(['stated', 'uncertain', 'suggested']),
    owner: z.string().nullable(),
    deadline: z.string().nullable(),
  })
  .strict();
export interface TranscriptionAdapter {
  readiness(): Promise<{ ready: boolean; reason?: string }>;
  start(
    onText: (event: z.infer<typeof transcriptEventSchema>) => Promise<void>,
    onState: (state: CaptureState) => void,
  ): Promise<void>;
  push(frame: Int16Array): void;
  pause(): Promise<void>;
  end(): Promise<void>;
}
