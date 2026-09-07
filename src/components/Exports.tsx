import { useState } from 'react';
import { Copy, Download, Printer, Check } from 'lucide-react';
import { Modal } from './Modal';
import { download } from '../api';
import { exportMarkdown } from '../../shared/export';
import type { Page } from '../../shared/domain';
export function Exports({ page, onClose }: { page: Page; onClose: () => void }) {
  const [copied, setCopied] = useState(false),
    [error, setError] = useState('');
  const filename = page.title.replace(/[^a-z0-9 -]/gi, '').trim() || 'notebook';
  return (
    <Modal title="Take your notes with you" onClose={onClose}>
      <p className="muted">Export the current page, user marks, and preparation.</p>
      <div className="export-options">
        <button
          onClick={async () => {
            try {
              await navigator.clipboard.writeText(exportMarkdown(page));
              setCopied(true);
            } catch {
              setError('Clipboard unavailable. Download the text instead.');
            }
          }}
        >
          {copied ? <Check /> : <Copy />}
          {copied ? 'Copied' : 'Copy Markdown'}
        </button>
        <button onClick={() => download(exportMarkdown(page), `${filename}.md`)}>
          <Download />
          Markdown
        </button>
        <button
          onClick={() =>
            download(
              exportMarkdown(page).replace(/^#{1,3} /gm, ''),
              `${filename}.txt`,
              'text/plain',
            )
          }
        >
          <Download />
          Plain text
        </button>
        <button
          onClick={() => {
            onClose();
            setTimeout(() => window.print(), 150);
          }}
        >
          <Printer />
          Print / Save as PDF
        </button>
      </div>
      <p className="fine-print">
        Excluded text blocks and their marks are omitted. Ink is included in print/PDF, and may
        itself contain private information. Handwriting remains editable in the account data export.
      </p>
      {error && <p className="error">{error}</p>}
    </Modal>
  );
}
