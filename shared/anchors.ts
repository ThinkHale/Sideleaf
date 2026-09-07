import type { Anchor, Block, Point } from './domain.js';

// Offsets are UTF-16 code units, matching DOM Range and NSString.
export function makeAnchor(block: Block, start: number, end: number): Anchor {
  if (start < 0 || end > block.text.length || end <= start) throw new Error('Invalid selection');
  return {
    blockId: block.id,
    revision: block.revision,
    start,
    end,
    quote: block.text.slice(start, end),
    prefix: block.text.slice(Math.max(0, start - 32), start),
    suffix: block.text.slice(end, end + 32),
    resolved: true,
  };
}

// Only a unique exact quote with matching surrounding context can move.
// Never replace the retained original quote with unrelated corrected text.
export function remapAnchor(anchor: Anchor, block: Block | undefined): Anchor {
  if (!block || block.id !== anchor.blockId) return { ...anchor, resolved: false };
  if (
    block.revision === anchor.revision &&
    block.text.slice(anchor.start, anchor.end) === anchor.quote
  )
    return { ...anchor, resolved: true };
  const candidates: number[] = [];
  let index = block.text.indexOf(anchor.quote);
  while (index !== -1) {
    const before = block.text.slice(Math.max(0, index - anchor.prefix.length), index);
    const after = block.text.slice(
      index + anchor.quote.length,
      index + anchor.quote.length + anchor.suffix.length,
    );
    if (before === anchor.prefix && after === anchor.suffix) candidates.push(index);
    index = block.text.indexOf(anchor.quote, index + 1);
  }
  if (candidates.length !== 1) return { ...anchor, resolved: false };
  return {
    ...anchor,
    start: candidates[0],
    end: candidates[0] + anchor.quote.length,
    revision: block.revision,
    resolved: true,
  };
}

export function pointInPolygon(
  point: Pick<Point, 'x' | 'y'>,
  polygon: Pick<Point, 'x' | 'y'>[],
): boolean {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const a = polygon[i],
      b = polygon[j];
    if (
      a.y > point.y !== b.y > point.y &&
      point.x < ((b.x - a.x) * (point.y - a.y)) / (b.y - a.y) + a.x
    )
      inside = !inside;
  }
  return inside;
}
export function isLasso(points: Pick<Point, 'x' | 'y'>[]): boolean {
  if (points.length < 6) return false;
  const xs = points.map((p) => p.x),
    ys = points.map((p) => p.y);
  const width = Math.max(...xs) - Math.min(...xs),
    height = Math.max(...ys) - Math.min(...ys);
  const distance = Math.hypot(points[0].x - points.at(-1)!.x, points[0].y - points.at(-1)!.y);
  return width >= 12 && height >= 10 && distance <= Math.max(24, Math.min(width, height) * 0.6);
}
export function visibleWords(text: string) {
  return [...text.matchAll(/\S+/gu)].map((m) => ({
    text: m[0],
    start: m.index,
    end: m.index + m[0].length,
  }));
}
