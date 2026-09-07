import { Fragment, useEffect, useRef, useState } from 'react';
import type { PointerEvent, RefObject } from 'react';
import type { Point, Stroke } from '../../shared/domain';
import { isLasso, pointInPolygon } from '../../shared/anchors';
export type Tool = 'type' | 'write' | 'mark' | 'select' | 'erase';
export function InkLayer({
  tool,
  strokes,
  onChange,
  onLasso,
  container,
}: {
  tool: Tool;
  strokes: Stroke[];
  onChange: (s: Stroke[]) => void;
  onLasso: (points: Point[]) => void;
  container: RefObject<HTMLDivElement | null>;
}) {
  const ref = useRef<SVGSVGElement>(null),
    points = useRef<Point[]>([]),
    pointer = useRef<number | null>(null);
  const [preview, setPreview] = useState<Point[]>([]);
  const [width, setWidth] = useState(800);
  const [selectedInk, setSelectedInk] = useState<string | null>(null);
  const drag = useRef<{ id: string; origin: Point; original: Point[] } | null>(null);
  const [moved, setMoved] = useState<{ id: string; points: Point[] } | null>(null);
  function translated(original: Point[], dx: number, dy: number) {
    const bounds = original.reduce(
      (b, p) => ({
        minX: Math.min(b.minX, p.x),
        maxX: Math.max(b.maxX, p.x),
        minY: Math.min(b.minY, p.y),
        maxY: Math.max(b.maxY, p.y),
      }),
      { minX: 800, maxX: 0, minY: 20000, maxY: 0 },
    );
    dx = Math.max(-bounds.minX, Math.min(800 - bounds.maxX, dx));
    dy = Math.max(-bounds.minY, Math.min(20000 - bounds.maxY, dy));
    return original.map((p) => ({ ...p, x: p.x + dx, y: p.y + dy }));
  }
  useEffect(() => {
    const element = container.current;
    if (!element) return;
    const observer = new ResizeObserver((entries) => setWidth(entries[0].contentRect.width));
    observer.observe(element);
    return () => observer.disconnect();
  }, [container]);
  const coordinate = (e: Pick<PointerEvent, 'clientX' | 'clientY' | 'pressure'>): Point => {
    const r = ref.current!.getBoundingClientRect();
    return {
      x: Math.max(0, Math.min(800, ((e.clientX - r.left) * 800) / r.width)),
      y: Math.max(0, Math.min(20000, ((e.clientY - r.top) * 800) / r.width)),
      pressure: e.pressure || 0.5,
    };
  };
  const active = tool === 'write' || tool === 'mark' || tool === 'erase';
  const path = (p: Point[]) =>
    p.map((q, i) => `${i ? 'L' : 'M'}${q.x.toFixed(2)} ${q.y.toFixed(2)}`).join(' ');
  return (
    <svg
      ref={ref}
      role="group"
      className={`ink-layer ${active ? 'active' : ''}`}
      aria-label={tool === 'mark' ? 'Circle text to mark it important' : 'Drawing canvas'}
      style={{ touchAction: active ? 'none' : 'auto' }}
      onPointerDown={(e) => {
        if (!active || !e.isPrimary || e.button !== 0) return;
        pointer.current = e.pointerId;
        e.currentTarget.setPointerCapture(e.pointerId);
        points.current = [coordinate(e)];
        setPreview(points.current);
      }}
      onPointerMove={(e) => {
        if (pointer.current !== e.pointerId) return;
        if (points.current.length >= 10000) return;
        points.current = [...points.current, coordinate(e)];
        setPreview(points.current);
      }}
      onPointerUp={(e) => {
        if (pointer.current !== e.pointerId) return;
        const captured = [...points.current, coordinate(e)];
        pointer.current = null;
        points.current = [];
        setPreview([]);
        if (tool === 'mark') {
          if (isLasso(captured)) {
            const r = ref.current!.getBoundingClientRect();
            onLasso(
              captured.map((p) => ({
                ...p,
                x: r.left + (p.x * r.width) / 800,
                y: r.top + (p.y * r.width) / 800,
              })),
            );
          }
          return;
        }
        if (tool === 'erase') {
          onChange(
            strokes.filter(
              (s) =>
                !s.points.some(
                  (p) =>
                    captured.some((c) => Math.hypot(c.x - p.x, c.y - p.y) < 14) ||
                    (isLasso(captured) && pointInPolygon(p, captured)),
                ),
            ),
          );
          return;
        }
        if (tool === 'write')
          onChange([
            ...strokes,
            { id: crypto.randomUUID(), points: captured, color: '#30372f', width: 2.2 },
          ]);
      }}
      onPointerCancel={() => {
        pointer.current = null;
        points.current = [];
        setPreview([]);
      }}
    >
      <g transform={`scale(${width / 800})`}>
        {strokes.map((s, index) => (
          <Fragment key={s.id}>
            <path
              d={path(moved?.id === s.id ? moved.points : s.points)}
              stroke={tool === 'select' && selectedInk === s.id ? '#687354' : s.color}
              strokeWidth={s.width}
              strokeLinecap="round"
              strokeLinejoin="round"
              fill="none"
            />
            {tool === 'select' && (
              <path
                d={path(moved?.id === s.id ? moved.points : s.points)}
                data-stroke-id={s.id}
                role="button"
                aria-label={`Ink stroke ${index + 1}`}
                tabIndex={0}
                fill="none"
                stroke="transparent"
                strokeWidth={18}
                style={{ pointerEvents: 'stroke', cursor: 'move', touchAction: 'none' }}
                onPointerDown={(e) => {
                  e.stopPropagation();
                  if (!e.isPrimary || e.button !== 0) return;
                  setSelectedInk(s.id);
                  e.currentTarget.focus();
                  e.currentTarget.setPointerCapture(e.pointerId);
                  drag.current = { id: s.id, origin: coordinate(e), original: s.points };
                }}
                onPointerMove={(e) => {
                  if (drag.current?.id !== s.id) return;
                  e.stopPropagation();
                  const p = coordinate(e);
                  setMoved({
                    id: s.id,
                    points: translated(
                      drag.current.original,
                      p.x - drag.current.origin.x,
                      p.y - drag.current.origin.y,
                    ),
                  });
                }}
                onPointerUp={(e) => {
                  if (drag.current?.id !== s.id) return;
                  e.stopPropagation();
                  const p = coordinate(e);
                  const dx = p.x - drag.current.origin.x,
                    dy = p.y - drag.current.origin.y;
                  const shifted = translated(drag.current.original, dx, dy);
                  drag.current = null;
                  setMoved(null);
                  if (dx || dy)
                    onChange(
                      strokes.map((stroke) =>
                        stroke.id === s.id ? { ...stroke, points: shifted } : stroke,
                      ),
                    );
                }}
                onPointerCancel={() => {
                  drag.current = null;
                  setMoved(null);
                }}
                onKeyDown={(e) => {
                  if (['Delete', 'Backspace'].includes(e.key)) {
                    e.preventDefault();
                    onChange(strokes.filter((stroke) => stroke.id !== s.id));
                    setSelectedInk(null);
                  } else if (e.key.startsWith('Arrow')) {
                    e.preventDefault();
                    const step = e.shiftKey ? 10 : 1;
                    const dx = e.key === 'ArrowLeft' ? -step : e.key === 'ArrowRight' ? step : 0;
                    const dy = e.key === 'ArrowUp' ? -step : e.key === 'ArrowDown' ? step : 0;
                    setSelectedInk(s.id);
                    onChange(
                      strokes.map((stroke) =>
                        stroke.id === s.id
                          ? { ...stroke, points: translated(stroke.points, dx, dy) }
                          : stroke,
                      ),
                    );
                  }
                }}
              />
            )}
          </Fragment>
        ))}
        {preview.length > 0 && (
          <path
            d={path(preview)}
            stroke={tool === 'mark' ? '#687354' : tool === 'erase' ? '#a95748' : '#30372f'}
            strokeWidth={tool === 'erase' ? 16 : 2.2}
            opacity={tool === 'erase' ? 0.25 : 1}
            strokeDasharray={tool === 'mark' ? '5 4' : undefined}
            strokeLinecap="round"
            fill="none"
          />
        )}
      </g>
    </svg>
  );
}
