import { useCallback, useEffect, useRef, useState } from 'react';
import {
  Type,
  PenLine,
  Highlighter,
  Scan,
  Eraser,
  Undo2,
  Redo2,
  Plus,
  Flag,
  Star,
  ListTodo,
  EyeOff,
  Trash2,
} from 'lucide-react';
import type { NotebookDocument, Page, Anchor, Point, Block, Annotation } from '../../shared/domain';
import { newBlock } from '../../shared/domain';
import { makeAnchor, pointInPolygon, remapAnchor, visibleWords } from '../../shared/anchors';
import { InkLayer, type Tool } from './InkLayer';

export function Editor({
  page,
  onChange,
  onDelete,
}: {
  page: Page;
  onChange: (p: Page) => void;
  onDelete: () => void;
}) {
  const [tool, setTool] = useState<Tool>('type'),
    [selection, setSelection] = useState<Anchor | null>(null),
    [notice, setNotice] = useState('');
  const surface = useRef<HTMLDivElement>(null),
    undo = useRef<NotebookDocument[]>([]),
    redo = useRef<NotebookDocument[]>([]),
    lastTyping = useRef(0);
  const doc = page.document;
  function change(next: NotebookDocument, typing = false) {
    if (!typing || Date.now() - lastTyping.current > 700) {
      undo.current.push(doc);
      if (undo.current.length > 80) undo.current.shift();
    }
    lastTyping.current = typing ? Date.now() : 0;
    redo.current = [];
    onChange({ ...page, document: next });
  }
  function history(direction: 'undo' | 'redo') {
    const from = direction === 'undo' ? undo : redo,
      to = direction === 'undo' ? redo : undo;
    const next = from.current.pop();
    if (next) {
      to.current.push(doc);
      onChange({ ...page, document: next });
      setSelection(null);
    }
  }
  function editBlock(block: Block, text: string) {
    const replacement = { ...block, text, revision: block.revision + 1 };
    change(
      {
        ...doc,
        blocks: doc.blocks.map((b) => (b.id === block.id ? replacement : b)),
        annotations: doc.annotations.map((a) =>
          a.anchor.blockId === block.id ? { ...a, anchor: remapAnchor(a.anchor, replacement) } : a,
        ),
      },
      true,
    );
  }
  function mark(kind: Annotation['kind'], anchors = selection ? [selection] : []) {
    const fresh = anchors.filter(
      (a) =>
        !doc.annotations.some(
          (m) =>
            m.kind === kind &&
            m.anchor.blockId === a.blockId &&
            m.anchor.start === a.start &&
            m.anchor.end === a.end &&
            m.anchor.resolved,
        ),
    );
    change({
      ...doc,
      annotations: [
        ...doc.annotations,
        ...fresh.map((anchor) => ({
          id: crypto.randomUUID(),
          kind,
          anchor,
          question:
            kind === 'follow-up'
              ? `What should we clarify about "${anchor.quote}"?`
              : kind === 'action'
                ? `Draft: ${anchor.quote}`
                : '',
          state: 'open' as const,
          createdAt: new Date().toISOString(),
        })),
      ],
    });
    setSelection(null);
    window.getSelection()?.removeAllRanges();
    setNotice(
      `${fresh.length} ${kind === 'important' ? 'important mark' : kind === 'follow-up' ? 'follow-up' : 'action draft'}${fresh.length === 1 ? '' : 's'} added.`,
    );
  }
  function readSelection() {
    if (tool !== 'select') return;
    const s = window.getSelection();
    if (!s || s.isCollapsed || !s.rangeCount) return;
    const r = s.getRangeAt(0),
      element = r.startContainer.parentElement?.closest('[data-block]') as HTMLElement | null;
    if (!element || !element.contains(r.endContainer)) return;
    const block = doc.blocks.find((b) => b.id === element.dataset.block);
    if (!block) return;
    const before = r.cloneRange();
    before.selectNodeContents(element);
    before.setEnd(r.startContainer, r.startOffset);
    const start = before.toString().length,
      end = start + r.toString().length;
    if (end > start && end <= block.text.length) setSelection(makeAnchor(block, start, end));
  }
  function lasso(points: Point[]) {
    const anchors: Anchor[] = [];
    for (const block of doc.blocks) {
      const spans = [
        ...(surface.current?.querySelectorAll<HTMLElement>(
          `[data-block="${block.id}"] [data-start]`,
        ) || []),
      ];
      let run: { start: number; end: number } | null = null;
      for (const span of spans) {
        const hit = [...span.getClientRects()].some((r) =>
          pointInPolygon({ x: r.x + r.width / 2, y: r.y + r.height / 2 }, points),
        );
        if (hit) {
          const start = Number(span.dataset.start),
            end = Number(span.dataset.end);
          if (run) run.end = end;
          else run = { start, end };
        } else if (run) {
          anchors.push(makeAnchor(block, run.start, run.end));
          run = null;
        }
      }
      if (run) anchors.push(makeAnchor(block, run.start, run.end));
    }
    if (anchors.length) mark('important', anchors);
    else setNotice('No words enclosed. Circle the center of the words you want to mark.');
  }
  useEffect(() => {
    if (!notice) return;
    const t = setTimeout(() => setNotice(''), 4000);
    return () => clearTimeout(t);
  }, [notice]);
  const tools = [
    { id: 'type', label: 'Type', Icon: Type },
    { id: 'write', label: 'Write', Icon: PenLine },
    { id: 'mark', label: 'Mark', Icon: Highlighter },
    { id: 'select', label: 'Select', Icon: Scan },
    { id: 'erase', label: 'Erase', Icon: Eraser },
  ] as const;
  return (
    <article
      className="paper"
      onKeyDown={(e) => {
        if (
          (e.ctrlKey || e.metaKey) &&
          e.key.toLowerCase() === 'z' &&
          !(e.target instanceof HTMLTextAreaElement || e.target instanceof HTMLInputElement)
        ) {
          e.preventDefault();
          history(e.shiftKey ? 'redo' : 'undo');
        }
      }}
    >
      <header className="page-heading">
        <TitleEditor value={page.title} onChange={(title) => onChange({ ...page, title })} />
        <div className="page-meta">
          <span>
            {new Date(page.updatedAt).toLocaleDateString(undefined, {
              month: 'long',
              day: 'numeric',
              year: 'numeric',
            })}
          </span>
          <span className="dot" />
          <span>Personal notes</span>
        </div>
      </header>
      <div className="writing-toolbar" role="toolbar" aria-label="Notebook tools">
        {tools.map(({ id, label, Icon }) => (
          <button
            key={id}
            aria-label={label}
            className={tool === id ? 'tool selected' : 'tool'}
            aria-pressed={tool === id}
            onClick={() => {
              setTool(id);
              setSelection(null);
            }}
          >
            <Icon size={19} />
            <span>{label}</span>
          </button>
        ))}
        <span className="toolbar-divider" />
        <button
          className="icon-button"
          aria-label="Undo"
          disabled={!undo.current.length}
          onClick={() => history('undo')}
        >
          <Undo2 size={19} />
        </button>
        <button
          className="icon-button"
          aria-label="Redo"
          disabled={!redo.current.length}
          onClick={() => history('redo')}
        >
          <Redo2 size={19} />
        </button>
      </div>
      <div className="tool-hint">
        {tool === 'type'
          ? 'Your space to think. Type a note, or switch to Write for ink.'
          : tool === 'write'
            ? 'Write and sketch freely. Circles in Write mode remain ordinary ink.'
            : tool === 'mark'
              ? 'Circle words to mark them important. Touch or Pencil to mark; use two-finger browser controls to zoom.'
              : tool === 'select'
                ? 'Select text for actions. Drag ink to move it, or focus a stroke and use arrow keys or Delete.'
                : 'Draw across strokes to erase ink. Text and semantic marks are preserved.'}
      </div>
      {selection && (
        <div className="selection-actions" role="group" aria-label="Selected phrase actions">
          <span title={selection.quote}>“{selection.quote}”</span>
          <button onClick={() => mark('important')}>
            <Star size={16} />
            Important
          </button>
          <button onClick={() => mark('follow-up')}>
            <Flag size={16} />
            Follow up
          </button>
          <button onClick={() => mark('action')}>
            <ListTodo size={16} />
            Action item
          </button>
          <button aria-label="Clear selection" onClick={() => setSelection(null)}>
            Cancel
          </button>
        </div>
      )}
      <div
        className="paper-writing"
        ref={surface}
        onMouseUp={readSelection}
        onKeyUp={readSelection}
      >
        <div className="blocks">
          {doc.blocks.map((block) => (
            <section
              className={`note-block ${block.kind} ${block.excluded ? 'excluded' : ''}`}
              key={block.id}
              id={`source-${block.id}`}
            >
              {tool === 'type' ? (
                <>
                  <AutoTextarea block={block} onChange={(text) => editBlock(block, text)} />
                  <div className="block-tools">
                    <button
                      className="icon-button"
                      aria-label={
                        block.excluded ? 'Include note in exports' : 'Exclude note from exports'
                      }
                      title={
                        block.excluded
                          ? 'Excluded from export, not deleted'
                          : 'Exclude from exports'
                      }
                      onClick={() =>
                        change({
                          ...doc,
                          blocks: doc.blocks.map((b) =>
                            b.id === block.id ? { ...b, excluded: !b.excluded } : b,
                          ),
                        })
                      }
                    >
                      <EyeOff size={14} />
                    </button>
                    <button
                      className="icon-button"
                      aria-label="Delete note block"
                      onClick={() =>
                        change({
                          ...doc,
                          blocks: doc.blocks.filter((b) => b.id !== block.id),
                          annotations: doc.annotations.map((a) =>
                            a.anchor.blockId === block.id
                              ? { ...a, anchor: { ...a.anchor, resolved: false } }
                              : a,
                          ),
                        })
                      }
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                </>
              ) : (
                <div
                  data-block={block.id}
                  className="block-text"
                  tabIndex={tool === 'select' ? 0 : -1}
                  onClick={(e) => {
                    if (tool !== 'select' || !window.getSelection()?.isCollapsed) return;
                    const span = (e.target as HTMLElement).closest<HTMLElement>('[data-start]');
                    if (span)
                      setSelection(
                        makeAnchor(block, Number(span.dataset.start), Number(span.dataset.end)),
                      );
                  }}
                >
                  {visibleWords(block.text).map((word, i, words) => {
                    const marked = doc.annotations.some(
                      (a) =>
                        a.anchor.resolved &&
                        a.anchor.blockId === block.id &&
                        a.anchor.start < word.end &&
                        a.anchor.end > word.start &&
                        a.state !== 'dismissed',
                    );
                    return (
                      <span key={word.start}>
                        {block.text.slice(i === 0 ? 0 : words[i - 1].end, word.start)}
                        <span
                          data-start={word.start}
                          data-end={word.end}
                          className={marked ? 'marked-word' : undefined}
                        >
                          {word.text}
                        </span>
                        {i === words.length - 1 ? block.text.slice(word.end) : ''}
                      </span>
                    );
                  })}
                  {!block.text && <span className="muted">Empty note</span>}
                </div>
              )}
              {block.excluded && (
                <small className="exclusion-label">
                  Excluded from exports. Source is still saved.
                </small>
              )}
            </section>
          ))}
        </div>
        {tool === 'type' && (
          <div className="add-block">
            <button
              className="text-button"
              onClick={() => change({ ...doc, blocks: [...doc.blocks, newBlock()] })}
            >
              <Plus size={16} />
              Add a note
            </button>
            <button
              className="text-button"
              onClick={() =>
                change({ ...doc, blocks: [...doc.blocks, newBlock('Section heading', 'heading')] })
              }
            >
              Add heading
            </button>
          </div>
        )}
        <InkLayer
          tool={tool}
          strokes={doc.ink}
          container={surface}
          onChange={(ink) => change({ ...doc, ink })}
          onLasso={lasso}
        />
      </div>
      <footer className="page-footer">
        <span>
          {doc.blocks.reduce(
            (sum, b) => sum + (b.text.trim() ? b.text.trim().split(/\s+/).length : 0),
            0,
          )}{' '}
          words · {doc.ink.length} ink strokes
        </span>
        <button className="text-button danger" onClick={onDelete}>
          Delete page
        </button>
      </footer>
      {notice && (
        <div className="toast" role="status">
          {notice}
        </div>
      )}
    </article>
  );
}
function TitleEditor({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  const ref = useRef<HTMLTextAreaElement>(null);
  const fit = () => {
    const element = ref.current;
    if (!element) return;
    element.style.height = '0px';
    element.style.height = `${element.scrollHeight}px`;
  };
  useEffect(fit, [value]);
  useEffect(() => {
    let width = 0;
    const observer = new ResizeObserver((entries) => {
      const next = entries[0].contentRect.width;
      if (next !== width) {
        width = next;
        fit();
      }
    });
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);
  return (
    <textarea
      ref={ref}
      rows={1}
      className="page-title"
      aria-label="Page title"
      value={value}
      maxLength={200}
      onChange={(e) => onChange(e.target.value.replace(/\n/g, ' '))}
      onKeyDown={(e) => {
        if (e.key === 'Enter') e.preventDefault();
      }}
    />
  );
}

function AutoTextarea({ block, onChange }: { block: Block; onChange: (text: string) => void }) {
  const ref = useRef<HTMLTextAreaElement>(null);
  const fit = useCallback(() => {
    const element = ref.current;
    if (!element) return;
    element.style.height = '0px';
    element.style.height = `${Math.max(block.kind === 'heading' ? 42 : 32, element.scrollHeight)}px`;
    element.scrollTop = 0;
  }, [block.kind]);
  useEffect(fit, [block.text, fit]);
  useEffect(() => {
    let width = -1;
    let frame = 0;
    const observer = new ResizeObserver(([entry]) => {
      if (entry.contentRect.width === width) return;
      width = entry.contentRect.width;
      // Defer height writes and ignore height-only notifications to avoid observer loops.
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(fit);
    });
    if (ref.current) observer.observe(ref.current);
    return () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
    };
  }, [fit]);
  return (
    <textarea
      ref={ref}
      aria-label={block.kind === 'heading' ? 'Section heading' : 'Note text'}
      className="block-editor"
      rows={1}
      maxLength={30000}
      placeholder="Start writing here…"
      value={block.text}
      onChange={(e) => onChange(e.target.value)}
    />
  );
}
