import { openDB } from 'idb';
import type { Page, Notebook } from '../shared/domain';
export type LocalPage = {
  page: Page;
  mutationId?: string;
  conflict?: Page | null;
  writerId?: string;
  deviceState?: 'saving' | 'saved' | 'failed';
};
const writerId = crypto.randomUUID();
// Keep this stable across product renames so existing offline drafts remain available.
const database = openDB('meeting-notebook-v1', 1, {
  upgrade(db) {
    db.createObjectStore('pages');
    db.createObjectStore('meta');
    db.createObjectStore('recovery');
  },
});
export const local = {
  async pages(userId: string): Promise<LocalPage[]> {
    const db = await database;
    const keys = await db.getAllKeys('pages');
    const records = await Promise.all(
      keys.filter((k) => String(k).startsWith(`${userId}:`)).map((k) => db.get('pages', k)),
    );
    return records;
  },
  async put(userId: string, value: LocalPage) {
    const db = await database;
    const tx = db.transaction(['pages', 'recovery'], 'readwrite');
    const key = `${userId}:${value.page.id}`;
    const previous: LocalPage | undefined = await tx.objectStore('pages').get(key);
    if (
      previous?.mutationId &&
      previous.writerId !== writerId &&
      previous.mutationId !== value.mutationId
    )
      await tx
        .objectStore('recovery')
        .put(previous.page, `${key}:${previous.writerId || 'previous'}`);
    await tx.objectStore('pages').put({ ...value, writerId }, key);
    await tx.done;
  },
  async remove(userId: string, pageId: string) {
    return (await database).delete('pages', `${userId}:${pageId}`);
  },
  async notebooks(userId: string, notebooks?: Notebook[]): Promise<Notebook[]> {
    const db = await database;
    if (notebooks) await db.put('meta', notebooks, `notebooks:${userId}`);
    return (await db.get('meta', `notebooks:${userId}`)) || [];
  },
  async identity(value?: { id: string; name: string; email: string } | null) {
    const db = await database;
    if (value !== undefined) {
      if (value === null) await db.delete('meta', 'identity');
      else await db.put('meta', value, 'identity');
    }
    return db.get('meta', 'identity');
  },
  async acceptedLegalVersion(userId: string, version?: string | null): Promise<string | null> {
    const db = await database;
    const key = `legal:${userId}`;
    if (version !== undefined) {
      if (version === null) await db.delete('meta', key);
      else await db.put('meta', version, key);
    }
    return (await db.get('meta', key)) || null;
  },
  async recover(userId: string, page: Page) {
    return (await database).put('recovery', page, `${userId}:${page.id}:${Date.now()}`);
  },
  async recoveries(userId: string): Promise<Page[]> {
    const db = await database;
    const keys = await db.getAllKeys('recovery');
    return Promise.all(
      keys.filter((k) => String(k).startsWith(`${userId}:`)).map((k) => db.get('recovery', k)),
    );
  },
  async clear(userId: string) {
    const db = await database;
    const tx = db.transaction(['pages', 'recovery', 'meta'], 'readwrite');
    for (const store of ['pages', 'recovery'] as const) {
      const objectStore = tx.objectStore(store);
      for (const key of await objectStore.getAllKeys())
        if (String(key).startsWith(`${userId}:`)) await objectStore.delete(key);
    }
    const metadata = tx.objectStore('meta');
    await metadata.delete(`notebooks:${userId}`);
    await metadata.delete(`legal:${userId}`);
    await metadata.delete('identity');
    await tx.done;
  },
};
