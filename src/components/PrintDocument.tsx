import type { Page } from '../../shared/domain';
export function PrintDocument({ page }: { page: Page }) {
  const included = page.document.blocks.filter((b) => !b.excluded);
  const ids = new Set(included.map((b) => b.id));
  const marks = page.document.annotations.filter((a) => ids.has(a.anchor.blockId));
  const strokes = page.document.ink;
  const bottom = strokes.reduce(
    (max, s) => s.points.reduce((m, p) => Math.max(m, p.y + 20), max),
    200,
  );
  return (
    <div className="print-document">
      <h1>{page.title}</h1>
      <p>Personal notes · {new Date(page.updatedAt).toLocaleDateString()}</p>
      {included.map((b) =>
        b.kind === 'heading' ? <h2 key={b.id}>{b.text}</h2> : <p key={b.id}>{b.text}</p>,
      )}
      {marks.length > 0 && (
        <>
          <h2>User marks</h2>
          {marks.map((a) => (
            <p key={a.id}>
              <strong>
                {a.kind} · {a.state}
              </strong>
              : “{a.anchor.quote}”{a.anchor.resolved ? '' : ' (source changed)'}
              {a.question ? `\n${a.question}` : ''}
            </p>
          ))}
        </>
      )}
      {page.document.meetingState === 'prepared' && (
        <>
          <h2>Preparation</h2>
          <p>Background only. This is not recorded discussion.</p>
          {Object.entries(page.document.preparation)
            .filter(([, v]) => v)
            .map(([key, value]) => (
              <section key={key}>
                <h3>{key}</h3>
                <p>{value}</p>
              </section>
            ))}
        </>
      )}
      {strokes.length > 0 && (
        <section className="print-ink">
          <h2>Handwriting and sketches</h2>
          <p>Ink is preserved separately from the reflowed text.</p>
          <svg viewBox={`0 0 800 ${bottom}`} aria-label="Handwriting">
            <g fill="none" strokeLinecap="round" strokeLinejoin="round">
              {strokes.map((s) => (
                <path
                  key={s.id}
                  d={s.points.map((p, i) => `${i ? 'L' : 'M'}${p.x} ${p.y}`).join(' ')}
                  stroke={s.color}
                  strokeWidth={s.width}
                />
              ))}
            </g>
          </svg>
        </section>
      )}
    </div>
  );
}
