import { describe, expect, it } from 'vitest';
import { emptyDocument, newBlock, documentSchema } from '../shared/domain';
import { makeAnchor, remapAnchor, isLasso, pointInPolygon } from '../shared/anchors';
import { groundedItemSchema, transcriptEventSchema } from '../shared/providers';
import { exportMarkdown } from '../shared/export';

describe('semantic anchoring', () => {
  it('uses UTF-16 offsets shared with DOM and NSString', () => {
    const b = newBlock('😀 A clear next step');
    const a = makeAnchor(b, 5, 10);
    expect(a.quote).toBe('clear');
  });
  it('remaps an unchanged quote and context after an insertion farther away', () => {
    const b = newBlock('A'.repeat(50) + ' clarify the deadline tomorrow ' + 'B'.repeat(50));
    const start = b.text.indexOf('deadline');
    const a = makeAnchor(b, start, start + 8);
    const next = remapAnchor(a, { ...b, text: 'Preface ' + b.text, revision: 2 });
    expect(next.resolved).toBe(true);
    expect(next.start).toBe(start + 8);
    expect(next.revision).toBe(2);
  });
  it('preserves original quote and refuses unrelated replacement', () => {
    const b = newBlock('Deadline is Friday.');
    const a = makeAnchor(b, 12, 18);
    const next = remapAnchor(a, { ...b, text: 'Deadline is Monday.', revision: 2 });
    expect(next.resolved).toBe(false);
    expect(next.quote).toBe('Friday');
  });
  it('refuses ambiguous duplicate context', () => {
    const b = newBlock('hello');
    const a = { ...makeAnchor(b, 0, 5), prefix: '', suffix: '' };
    expect(remapAnchor(a, { ...b, text: 'hello hello', revision: 2 }).resolved).toBe(false);
  });
  it('does not retarget a missing block', () => {
    const b = newBlock('A quote');
    expect(remapAnchor(makeAnchor(b, 0, 1), undefined).resolved).toBe(false);
  });
});
describe('lasso geometry', () => {
  const polygon = [
    { x: 0, y: 0 },
    { x: 50, y: 0 },
    { x: 100, y: 0 },
    { x: 100, y: 50 },
    { x: 50, y: 50 },
    { x: 0, y: 50 },
    { x: 0, y: 0 },
  ];
  it('distinguishes inside, outside, and an open stroke', () => {
    expect(pointInPolygon({ x: 25, y: 20 }, polygon)).toBe(true);
    expect(pointInPolygon({ x: 101, y: 20 }, polygon)).toBe(false);
    expect(isLasso(polygon)).toBe(true);
    expect(isLasso(polygon.slice(0, 5))).toBe(false);
  });
  it('is invariant under scroll and scale transforms', () => {
    const shifted = polygon.map((p) => ({ x: p.x * 2 + 320, y: p.y * 2 - 90 }));
    expect(pointInPolygon({ x: 370, y: -50 }, shifted)).toBe(true);
  });
});
describe('data and provenance validation', () => {
  it('rejects audio and unknown payload fields', () => {
    expect(documentSchema.safeParse({ ...emptyDocument(), audio: 'payload' }).success).toBe(false);
  });
  it('rejects duplicate block identity', () => {
    const d = emptyDocument();
    d.blocks.push(d.blocks[0]);
    expect(documentSchema.safeParse(d).success).toBe(false);
  });
  it('requires exact quote/revision for resolved marks', () => {
    const d = emptyDocument();
    d.blocks[1].text = 'Original';
    d.annotations.push({
      id: crypto.randomUUID(),
      kind: 'important',
      anchor: { ...makeAnchor(d.blocks[1], 0, 8), quote: 'Different' },
      question: '',
      state: 'open',
      createdAt: new Date().toISOString(),
    });
    expect(documentSchema.safeParse(d).success).toBe(false);
  });
  it('requires evidence and explicit uncertainty for AI facts', () => {
    expect(
      groundedItemSchema.safeParse({
        text: 'Agreed',
        sources: [],
        certainty: 'stated',
        owner: null,
        deadline: null,
      }).success,
    ).toBe(false);
    expect(transcriptEventSchema.safeParse({ text: 'fake transcript' }).success).toBe(false);
  });
  it('excludes private text and marks without deleting source', () => {
    const d = emptyDocument();
    d.blocks[1].text = 'Private detail';
    d.blocks[1].excluded = true;
    d.annotations.push({
      id: crypto.randomUUID(),
      kind: 'important',
      anchor: makeAnchor(d.blocks[1], 0, 14),
      question: '',
      state: 'open',
      createdAt: new Date().toISOString(),
    });
    const p = {
      id: crypto.randomUUID(),
      notebookId: crypto.randomUUID(),
      title: 'Meeting',
      document: d,
      version: 1,
      updatedAt: new Date().toISOString(),
    };
    expect(exportMarkdown(p)).not.toContain('Private detail');
    expect(exportMarkdown(p, true)).toContain('Private detail');
    expect(p.document.blocks[1].text).toBe('Private detail');
  });
});
