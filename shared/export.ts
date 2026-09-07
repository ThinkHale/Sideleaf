import type { Page } from './domain.js';

export function exportMarkdown(page: Page, includePrivate = false): string {
  const blocks = page.document.blocks.filter((b) => includePrivate || !b.excluded);
  const allowed = new Set(blocks.map((b) => b.id));
  const lines = [
    `# ${page.title}`,
    '',
    '## Personal notes',
    '',
    ...blocks.map((b) => `${b.kind === 'heading' ? '### ' : ''}${b.text}`),
    '',
    '## User marks',
    '',
  ];
  for (const a of page.document.annotations.filter((a) => allowed.has(a.anchor.blockId)))
    lines.push(
      `- ${a.kind} (${a.state}${a.anchor.resolved ? '' : ', unresolved source'}): "${a.anchor.quote}"${a.question ? `\n  ${a.question}` : ''}`,
    );
  const p = page.document.preparation;
  if (Object.entries(p).some(([k, v]) => k !== 'type' && v)) {
    lines.push('', '## Preparation (background, not recorded discussion)', '');
    for (const [key, value] of Object.entries(p)) if (value) lines.push(`### ${key}`, value, '');
  }
  if (page.document.ink.length)
    lines.push(
      '',
      '[This text export excludes drawing strokes. Use Print / PDF or the full data export to preserve ink.]',
    );
  return lines.join('\n\n');
}
