import { useEffect, useState } from 'react';
import { local } from '../storage';
import { download } from '../api';
import type { Page } from '../../shared/domain';
export function Recovery({ userId }: { userId: string }) {
  const [pages, setPages] = useState<Page[]>([]);
  useEffect(() => {
    void local.recoveries(userId).then(setPages);
  }, [userId]);
  return (
    <section className="settings-section">
      <h3>Device recovery</h3>
      <p>
        Drafts displaced by another tab or a conflict are retained here until you sign out. Download
        a copy before clearing this device.
      </p>
      {pages.length ? (
        pages.map((page, i) => (
          <div className="history-row" key={`${page.id}:${i}`}>
            <div>
              <strong>{page.title}</strong>
              <small>{new Date(page.updatedAt).toLocaleString()}</small>
            </div>
            <button
              onClick={() =>
                download(
                  JSON.stringify(page, null, 2),
                  'recovered-notebook-page.json',
                  'application/json',
                )
              }
            >
              Download draft
            </button>
          </div>
        ))
      ) : (
        <small>No displaced drafts on this device.</small>
      )}
    </section>
  );
}
