import { z } from 'zod';

export const pointSchema = z
  .object({
    x: z.number().finite().min(0).max(10000),
    y: z.number().finite().min(0).max(20000),
    pressure: z.number().min(0).max(1).default(0.5),
  })
  .strict();
export const strokeSchema = z
  .object({
    id: z.string().uuid(),
    points: z.array(pointSchema).min(1).max(10000),
    color: z.enum(['#30372f', '#687354']),
    width: z.number().min(1).max(12),
  })
  .strict();
export const blockSchema = z
  .object({
    id: z.string().uuid(),
    text: z.string().max(30000),
    kind: z.enum(['heading', 'paragraph']),
    source: z.enum(['personal', 'transcript', 'ai']),
    revision: z.number().int().min(1),
    excluded: z.boolean().default(false),
  })
  .strict();
export const anchorSchema = z
  .object({
    blockId: z.string().uuid(),
    revision: z.number().int().min(1),
    start: z.number().int().min(0),
    end: z.number().int().min(1),
    quote: z.string().min(1).max(30000),
    prefix: z.string().max(32),
    suffix: z.string().max(32),
    resolved: z.boolean(),
  })
  .strict()
  .refine((a) => a.end > a.start, 'Invalid text range');
export const annotationSchema = z
  .object({
    id: z.string().uuid(),
    kind: z.enum(['important', 'follow-up', 'action']),
    anchor: anchorSchema,
    question: z.string().max(2000),
    state: z.enum(['open', 'addressed', 'dismissed', 'later']),
    createdAt: z.string().datetime(),
  })
  .strict();
export const preparationSchema = z
  .object({
    type: z.enum(['General', 'Client meeting', 'Training', 'Discovery']),
    participants: z.string().max(2000),
    context: z.string().max(5000),
    outcome: z.string().max(5000),
    agenda: z.string().max(5000),
    questions: z.string().max(5000),
    concerns: z.string().max(5000),
    background: z.string().max(10000),
    references: z.string().max(20000),
  })
  .strict();
export const documentSchema = z
  .object({
    schemaVersion: z.literal(1),
    blocks: z.array(blockSchema).max(300),
    ink: z.array(strokeSchema).max(1000),
    annotations: z.array(annotationSchema).max(1000),
    preparation: preparationSchema,
    meetingState: z.enum(['notes', 'prepared']),
  })
  .strict()
  .superRefine((doc, ctx) => {
    for (const [key, items] of [
      ['blocks', doc.blocks],
      ['ink', doc.ink],
      ['annotations', doc.annotations],
    ] as const) {
      if (new Set(items.map((i) => i.id)).size !== items.length)
        ctx.addIssue({ code: 'custom', path: [key], message: 'Duplicate identifiers' });
    }
    for (const a of doc.annotations) {
      if (!a.anchor.resolved) continue;
      const block = doc.blocks.find((b) => b.id === a.anchor.blockId);
      if (
        !block ||
        block.revision !== a.anchor.revision ||
        block.text.slice(a.anchor.start, a.anchor.end) !== a.anchor.quote
      )
        ctx.addIssue({
          code: 'custom',
          path: ['annotations'],
          message: 'Resolved annotation must match its source exactly',
        });
    }
  });
export const pageWriteSchema = z
  .object({
    title: z.string().trim().min(1).max(200),
    notebookId: z.string().uuid(),
    document: documentSchema,
    baseVersion: z.number().int().min(0),
    mutationId: z.string().uuid(),
  })
  .strict();
export type Point = z.infer<typeof pointSchema>;
export type Stroke = z.infer<typeof strokeSchema>;
export type Block = z.infer<typeof blockSchema>;
export type Anchor = z.infer<typeof anchorSchema>;
export type Annotation = z.infer<typeof annotationSchema>;
export type Preparation = z.infer<typeof preparationSchema>;
export type NotebookDocument = z.infer<typeof documentSchema>;
export type Page = {
  id: string;
  notebookId: string;
  title: string;
  document: NotebookDocument;
  version: number;
  updatedAt: string;
};
export type Notebook = { id: string; name: string; color: string };
export type CaptureState =
  'ready' | 'connecting' | 'listening' | 'paused' | 'interrupted' | 'finalizing' | 'complete';
export const emptyPreparation = (): Preparation => ({
  type: 'General',
  participants: '',
  context: '',
  outcome: '',
  agenda: '',
  questions: '',
  concerns: '',
  background: '',
  references: '',
});
export const newBlock = (text = '', kind: Block['kind'] = 'paragraph'): Block => ({
  id: crypto.randomUUID(),
  text,
  kind,
  source: 'personal',
  revision: 1,
  excluded: false,
});
export const emptyDocument = (): NotebookDocument => ({
  schemaVersion: 1,
  blocks: [newBlock('Notes', 'heading'), newBlock()],
  ink: [],
  annotations: [],
  preparation: emptyPreparation(),
  meetingState: 'notes',
});
export const templates: Record<Preparation['type'], Partial<Preparation>> = {
  General: {
    outcome: 'Leave with a shared understanding and a clear next step.',
    agenda: 'Context\nDiscussion\nNext steps',
    questions: 'What would make this conversation useful?',
  },
  'Client meeting': {
    outcome: 'Understand the priorities and agree on a useful next step.',
    agenda: 'Current situation\nPriorities and constraints\nNext steps',
    questions: 'What matters most right now?\nWho else should be involved?',
  },
  Training: {
    outcome: 'Understand the process and be able to apply it.',
    agenda: 'Learning goals\nExplanation and examples\nPractice\nQuestions',
    questions: 'Can you walk through an example?\nWhat should I try next?',
  },
  Discovery: {
    outcome: 'Understand the problem before proposing a solution.',
    agenda: 'Background\nCurrent process\nFriction and opportunities',
    questions: 'What happens today?\nWhere does the process become difficult?',
  },
};
