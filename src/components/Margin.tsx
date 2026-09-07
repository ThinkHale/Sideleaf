import { Flag, Check, X, Clock3, Mic, MicOff, ShieldCheck, ChevronRight, Star } from 'lucide-react';
import type { Annotation, Page } from '../../shared/domain';
export function Margin({
  page,
  microphoneLive,
  onPrepare,
  onChange,
}: {
  page: Page;
  microphoneLive: boolean;
  onPrepare: () => void;
  onChange: (p: Page) => void;
}) {
  const items = page.document.annotations.filter(
    (a) => a.kind !== 'important' && a.state === 'open',
  );
  const rest = page.document.annotations.filter(
    (a) =>
      a.kind !== 'important' &&
      (a.state === 'later' || (a.state === 'open' && !items.slice(0, 2).includes(a))),
  );
  const important = page.document.annotations.filter(
    (a) => a.kind === 'important' && a.state !== 'dismissed',
  );
  function update(a: Annotation, patch: Partial<Annotation>) {
    onChange({
      ...page,
      document: {
        ...page.document,
        annotations: page.document.annotations.map((i) => (i.id === a.id ? { ...i, ...patch } : i)),
      },
    });
  }
  function remove(id: string) {
    onChange({
      ...page,
      document: {
        ...page.document,
        annotations: page.document.annotations.filter((a) => a.id !== id),
      },
    });
  }
  function item(a: Annotation) {
    return (
      <div className="followup" key={a.id}>
        <div className="followup-label">
          <Flag size={14} />
          {a.kind === 'action' ? 'Action draft' : 'Your follow-up'}
          {!a.anchor.resolved && <span className="unresolved">Source changed</span>}
        </div>
        <textarea
          aria-label={a.kind === 'action' ? 'Action draft' : 'Follow-up question'}
          value={a.question}
          onChange={(e) => update(a, { question: e.target.value })}
          rows={3}
        />
        <a
          className="source-link"
          href={`#source-${a.anchor.blockId}`}
          onClick={(e) => {
            e.preventDefault();
            document
              .getElementById(`source-${a.anchor.blockId}`)
              ?.scrollIntoView({ block: 'center', behavior: 'instant' });
          }}
        >
          “{a.anchor.quote}”
        </a>
        {!a.anchor.resolved && (
          <small>The original quote is preserved. Review it before using this item.</small>
        )}
        <div className="followup-actions">
          <button
            aria-label="Mark addressed"
            title="Addressed"
            onClick={() => update(a, { state: 'addressed' })}
          >
            <Check size={16} />
          </button>
          <button
            aria-label="Save for later"
            title="Save for later"
            onClick={() => update(a, { state: 'later' })}
          >
            <Clock3 size={16} />
          </button>
          <button
            aria-label="Dismiss follow-up"
            title="Dismiss"
            onClick={() => update(a, { state: 'dismissed' })}
          >
            <X size={16} />
          </button>
        </div>
      </div>
    );
  }
  return (
    <aside className="margin">
      <section>
        <h2>Meeting preparation</h2>
        <p>
          {page.document.meetingState === 'prepared'
            ? page.document.preparation.outcome || 'Your preparation is saved.'
            : 'A little context goes a long way.'}
        </p>
        <button className="primary full" onClick={onPrepare}>
          {page.document.meetingState === 'prepared' ? 'Review preparation' : 'Prepare a meeting'}
        </button>
        {page.document.meetingState === 'prepared' && (
          <small className="context-note">Background only. This is not recorded discussion.</small>
        )}
      </section>
      <section className="followups">
        <h2>Follow-ups{items.length > 0 && <span className="count">{items.length}</span>}</h2>
        {items.length ? (
          items.slice(0, 2).map(item)
        ) : (
          <p className="muted">Mark a phrase to keep a question close.</p>
        )}
        {rest.length > 0 && (
          <details>
            <summary>
              {rest.length} saved or queued <ChevronRight size={15} />
            </summary>
            {rest.map(item)}
          </details>
        )}
        {page.document.annotations.some(
          (a) => a.kind !== 'important' && ['addressed', 'dismissed'].includes(a.state),
        ) && (
          <details>
            <summary>Resolved items</summary>
            {page.document.annotations
              .filter((a) => a.kind !== 'important' && ['addressed', 'dismissed'].includes(a.state))
              .map((a) => (
                <div key={a.id} className="resolved-item">
                  <span>{a.question}</span>
                  <button className="text-button" onClick={() => update(a, { state: 'open' })}>
                    Reopen
                  </button>
                  <button className="text-button" onClick={() => remove(a.id)}>
                    Remove
                  </button>
                </div>
              ))}
          </details>
        )}
      </section>
      {important.length > 0 && (
        <section>
          <h2>Important</h2>
          {important.map((a) => (
            <div key={a.id} className="important-item">
              <Star size={15} />
              <div>
                <a
                  href={`#source-${a.anchor.blockId}`}
                  onClick={(e) => {
                    e.preventDefault();
                    document
                      .getElementById(`source-${a.anchor.blockId}`)
                      ?.scrollIntoView({ block: 'center' });
                  }}
                >
                  {a.anchor.quote}
                </a>
                {!a.anchor.resolved && (
                  <small className="unresolved">Source changed. Original quote retained.</small>
                )}
              </div>
              <button className="icon-button" aria-label="Remove mark" onClick={() => remove(a.id)}>
                <X size={14} />
              </button>
            </div>
          ))}
        </section>
      )}
      <div className="margin-privacy">
        <p>
          <ShieldCheck size={19} />
          Privacy by design.
        </p>
        <small aria-live="polite">
          {microphoneLive ? <Mic size={14} /> : <MicOff size={14} />}
          {microphoneLive ? 'Your microphone is live.' : 'Your microphone is off.'}
        </small>
      </div>
    </aside>
  );
}
