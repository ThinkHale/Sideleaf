import { useCallback, useEffect, useRef, useState } from 'react';
import type { Notebook, Page } from '../shared/domain';
import { emptyDocument } from '../shared/domain';
import { api, ApiError } from './api';
import { local, type LocalPage } from './storage';

export function useNotebook(userId: string) {
  const [records, setRecords] = useState<LocalPage[]>([]);
  const [notebooks, setNotebooks] = useState<Notebook[]>([]);
  const [ready, setReady] = useState(false);
  const [online, setOnline] = useState(navigator.onLine);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const current = useRef<LocalPage[]>([]);
  const inFlight = useRef(false);
  const mounted = useRef(true);
  const update = useCallback((items: LocalPage[]) => {
    current.current = items;
    if (mounted.current) setRecords([...items]);
  }, []);
  useEffect(() => {
    const warn = (event: BeforeUnloadEvent) => {
      if (current.current.some((r) => r.deviceState === 'saving' || r.deviceState === 'failed')) {
        event.preventDefault();
        event.returnValue = '';
      }
    };
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, []);
  useEffect(() => {
    mounted.current = true;
    const changed = () => setOnline(navigator.onLine);
    window.addEventListener('online', changed);
    window.addEventListener('offline', changed);
    return () => {
      mounted.current = false;
      window.removeEventListener('online', changed);
      window.removeEventListener('offline', changed);
    };
  }, []);
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [cached, books] = await Promise.all([local.pages(userId), local.notebooks(userId)]);
      if (cancelled) return;
      update(cached);
      setNotebooks(books);
      try {
        const [remote, remoteBooks] = await Promise.all([
          api<Page[]>('/pages'),
          api<Notebook[]>('/notebooks'),
        ]);
        const merged = remote.map(
          (page) => cached.find((r) => r.page.id === page.id && r.mutationId) || { page },
        );
        merged.push(
          ...cached.filter((r) => r.mutationId && !remote.some((p) => p.id === r.page.id)),
        );
        await Promise.all(merged.map((r) => local.put(userId, r)));
        for (const stale of cached.filter(
          (r) => !r.mutationId && !remote.some((p) => p.id === r.page.id),
        ))
          await local.remove(userId, stale.page.id);
        await local.notebooks(userId, remoteBooks);
        if (!cancelled) {
          update(merged);
          setNotebooks(remoteBooks);
        }
      } catch {
        if (!cancelled)
          setError(
            navigator.onLine
              ? 'Server unavailable. Cached notes remain editable.'
              : 'Offline. Your notes stay on this device until reconnection.',
          );
      }
      if (!cancelled) setReady(true);
    })().catch(() => {
      setError('Device storage is unavailable. Enable browser storage before editing.');
    });
    return () => {
      cancelled = true;
    };
  }, [userId, update]);

  const edit = useCallback(
    async (page: Page) => {
      const old = current.current.find((r) => r.page.id === page.id);
      const record: LocalPage = {
        page: {
          ...page,
          version: old?.page.version ?? page.version,
          updatedAt: new Date().toISOString(),
        },
        mutationId: crypto.randomUUID(),
        deviceState: 'saving',
        ...(old?.conflict !== undefined ? { conflict: old.conflict } : {}),
      };
      update([...current.current.filter((r) => r.page.id !== page.id), record]);
      try {
        await local.put(userId, { ...record, deviceState: 'saved' });
        update(
          current.current.map((r) =>
            r.mutationId === record.mutationId ? { ...r, deviceState: 'saved' } : r,
          ),
        );
      } catch {
        update(
          current.current.map((r) =>
            r.mutationId === record.mutationId ? { ...r, deviceState: 'failed' } : r,
          ),
        );
        setError('Could not save to device storage. Keep this tab open and export your notes.');
      }
    },
    [userId, update],
  );

  const sync = useCallback(async () => {
    if (inFlight.current || !navigator.onLine || !ready) return;
    inFlight.current = true;
    setSaving(true);
    try {
      for (const pending of [...current.current]) {
        if (!pending.mutationId || pending.conflict !== undefined) continue;
        const p = pending.page;
        try {
          const saved = await api<Page>(`/pages/${p.id}`, {
            method: 'PUT',
            body: JSON.stringify({
              title: p.title || 'Untitled page',
              notebookId: p.notebookId,
              document: p.document,
              baseVersion: p.version,
              mutationId: pending.mutationId,
            }),
          });
          const latest = current.current.find((r) => r.page.id === p.id);
          if (!latest) continue;
          const next: LocalPage =
            latest.mutationId === pending.mutationId
              ? { page: saved }
              : { ...latest, page: { ...latest.page, version: saved.version } };
          update(current.current.map((r) => (r.page.id === p.id ? next : r)));
          await local.put(userId, next);
          setError('');
        } catch (err) {
          if (err instanceof ApiError && err.status === 409) {
            const latest = current.current.find((r) => r.page.id === p.id)!;
            const next = { ...latest, conflict: (err.data.current as Page | null) ?? null };
            update(current.current.map((r) => (r.page.id === p.id ? next : r)));
            await local.put(userId, next);
          } else {
            setError(
              err instanceof ApiError
                ? err.message
                : 'Connection interrupted. Your draft is saved on this device.',
            );
            break;
          }
        }
      }
    } finally {
      inFlight.current = false;
      if (mounted.current) setSaving(false);
    }
  }, [ready, userId, update]);
  useEffect(() => {
    const timer = setTimeout(sync, 700);
    return () => clearTimeout(timer);
  }, [records, online, sync]);
  useEffect(() => {
    const timer = setInterval(sync, 10000);
    return () => clearInterval(timer);
  }, [sync]);

  async function addNotebook(name: string) {
    const notebook = await api<Notebook>('/notebooks', {
      method: 'POST',
      body: JSON.stringify({ id: crypto.randomUUID(), name }),
    });
    const next = [...notebooks, notebook];
    setNotebooks(next);
    await local.notebooks(userId, next);
    return notebook;
  }
  async function addPage(notebookId: string, title = 'Untitled page', document = emptyDocument()) {
    const page: Page = {
      id: crypto.randomUUID(),
      title,
      notebookId,
      document,
      version: 0,
      updatedAt: new Date().toISOString(),
    };
    await edit(page);
    return page;
  }
  async function resolveConflict(id: string, choice: 'copy' | 'server') {
    const record = current.current.find((r) => r.page.id === id)!;
    if (record.conflict === undefined) return;
    await local.recover(userId, record.page);
    let copy: Page | undefined;
    if (choice === 'copy')
      copy = await addPage(
        record.page.notebookId,
        `${record.page.title} (recovered copy)`,
        record.page.document,
      );
    const server = record.conflict;
    const next = current.current.filter((r) => r.page.id !== id);
    if (server) {
      next.push({ page: server });
      await local.put(userId, { page: server });
    } else await local.remove(userId, id);
    update(next);
    return copy;
  }
  async function deletePage(id: string) {
    if (inFlight.current) throw new Error('Wait for the current save before deleting this page.');
    const record = current.current.find((r) => r.page.id === id);
    if (record?.page.version) await api(`/pages/${id}`, { method: 'DELETE' });
    await local.remove(userId, id);
    update(current.current.filter((r) => r.page.id !== id));
  }
  return {
    records,
    notebooks,
    ready,
    online,
    error,
    saving,
    edit,
    sync,
    addNotebook,
    addPage,
    resolveConflict,
    deletePage,
    hasPending: () => current.current.some((r) => r.mutationId),
  };
}
